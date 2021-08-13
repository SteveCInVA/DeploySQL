function Get-DbaWindowsLog {
    <#
    .SYNOPSIS
        Gets Windows Application events associated with an instance

    .DESCRIPTION
        Gets Windows Application events associated with an instance

    .PARAMETER SqlInstance
        The instance(s) to retrieve the event logs from

    .PARAMETER Start
        Default: 1970
        Retrieve all events starting from this timestamp.

    .PARAMETER End
        Default: Now
        Retrieve all events that happened before this timestamp

    .PARAMETER Credential
        Credential to be used to connect to the Server. Note this is a Windows credential, as this command requires we communicate with the computer and not with the SQL instance.

    .PARAMETER MaxThreads
        Default: Unlimited
        The maximum number of parallel threads used on the local computer.
        Given that those will mostly be waiting for the remote system, there is usually no need to limit this.

    .PARAMETER MaxRemoteThreads
        Default: 2
        The maximum number of parallel threads that are executed on the target sql server.
        These processes will cause considerable CPU load, so a low limit is advisable in most scenarios.
        Any value lower than 1 disables the limit

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Logging
        Author: Drew Furgiuele | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaWindowsLog

    .EXAMPLE
        PS C:\> $ErrorLogs = Get-DbaWindowsLog -SqlInstance sql01\sharepoint
        PS C:\> $ErrorLogs | Where-Object ErrorNumber -eq 18456

        Returns all lines in the errorlogs that have event number 18456 in them

    #>
    #This exists to ignore the Script Analyzer rule for Start-Runspace
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]
        $SqlInstance = $env:COMPUTERNAME,

        [DateTime]
        $Start = "1/1/1970 00:00:00",

        [DateTime]
        $End = (Get-Date),


        [System.Management.Automation.PSCredential]
        $Credential,

        [int]
        $MaxThreads = 0,

        [int]
        $MaxRemoteThreads = 2,

        [switch]$EnableException
    )

    begin {
        Write-Message -Level Debug -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        #region Helper Functions
        function Start-Runspace {
            $Powershell = [PowerShell]::Create().AddScript($scriptBlock_ParallelRemoting).AddParameter("SqlInstance", $instance).AddParameter("Start", $Start).AddParameter("End", $End).AddParameter("Credential", $Credential).AddParameter("MaxRemoteThreads", $MaxRemoteThreads).AddParameter("ScriptBlock", $scriptBlock_RemoteExecution)
            $Powershell.RunspacePool = $RunspacePool
            Write-Message -Level Verbose -Message "Launching remote runspace against <c='green'>$instance</c>" -Target $instance
            $null = $RunspaceCollection.Add((New-Object -TypeName PSObject -Property @{ Runspace = $PowerShell.BeginInvoke(); PowerShell = $PowerShell; Instance = $instance.FullSmoName }))
        }

        function Receive-Runspace {
            [Parameter()]
            param (
                [switch]
                $Wait
            )

            do {
                foreach ($Run in $RunspaceCollection.ToArray()) {
                    if ($Run.Runspace.IsCompleted) {
                        Write-Message -Level Verbose -Message "Receiving results from <c='green'>$($Run.Instance)</c>" -Target $Run.Instance
                        $Run.PowerShell.EndInvoke($Run.Runspace)
                        $Run.PowerShell.Dispose()
                        $RunspaceCollection.Remove($Run)
                    }
                }

                if ($Wait -and ($RunspaceCollection.Count -gt 0)) { Start-Sleep -Milliseconds 250 }
            }
            while ($Wait -and ($RunspaceCollection.Count -gt 0))
        }
        #endregion Helper Functions

        #region Scriptblocks
        $scriptBlock_RemoteExecution = {
            param (
                [System.DateTime]
                $Start,

                [System.DateTime]
                $End,

                [string]
                $InstanceName,

                [int]
                $Throttle
            )

            #region Helper function
            function Convert-ErrorRecord {
                param (
                    $Line
                )

                if (Get-Variable -Name codesAndStuff -Scope 1) {
                    $line2 = (Get-Variable -Name codesAndStuff -Scope 1).Value
                    Remove-Variable -Name codesAndStuff -Scope 1

                    $groups = [regex]::Matches($line2, '^([\d- :]+.\d\d) (\w+)[ ]+Error: (\d+), Severity: (\d+), State: (\d+)').Groups
                    $groups2 = [regex]::Matches($line, '^[\d- :]+.\d\d \w+[ ]+(.*)$').Groups

                    New-Object PSObject -Property @{
                        Timestamp   = [DateTime]::ParseExact($groups[1].Value, "yyyy-MM-dd HH:mm:ss.ff", $null)
                        Spid        = $groups[2].Value
                        Message     = $groups2[1].Value
                        ErrorNumber = [int]($groups[3].Value)
                        Severity    = [int]($groups[4].Value)
                        State       = [int]($groups[5].Value)
                    }
                }

                if ($Line -match '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d\d[\w ]+((\w+): (\d+)[,\.]\s?){3}') {
                    Set-Variable -Name codesAndStuff -Value $Line -Scope 1
                }
            }
            #endregion Helper function

            #region Script that processes an individual file
            $scriptBlock = {
                param (
                    [System.IO.FileInfo]
                    $File
                )

                try {
                    $stream = New-Object System.IO.FileStream($File.FullName, "Open", "Read", "ReadWrite, Delete")
                    $reader = New-Object System.IO.StreamReader($stream)

                    while (-not $reader.EndOfStream) {
                        Convert-ErrorRecord -Line $reader.ReadLine()
                    }
                } catch {
                    # here to avoid an empty catch
                    $null = 1
                }
            }
            #endregion Script that processes an individual file

            #region Gather list of files to process
            $eventSource = "MSSQLSERVER"
            if ($InstanceName -notmatch "^DEFAULT$|^MSSQLSERVER$") {
                $eventSource = 'MSSQL$' + $InstanceName
            }

            $event = Get-WinEvent -FilterHashtable @{
                LogName      = "Application"
                ID           = 17111
                ProviderName = $eventSource
            } -MaxEvents 1 -ErrorAction SilentlyContinue

            if (-not $event) { return }

            $path = $event.Properties[0].Value
            $errorLogPath = Split-Path -Path $path
            $errorLogFileName = Split-Path -Path $path -Leaf
            $errorLogFiles = Get-ChildItem -Path $errorLogPath | Where-Object { ($_.Name -like "$errorLogFileName*") -and ($_.LastWriteTime -gt $Start) -and ($_.CreationTime -lt $End) }
            #endregion Gather list of files to process

            #region Prepare Runspaces
            [Collections.Arraylist]$RunspaceCollection = @()

            $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $Command = Get-Item function:Convert-ErrorRecord
            $InitialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($command.Name, $command.Definition)))

            $RunspacePool = [RunspaceFactory]::CreateRunspacePool($InitialSessionState)
            $null = $RunspacePool.SetMinRunspaces(1)
            if ($Throttle -gt 0) { $null = $RunspacePool.SetMaxRunspaces($Throttle) }
            $RunspacePool.Open()
            #endregion Prepare Runspaces

            #region Process Error files
            $countDone = 0
            $countStarted = 0
            $countTotal = ($errorLogFiles | Measure-Object).Count

            while ($countDone -lt $countTotal) {
                while (($RunspacePool.GetAvailableRunspaces() -gt 0) -and ($countStarted -lt $countTotal)) {
                    $Powershell = [PowerShell]::Create().AddScript($scriptBlock).AddParameter("File", $errorLogFiles[$countStarted])
                    $Powershell.RunspacePool = $RunspacePool
                    $null = $RunspaceCollection.Add((New-Object -TypeName PSObject -Property @{ Runspace = $PowerShell.BeginInvoke(); PowerShell = $PowerShell }))
                    $countStarted++
                }

                foreach ($Run in $RunspaceCollection.ToArray()) {
                    if ($Run.Runspace.IsCompleted) {
                        $Run.PowerShell.EndInvoke($Run.Runspace) | Where-Object { ($_.Timestamp -gt $Start) -and ($_.Timestamp -lt $End) }
                        $Run.PowerShell.Dispose()
                        $RunspaceCollection.Remove($Run)
                        $countDone++
                    }
                }

                Start-Sleep -Milliseconds 250
            }
            $RunspacePool.Close()
            $RunspacePool.Dispose()
            #endregion Process Error files
        }

        $scriptBlock_ParallelRemoting = {
            param (
                [DbaInstanceParameter]
                $SqlInstance,

                [DateTime]
                $Start,

                [DateTime]
                $End,

                [PSCredential]
                $Credential,

                [int]
                $MaxRemoteThreads,

                [System.Management.Automation.ScriptBlock]
                $ScriptBlock
            )

            $params = @{
                ArgumentList = $Start, $End, $SqlInstance.InstanceName, $MaxRemoteThreads
                ScriptBlock  = $ScriptBlock
            }
            if (-not $SqlInstance.IsLocalhost) { $params["ComputerName"] = $SqlInstance.ComputerName }
            if ($Credential) { $params["Credential"] = $Credential }

            Invoke-Command @params | Select-Object @{ n = "InstanceName"; e = { $SqlInstance.FullSmoName } }, Timestamp, Spid, Severity, ErrorNumber, State, Message
        }
        #endregion Scriptblocks

        #region Setup Runspace
        [Collections.Arraylist]$RunspaceCollection = @()
        $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $defaultrunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
        $RunspacePool = [RunspaceFactory]::CreateRunspacePool($InitialSessionState)
        $RunspacePool.SetMinRunspaces(1) | Out-Null
        if ($MaxThreads -gt 0) { $null = $RunspacePool.SetMaxRunspaces($MaxThreads) }
        $RunspacePool.Open()

        $countStarted = 0
        #Variable marked as unused by PSScriptAnalyzer
        #$countReceived = 0
        #endregion Setup Runspace
    }

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level VeryVerbose -Message "Processing <c='green'>$instance</c>" -Target $instance
            Start-Runspace
            Receive-Runspace
        }
    }

    end {
        Receive-Runspace -Wait
        $RunspacePool.Close()
        $RunspacePool.Dispose()
        [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $defaultrunspace
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUazttfDhgEAfiXNBKYbA31G57
# ramgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFMZ7Fv5O/9GcVbukQW0ylW/+iNO+MA0GCSqGSIb3DQEBAQUABIIBALTYzCZ4
# ebCg6P9Sp0bXbdJT9IOc17+pjjDHqriWSa4gtMRGIqNz7jZMlaqAQj/Q6uaicuN9
# 4yowIY1unX0DpTOWAMHSL0k/XZFmnF5R/APdMyInPjsFjaivw6xpKc3qcxNIKRGN
# /Q3F8P6xxoQbcNbFNYcscBhzklHfJ4anJuF16a9l08OokyyxCmI5/B9fb6aANwvs
# gRk+CfnnK4o16iS/2raEQB87LHV2Hhq+0yG21teGdOpZOmMUlTo8DmorzEbhOFXq
# JvlW+4lhzDI0+J3cCrv/hr54iBR1ye74WNcpFRp1jLZFDZJmdwy+hWU8qjF7yyik
# geXm8/POJ+FgM/yhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzMFowLwYJKoZIhvcNAQkEMSIEIFM4T92VHf1A8fgA8pMgJg4W6ghZ
# VnYtTJMzE3MFXmh4MA0GCSqGSIb3DQEBAQUABIIBAAwzfjwHG00irdfw8bhLUxdK
# IXwjJCRbhelXoPwqwn4Vqel7QG5BrV3IwCie1JVHnUSC3Q/5qh5LyQbcX1zhJAaX
# pTSHMdjc4/XLgjxqcJMJBYswe/pEDuV1pHKG647BfGwxkCXBZIdcflVhriHafpzV
# xTV9mkyHWyOEYHmbkRNE3bSNqTRrLBpqEuefbTxOleZs+nIc3efYDFq+xlKlYfQ8
# 78en5XoVKJllxgPQNH3YL1alFmWvdkOo3kVls0+YGExMEX4qpQvUvx4KBYCu92Xz
# ciC1zzf4KW3DRRJ3nF56EhALUFKixdwguxgUBryvvmrDMSQuka4gRcJbJOLlxrM=
# SIG # End signature block
