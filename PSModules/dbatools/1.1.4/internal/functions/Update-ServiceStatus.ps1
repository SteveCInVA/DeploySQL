function Update-ServiceStatus {
    <#
    .SYNOPSIS
        Internal function. Sends start/stop request to a SQL Server service and wait for the result.

    .DESCRIPTION
        Accepts objects from Get-DbaService and performs a corresponding action.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Timeout
        How long to wait for the start/stop request completion before moving on.

    .PARAMETER InputObject
        A collection of services from Get-DbaService

    .PARAMETER Action
        Start or stop.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .NOTES
        Author: Kirill Kravtsov ( @nvarscar )
        Tags:
        dbatools PowerShell module (https://dbatools.io)
       Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        $InputObject = Get-DbaService -ComputerName sql1
        Update-ServiceStatus -InputObject $InputObject -Action 'stop' -Timeout 30
        Update-ServiceStatus -InputObject $InputObject -Action 'start' -Timeout 30

        Restarts SQL services on sql1

    .EXAMPLE
        $InputObject = Get-DbaService -ComputerName sql1
        $credential = Get-Credential
        Update-ServiceStatus -InputObject $InputObject -Action 'stop' -Timeout 0 -Credential $credential

        Stops SQL services on sql1 and waits indefinitely for them to stop. Uses $credential to authorize on the server.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [parameter(ValueFromPipeline, Mandatory)]
        [object[]]$InputObject,
        [parameter(Mandatory)]
        [string[]]$Action,
        [int]$Timeout = 60,
        [PSCredential] $Credential,
        [bool]$EnableException
    )
    begin {
        $callStack = Get-PSCallStack
        if ($callStack.Length -gt 1) {
            $callerName = $callStack[1].Command
        } else {
            $callerName = $callStack[0].Command
        }
        #Prepare the service control script block
        $svcControlBlock = {
            $group = $_.Group
            $computerName = $_.Name
            $servicePriorityCollection = $group.ServicePriority | Select-Object -unique | Sort-Object -Property @{ Expression = { [int]$_ }; Descending = $action -ne 'stop' }
            foreach ($priority in $servicePriorityCollection) {
                $services = $group | Where-Object { $_.ServicePriority -eq $priority }
                $servicesToRestart = @()
                foreach ($service in $services) {
                    if ('dbatools.DbaSqlService' -in $service.PSObject.TypeNames) {
                        $cimObject = $service._CimObject
                        if (($cimObject.State -eq 'Running' -and $action -eq 'start') -or ($cimObject.State -eq 'Stopped' -and $action -eq 'stop')) {
                            $service | Add-Member -Force -NotePropertyName Status -NotePropertyValue 'Successful' -PassThru |
                            Add-Member -Force -NotePropertyName Message -NotePropertyValue "The service is already $actionText, no action required" -PassThru
                    } elseif ($cimObject.StartMode -eq 'Disabled' -and $action -in 'start', 'restart') {
                        $service | Add-Member -Force -NotePropertyName Status -NotePropertyValue 'Failed' -PassThru |
                        Add-Member -Force -NotePropertyName Message -NotePropertyValue "The service is disabled and cannot be $actionText" -PassThru
                } else {
                    $servicesToRestart += $service
                }
            } else {
                throw "Unknown object in pipeline - make sure to use Get-DbaService cmdlet"
            }
        }
        #Set desired $action
        if ($action -in 'start', 'restart') {
            $methodName = 'StartService'
            $desiredState = 'Running'
            $undesiredState = 'Stopped'
        } elseif ($action -eq 'stop') {
            $methodName = 'StopService'
            $desiredState = 'Stopped'
            $undesiredState = 'Running'
        }
        $invokeResults = @()
        foreach ($service in $servicesToRestart) {
            if ($Pscmdlet.ShouldProcess("Sending $action request to service $($service.ServiceName) on $($service.ComputerName)")) {
                #Invoke corresponding CIM method
                $invokeResult = Invoke-CimMethod -InputObject $service._CimObject -MethodName $methodName
                $invokeResults += [psobject]@{
                    InvokeResult    = $invokeResult
                    ServiceState    = $invokeResult.State
                    ServiceExitCode = $invokeResult.ReturnValue
                    CheckPending    = $true
                    Service         = $service
                }
            }
        }

        $startTime = Get-Date
        if ($Pscmdlet.ShouldProcess("Waiting the services to $action on $computerName")) {
            #Wait for the service to complete the action until timeout
            while ($invokeResults.CheckPending -contains $true) {
                foreach ($result in ($invokeResults | Where-Object CheckPending -eq $true)) {
                    try {
                        #Refresh Cim instance - not using Get-DbaCmObject because module is not loaded here, but it only refreshes existing object
                        $result.Service._CimObject = $result.Service._CimObject | Get-CimInstance
                    } catch {
                        $result.ServiceExitCode = -3
                        $result.ServiceState = 'Unknown'
                        $result.CheckPending = $false
                        continue
                    }
                    $result.ServiceState = $result.Service._CimObject.State
                    #Failed or succeeded
                    if ($result.ServiceExitCode -ne 0 -or $result.ServiceState -eq $desiredState) {
                        $result.CheckPending = $false
                        continue
                    }
                    #Failed after being in the Pending state
                    if ($result.CheckPending -and $result.ServiceState -eq $undesiredState) {
                        $result.ServiceExitCode = -2
                        $result.CheckPending = $false
                        continue
                    }
                    #Timed out
                    if ($timeout -gt 0 -and ((Get-Date) - $startTime).TotalSeconds -gt $timeout) {
                        $result.ServiceExitCode = -1
                        $result.CheckPending = $false
                        continue
                    }
                    #Still pending - leave CheckPending as is and run again
                }
                Start-Sleep -Milliseconds 200
            }
        }
        foreach ($result in $invokeResults) {
            #Add status
            $status = switch ($result.ServiceExitCode) {
                0 { 'Successful' }
                10 { 'Successful ' } #Already running - FullText service is started automatically
                default { 'Failed' }
            }
            Add-Member -Force -InputObject $result.Service -NotePropertyName Status -NotePropertyValue $status
            #Add error message
            $errorMessageFromReturnValue = if ($result.ServiceExitCode -in 0..($errorCodes.Length - 1)) {
                $errorCodes[$result.ServiceExitCode]
            } else { "Unknown error." }
            $message = switch ($result.ServiceExitCode) {
                -2 { "The service failed to $action." }
                -1 { "The attempt to $action the service has timed out." }
                0 { "Service was successfully $actionText." }
                default { "The attempt to $action the service returned the following error: $errorMessageFromReturnValue" }
            }
            Add-Member -Force -InputObject $result.Service -NotePropertyName Message -NotePropertyValue $message
            # Refresh service state for the object
            if ($result.ServiceState) { $result.Service.State = $result.ServiceState }
            $result
        }
    }
}

$actionText = switch ($action) { stop { 'stopped' }; start { 'started' }; restart { 'restarted' } }
$errorCodes = Get-DbaServiceErrorMessage
}

process {
    #Group services for each computer
    $serviceComputerGroup = $InputObject | Group-Object -Property ComputerName
    foreach ($group in $serviceComputerGroup) {
        Write-Message -Message "Getting CIM objects from computer $($group.Name)"
        $serviceNames = $group.Group.ServiceName -join "' OR name = '"
        try {
            $svcCim = Get-DbaCmObject -ComputerName $group.Name -Namespace "root\cimv2" -query "SELECT * FROM Win32_Service WHERE name = '$serviceNames'" -Credential $credential
        } catch {
            Stop-Function -EnableException $EnableException -FunctionName $callerName -Message ("The attempt to get CIM session for the services on $($group.Name) returned the following error: " + ($_.Exception.Message -join ' ')) -Category ConnectionError -ErrorRecord $_
        }
        foreach ($service in $group.Group) {
            if ($cimObject = ($svcCim | Where-Object Name -eq $service.ServiceName)) {
                Add-Member -Force -InputObject $service -NotePropertyName _CimObject -NotePropertyValue $cimObject
            } else {
                Stop-Function -Message "Failed to retrieve service name $($service.ServiceName) from the CIM object collection - the service will not be processed" -Continue -Target $group.Name
            }
        }
    }
    if ($Pscmdlet.ShouldProcess("Running the following service action: $action")) {
        if ($serviceComputerGroup) {
            try {
                $serviceComputerGroup | Invoke-Parallel -ScriptBlock $svcControlBlock -Throttle 50 -ImportVariables | ForEach-Object {
                    if ($_.ServiceExitCode) {
                        $target = "$($_.Service.ServiceName) on $($_.Service.ComputerName)"
                        Write-Message -Level Warning -Message "($target) $($_.Service.Message)" -Target $target
                        if ($_.Service.ServiceType -eq 'Engine' -and $_.ServiceExitCode -eq 3) {
                            Write-Message -Level Warning -Message "($target) Run the command with '-Force' switch to force the restart of a dependent SQL Agent" -Target $target
                        }
                    }
                    $_.Service | Select-DefaultView -Property ComputerName, ServiceName, InstanceName, ServiceType, State, Status, Message
                }
            } catch {
                Stop-Function -Message "Multi-threaded execution returned an error" -ErrorRecord $_ -EnableException $EnableException -FunctionName $callerName
            }
        }
    }
}
end {
}
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUifs1yy22JmYlVim1lAv06WAn
# cPOgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgVGltZXN0YW1waW5nIENBMB4XDTIxMDEwMTAwMDAwMFoXDTMxMDEw
# NjAwMDAwMFowSDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMu
# MSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyMTCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAMLmYYRnxYr1DQikRcpja1HXOhFCvQp1dU2UtAxQ
# tSYQ/h3Ib5FrDJbnGlxI70Tlv5thzRWRYlq4/2cLnGP9NmqB+in43Stwhd4CGPN4
# bbx9+cdtCT2+anaH6Yq9+IRdHnbJ5MZ2djpT0dHTWjaPxqPhLxs6t2HWc+xObTOK
# fF1FLUuxUOZBOjdWhtyTI433UCXoZObd048vV7WHIOsOjizVI9r0TXhG4wODMSlK
# XAwxikqMiMX3MFr5FK8VX2xDSQn9JiNT9o1j6BqrW7EdMMKbaYK02/xWVLwfoYer
# vnpbCiAvSwnJlaeNsvrWY4tOpXIc7p96AXP4Gdb+DUmEvQECAwEAAaOCAbgwggG0
# MA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsG
# AQUFBwMIMEEGA1UdIAQ6MDgwNgYJYIZIAYb9bAcBMCkwJwYIKwYBBQUHAgEWG2h0
# dHA6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAfBgNVHSMEGDAWgBT0tuEgHf4prtLk
# YaWyoiWyyBc1bjAdBgNVHQ4EFgQUNkSGjqS6sGa+vCgtHUQ23eNqerwwcQYDVR0f
# BGowaDAyoDCgLoYsaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJl
# ZC10cy5jcmwwMqAwoC6GLGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFz
# c3VyZWQtdHMuY3JsMIGFBggrBgEFBQcBAQR5MHcwJAYIKwYBBQUHMAGGGGh0dHA6
# Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBPBggrBgEFBQcwAoZDaHR0cDovL2NhY2VydHMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJRFRpbWVzdGFtcGluZ0NB
# LmNydDANBgkqhkiG9w0BAQsFAAOCAQEASBzctemaI7znGucgDo5nRv1CclF0CiNH
# o6uS0iXEcFm+FKDlJ4GlTRQVGQd58NEEw4bZO73+RAJmTe1ppA/2uHDPYuj1UUp4
# eTZ6J7fz51Kfk6ftQ55757TdQSKJ+4eiRgNO/PT+t2R3Y18jUmmDgvoaU+2QzI2h
# F3MN9PNlOXBL85zWenvaDLw9MtAby/Vh/HUIAHa8gQ74wOFcz8QRcucbZEnYIpp1
# FUL1LTI4gdr0YKK6tFL7XOBhJCVPst/JKahzQ1HavWPWH1ub9y4bTxMd90oNcX6X
# t/Q/hOvB46NJofrOp79Wz7pZdmGJX36ntI5nePk2mOHLKNpbh6aKLzCCBRowggQC
# oAMCAQICEAMFu4YhsKFjX7/erhIE520wDQYJKoZIhvcNAQELBQAwcjELMAkGA1UE
# BhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2lj
# ZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUg
# U2lnbmluZyBDQTAeFw0yMDA1MTIwMDAwMDBaFw0yMzA2MDgxMjAwMDBaMFcxCzAJ
# BgNVBAYTAlVTMREwDwYDVQQIEwhWaXJnaW5pYTEPMA0GA1UEBxMGVmllbm5hMREw
# DwYDVQQKEwhkYmF0b29sczERMA8GA1UEAxMIZGJhdG9vbHMwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQC8v2N7q+O/vggBtpjmteofFo140k73JXQ5sOD6
# QLzjgija+scoYPxTmFSImnqtjfZFWmucAWsDiMVVro/6yGjsXmJJUA7oD5BlMdAK
# fuiq4558YBOjjc0Bp3NbY5ZGujdCmsw9lqHRAVil6P1ZpAv3D/TyVVq6AjDsJY+x
# rRL9iMc8YpD5tiAj+SsRSuT5qwPuW83ByRHqkaJ5YDJ/R82ZKh69AFNXoJ3xCJR+
# P7+pa8tbdSgRf25w4ZfYPy9InEvsnIRVZMeDjjuGvqr0/Mar73UI79z0NYW80yN/
# 7VzlrvV8RnniHWY2ib9ehZligp5aEqdV2/XFVPV4SKaJs8R9AgMBAAGjggHFMIIB
# wTAfBgNVHSMEGDAWgBRaxLl7KgqjpepxA8Bg+S32ZXUOWDAdBgNVHQ4EFgQU8MCg
# +7YDgENO+wnX3d96scvjniIwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsG
# AQUFBwMDMHcGA1UdHwRwMG4wNaAzoDGGL2h0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNv
# bS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMDWgM6Axhi9odHRwOi8vY3JsNC5kaWdp
# Y2VydC5jb20vc2hhMi1hc3N1cmVkLWNzLWcxLmNybDBMBgNVHSAERTBDMDcGCWCG
# SAGG/WwDATAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20v
# Q1BTMAgGBmeBDAEEATCBhAYIKwYBBQUHAQEEeDB2MCQGCCsGAQUFBzABhhhodHRw
# Oi8vb2NzcC5kaWdpY2VydC5jb20wTgYIKwYBBQUHMAKGQmh0dHA6Ly9jYWNlcnRz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNIQTJBc3N1cmVkSURDb2RlU2lnbmluZ0NB
# LmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4IBAQCPzflwlQwf1jak
# EqymPOc0nBxiY7F4FwcmL7IrTLhub6Pjg4ZYfiC79Akz5aNlqO+TJ0kqglkfnOsc
# jfKQzzDwcZthLVZl83igzCLnWMo8Zk/D2d4ZLY9esFwqPNvuuVDrHvgh7H6DJ/zP
# Vm5EOK0sljT0UQ6HQEwtouH5S8nrqCGZ8jKM/+DeJlm+rCAGGf7TV85uqsAn5JqD
# En/bXE1AlyG1Q5YiXFGS5Sf0qS4Nisw7vRrZ6Qc4NwBty4cAYjzDPDixorWI8+FV
# OUWKMdL7tV8i393/XykwsccCstBCp7VnSZN+4vgzjEJQql5uQfysjcW9rrb/qixp
# csPTKYRHMIIFMDCCBBigAwIBAgIQBAkYG1/Vu2Z1U0O1b5VQCDANBgkqhkiG9w0B
# AQsFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMTMxMDIyMTIwMDAwWhcNMjgxMDIyMTIwMDAwWjByMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQg
# Q29kZSBTaWduaW5nIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
# +NOzHH8OEa9ndwfTCzFJGc/Q+0WZsTrbRPV/5aid2zLXcep2nQUut4/6kkPApfmJ
# 1DcZ17aq8JyGpdglrA55KDp+6dFn08b7KSfH03sjlOSRI5aQd4L5oYQjZhJUM1B0
# sSgmuyRpwsJS8hRniolF1C2ho+mILCCVrhxKhwjfDPXiTWAYvqrEsq5wMWYzcT6s
# cKKrzn/pfMuSoeU7MRzP6vIK5Fe7SrXpdOYr/mzLfnQ5Ng2Q7+S1TqSp6moKq4Tz
# rGdOtcT3jNEgJSPrCGQ+UpbB8g8S9MWOD8Gi6CxR93O8vYWxYoNzQYIH5DiLanMg
# 0A9kczyen6Yzqf0Z3yWT0QIDAQABo4IBzTCCAckwEgYDVR0TAQH/BAgwBgEB/wIB
# ADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwMweQYIKwYBBQUH
# AQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYI
# KwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFz
# c3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmw0
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaG
# NGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RD
# QS5jcmwwTwYDVR0gBEgwRjA4BgpghkgBhv1sAAIEMCowKAYIKwYBBQUHAgEWHGh0
# dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwCgYIYIZIAYb9bAMwHQYDVR0OBBYE
# FFrEuXsqCqOl6nEDwGD5LfZldQ5YMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6en
# IZ3zbcgPMA0GCSqGSIb3DQEBCwUAA4IBAQA+7A1aJLPzItEVyCx8JSl2qB1dHC06
# GsTvMGHXfgtg/cM9D8Svi/3vKt8gVTew4fbRknUPUbRupY5a4l4kgU4QpO4/cY5j
# DhNLrddfRHnzNhQGivecRk5c/5CxGwcOkRX7uq+1UcKNJK4kxscnKqEpKBo6cSgC
# PC6Ro8AlEeKcFEehemhor5unXCBc2XGxDI+7qPjFEmifz0DLQESlE/DmZAwlCEIy
# sjaKJAL+L3J+HNdJRZboWR3p+nRka7LrZkPas7CM1ekN3fYBIM6ZMWM9CBoYs4Gb
# T8aTEAb8B4H6i9r5gkn3Ym6hU/oSlBiFLpKR6mhsRDKyZqHnGKSaZFHvMIIFMTCC
# BBmgAwIBAgIQCqEl1tYyG35B5AXaNpfCFTANBgkqhkiG9w0BAQsFADBlMQswCQYD
# VQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGln
# aWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0Ew
# HhcNMTYwMTA3MTIwMDAwWhcNMzEwMTA3MTIwMDAwWjByMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5n
# IENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvdAy7kvNj3/dqbqC
# mcU5VChXtiNKxA4HRTNREH3Q+X1NaH7ntqD0jbOI5Je/YyGQmL8TvFfTw+F+CNZq
# FAA49y4eO+7MpvYyWf5fZT/gm+vjRkcGGlV+Cyd+wKL1oODeIj8O/36V+/OjuiI+
# GKwR5PCZA207hXwJ0+5dyJoLVOOoCXFr4M8iEA91z3FyTgqt30A6XLdR4aF5FMZN
# JCMwXbzsPGBqrC8HzP3w6kfZiFBe/WZuVmEnKYmEUeaC50ZQ/ZQqLKfkdT66mA+E
# f58xFNat1fJky3seBdCEGXIX8RcG7z3N1k3vBkL9olMqT4UdxB08r8/arBD13ays
# 6Vb/kwIDAQABo4IBzjCCAcowHQYDVR0OBBYEFPS24SAd/imu0uRhpbKiJbLIFzVu
# MB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHkGCCsG
# AQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29t
# MEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRBc3N1cmVkSURSb290Q0EuY3J0MIGBBgNVHR8EejB4MDqgOKA2hjRodHRwOi8v
# Y3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMDqg
# OKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURS
# b290Q0EuY3JsMFAGA1UdIARJMEcwOAYKYIZIAYb9bAACBDAqMCgGCCsGAQUFBwIB
# FhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAsGCWCGSAGG/WwHATANBgkq
# hkiG9w0BAQsFAAOCAQEAcZUS6VGHVmnN793afKpjerN4zwY3QITvS4S/ys8DAv3F
# p8MOIEIsr3fzKx8MIVoqtwU0HWqumfgnoma/Capg33akOpMP+LLR2HwZYuhegiUe
# xLoceywh4tZbLBQ1QwRostt1AuByx5jWPGTlH0gQGF+JOGFNYkYkh2OMkVIsrymJ
# 5Xgf1gsUpYDXEkdws3XVk4WTfraSZ/tTYYmo9WuWwPRYaQ18yAGxuSh1t5ljhSKM
# Ycp5lH5Z/IwP42+1ASa2bKXuh1Eh5Fhgm7oMLSttosR+u8QlK0cCCHxJrhO24XxC
# QijGGFbPQTS2Zl22dHv1VjMiLyI2skuiSpXY9aaOUjGCBFwwggRYAgEBMIGGMHIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJ
# RCBDb2RlIFNpZ25pbmcgQ0ECEAMFu4YhsKFjX7/erhIE520wCQYFKw4DAhoFAKB4
# MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQB
# gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkE
# MRYEFOUfNwqmgDx+aE7wsGdR+zZph2ysMA0GCSqGSIb3DQEBAQUABIIBADOQ6q7l
# XCeWzcJSu7OFMG2UFa/QvsB4DYHx684Sbcdt76+xQU6vok6NLz/hYqPN6pFhK3pP
# +9AmG0fDuvXPnD1ha4ITCmaW1m+bvEmZThI4sG5VLvL0G+rSRevmZFgzIYeLx/Oz
# 4N7efWnXOVdySJET4ZH+NRPPWqq1FFocZ/SbtMIficnwAoyzJodBL7M+/LKoZ2gH
# KONdoM/FdnUKQGHbubMpv5JVMuGbD8/P0IS2hyETBCuyFp1dWZXAdJprIOV7CKL/
# 0NpZ0i34tWgQt0y1810Sp2jHxUPD7gJp/K3m43Wj+i00IcCJVn0+ZsA/3v9lxOC/
# ZdzgKeKhotRbI0mhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAzOVowLwYJKoZIhvcNAQkEMSIEIOgjqnndtyavsyYAe9ZPubEWjgkG
# ywPSlv7QL02YscXpMA0GCSqGSIb3DQEBAQUABIIBAAcek8tvQQchX8TmxvIHgF8E
# nd0bas8ZTI1lu3DZtVCzXTxxVeBPczMRbH0sEjWrbaVZlfsQkSDdd9es7eBx7nRV
# U+74m/lbQgVzHNuN5xvjFY9aBQ+/A2yO2+AJpslaHiPj4+pJVBk1Aj7ReO3UJuiK
# pfXFxSQtgOAHSawCCKt/zFVyKK/eCKCbxoRkoAi0EvIfE1oqQ9ETikfrFdxlEWDm
# tTHpyIBWkd5NipxcoO975q73ulVxFvU1stg+Ra7bAutlTtd4i3bskVWZENtVh4ZE
# XiEGwlm+N4/kpv00GtsYI2OshiXtKg+LL/41bRrjY2hROcP5M4/On4sFzg+7BbE=
# SIG # End signature block
