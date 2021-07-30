function Set-DbaStartupParameter {
    <#
    .SYNOPSIS
        Sets the Startup Parameters for a SQL Server instance

    .DESCRIPTION
        Modifies the startup parameters for a specified SQL Server Instance

        For full details of what each parameter does, please refer to this MSDN article - https://msdn.microsoft.com/en-us/library/ms190737(v=sql.105).aspx

    .PARAMETER SqlInstance
        The SQL Server instance to be modified

        If the Sql Instance is offline path parameters will be ignored as we cannot test the instance's access to the path. If you want to force this to work then please use the Force switch

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Windows Credential with permission to log on to the server running the SQL instance

    .PARAMETER MasterData
        Path to the data file for the Master database

        Will be ignored if SqlInstance is offline or the Offline switch is set. To override this behaviour use the Force switch. This is to ensure you understand the risk as we cannot validate the path if the instance is offline

    .PARAMETER MasterLog
        Path to the log file for the Master database

        Will be ignored if SqlInstance is offline or the Offline switch is set. To override this behaviour use the Force switch. This is to ensure you understand the risk as we cannot validate the path if the instance is offline

    .PARAMETER ErrorLog
        Path to the SQL Server error log file

        Will be ignored if SqlInstance is offline or the Offline switch is set. To override this behaviour use the Force switch. This is to ensure you understand the risk as we cannot validate the path if the instance is offline

    .PARAMETER TraceFlag
        A comma separated list of TraceFlags to be applied at SQL Server startup
        By default these will be appended to any existing trace flags set

    .PARAMETER CommandPromptStart
        Shortens startup time when starting SQL Server from the command prompt. Typically, the SQL Server Database Engine starts as a service by calling the Service Control Manager.
        Because the SQL Server Database Engine does not start as a service when starting from the command prompt

    .PARAMETER MinimalStart
        Starts an instance of SQL Server with minimal configuration. This is useful if the setting of a configuration value (for example, over-committing memory) has
        prevented the server from starting. Starting SQL Server in minimal configuration mode places SQL Server in single-user mode

    .PARAMETER MemoryToReserve
        Specifies an integer number of megabytes (MB) of memory that SQL Server will leave available for memory allocations within the SQL Server process,
        but outside the SQL Server memory pool. The memory outside of the memory pool is the area used by SQL Server for loading items such as extended procedure .dll files,
        the OLE DB providers referenced by distributed queries, and automation objects referenced in Transact-SQL statements. The default is 256 MB.

    .PARAMETER SingleUser
        Start Sql Server in single user mode

    .PARAMETER NoLoggingToWinEvents
        Don't use Windows Application events log

    .PARAMETER StartAsNamedInstance
        Allows you to start a named instance of SQL Server

    .PARAMETER DisableMonitoring
        Disables the following monitoring features:

        SQL Server performance monitor counters
        Keeping CPU time and cache-hit ratio statistics
        Collecting information for the DBCC SQLPERF command
        Collecting information for some dynamic management views
        Many extended-events event points

        ** Warning *\* When you use the -x startup option, the information that is available for you to diagnose performance and functional problems with SQL Server is greatly reduced.

    .PARAMETER SingleUserDetails
        The username for single user

    .PARAMETER IncreasedExtents
        Increases the number of extents that are allocated for each file in a file group.

    .PARAMETER TraceFlagOverride
        Overrides the default behaviour and replaces any existing trace flags. If not trace flags specified will just remove existing ones

    .PARAMETER StartupConfig
        Pass in a previously saved SQL Instance startup config
        using this parameter will set TraceFlagOverride to true, so existing Trace Flags will be overridden

    .PARAMETER Offline
        Setting this switch will try perform the requested actions without connect to the SQL Server Instance, this will speed things up if you know the Instance is offline.

        When working offline, path inputs (MasterData, MasterLog and ErrorLog) will be ignored, unless Force is specified

    .PARAMETER Force
        By default we test the values passed in via MasterData, MasterLog, ErrorLog

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Startup, Parameter, Configure
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaStartupParameter

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser

        Will configure the SQL Instance server1\instance1 to startup up in Single User mode at next startup

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016 -IncreasedExtents

        Will configure the SQL Instance sql2016 to IncreasedExtents = True (-E)

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016  -IncreasedExtents:$false -WhatIf

        Shows what would happen if you attempted to configure the SQL Instance sql2016 to IncreasedExtents = False (no -E)

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -TraceFlag 8032,8048

        This will append Trace Flags 8032 and 8048 to the startup parameters

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016 -SingleUser:$false -TraceFlagOverride

        This will remove all trace flags and set SingleUser to false

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser -TraceFlag 8032,8048 -TraceFlagOverride

        This will set Trace Flags 8032 and 8048 to the startup parameters, removing any existing Trace Flags

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016 -SingleUser:$false -TraceFlagOverride -Offline

        This will remove all trace flags and set SingleUser to false from an offline instance

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016 -ErrorLog c:\Sql\ -Offline

        This will attempt to change the ErrorLog path to c:\sql\. However, with the offline switch this will not happen. To force it, use the -Force switch like so:

        Set-DbaStartupParameter -SqlInstance sql2016 -ErrorLog c:\Sql\ -Offline -Force

    .EXAMPLE
        PS C:\> $StartupConfig = Get-DbaStartupParameter -SqlInstance server1\instance1
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser -NoLoggingToWinEvents
        PS C:\> #Restart your SQL instance with the tool of choice
        PS C:\> #Do Some work
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -StartupConfig $StartupConfig
        PS C:\> #Restart your SQL instance with the tool of choice and you're back to normal

        In this example we take a copy of the existing startup configuration of server1\instance1

        We then change the startup parameters ahead of some work

        After the work has been completed, we can push the original startup parameters back to server1\instance1 and resume normal operation
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param ([parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string]$MasterData,
        [string]$MasterLog,
        [string]$ErrorLog,
        [string[]]$TraceFlag,
        [switch]$CommandPromptStart,
        [switch]$MinimalStart,
        [int]$MemoryToReserve,
        [switch]$SingleUser,
        [string]$SingleUserDetails,
        [switch]$NoLoggingToWinEvents,
        [switch]$StartAsNamedInstance,
        [switch]$DisableMonitoring,
        [switch]$IncreasedExtents,
        [switch]$TraceFlagOverride,
        [object]$StartupConfig,
        [switch]$Offline,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
        $null = Test-ElevationRequirement -ComputerName $SqlInstance[0]
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            if (-not $Offline) {
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Write-Message -Level Warning -Message "Failed to connect to $instance, will try to work with just WMI. Path options will be ignored unless Force was indicated"
                    $Server = $instance
                    $Offline = $true
                }
            } else {
                Write-Message -Level Verbose -Message "Offline switch set, proceeding with just WMI"
                $server = $instance
            }

            # Get Current parameters (uses WMI) -- requires elevated session
            try {
                $currentStartup = Get-DbaStartupParameter -SqlInstance $instance -Credential $Credential -EnableException
            } catch {
                Stop-Function -Message "Unable to gather current startup parameters" -Target $instance -ErrorRecord $_
                return
            }
            $originalParamString = $currentStartup.ParameterString
            $parameterString = $null

            Write-Message -Level Verbose -Message "Original startup parameter string: $originalParamString"

            if ('StartupConfig' -in $PSBoundParameters.Keys) {
                Write-Message -Level VeryVerbose -Message "startupObject passed in"
                $newStartup = $StartupConfig
                $TraceFlagOverride = $true
            } else {
                Write-Message -Level VeryVerbose -Message "Parameters passed in"
                $newStartup = $currentStartup.PSObject.Copy()
                foreach ($param in ($PSBoundParameters.Keys | Where-Object { $_ -in ($newStartup.PSObject.Properties.Name) })) {
                    if ($PSBoundParameters.Item($param) -ne $newStartup.$param) {
                        $newStartup.$param = $PSBoundParameters.Item($param)
                    }
                }
            }

            if (!($currentStartup.SingleUser)) {

                if ($newStartup.MasterData.Length -gt 0) {
                    if ($Offline -and -not $Force) {
                        Write-Message -Level Warning -Message "Working offline, skipping untested MasterData path"
                        $parameterString += "-d$($currentStartup.MasterData);"

                    } else {
                        if ($Force) {
                            $parameterString += "-d$($newStartup.MasterData);"
                        } elseif (Test-DbaPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newStartup.MasterData -Parent)) {
                            $parameterString += "-d$($newStartup.MasterData);"
                        } else {
                            Stop-Function -Message "Specified folder for MasterData file is not reachable by instance $instance"
                            return
                        }
                    }
                } else {
                    Stop-Function -Message "MasterData value must be provided"
                    return
                }

                if ($newStartup.ErrorLog.Length -gt 0) {
                    if ($Offline -and -not $Force) {
                        Write-Message -Level Warning -Message "Working offline, skipping untested ErrorLog path"
                        $parameterString += "-e$($currentStartup.ErrorLog);"
                    } else {
                        if ($Force) {
                            $parameterString += "-e$($newStartup.ErrorLog);"
                        } elseif (Test-DbaPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newStartup.ErrorLog -Parent)) {
                            $parameterString += "-e$($newStartup.ErrorLog);"
                        } else {
                            Stop-Function -Message "Specified folder for ErrorLog  file is not reachable by $instance"
                            return
                        }
                    }
                } else {
                    Stop-Function -Message "ErrorLog value must be provided"
                    return
                }

                if ($newStartup.MasterLog.Length -gt 0) {
                    if ($Offline -and -not $Force) {
                        Write-Message -Level Warning -Message "Working offline, skipping untested MasterLog path"
                        $parameterString += "-l$($currentStartup.MasterLog);"
                    } else {
                        if ($Force) {
                            $parameterString += "-l$($newStartup.MasterLog);"
                        } elseif (Test-DbaPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newStartup.MasterLog -Parent)) {
                            $parameterString += "-l$($newStartup.MasterLog);"
                        } else {
                            Stop-Function -Message "Specified folder for MasterLog  file is not reachable by $instance"
                            return
                        }
                    }
                } else {
                    Stop-Function -Message "MasterLog value must be provided."
                    return
                }
            } else {

                Write-Message -Level Verbose -Message "Instance is presently configured for single user, skipping path validation"
                if ($newStartup.MasterData.Length -gt 0) {
                    $parameterString += "-d$($newStartup.MasterData);"
                } else {
                    Stop-Function -Message "Must have a value for MasterData"
                    return
                }
                if ($newStartup.ErrorLog.Length -gt 0) {
                    $parameterString += "-e$($newStartup.ErrorLog);"
                } else {
                    Stop-Function -Message "Must have a value for Errorlog"
                    return
                }
                if ($newStartup.MasterLog.Length -gt 0) {
                    $parameterString += "-l$($newStartup.MasterLog);"
                } else {
                    Stop-Function -Message "Must have a value for MasterLog"
                    return
                }
            }

            if ($newStartup.CommandPromptStart) {
                $parameterString += "-c;"
            }
            if ($newStartup.MinimalStart) {
                $parameterString += "-f;"
            }
            if ($newStartup.MemoryToReserve -notin ($null, 0)) {
                $parameterString += "-g$($newStartup.MemoryToReserve)"
            }
            if ($newStartup.SingleUser) {
                if ($SingleUserDetails.Length -gt 0) {
                    if ($SingleUserDetails -match ' ') {
                        $SingleUserDetails = """$SingleUserDetails"""
                    }
                    $parameterString += "-m$SingleUserDetails;"
                } else {
                    $parameterString += "-m;"
                }
            }
            if ($newStartup.NoLoggingToWinEvents) {
                $parameterString += "-n;"
            }
            If ($newStartup.StartAsNamedInstance) {
                $parameterString += "-s;"
            }
            if ($newStartup.DisableMonitoring) {
                $parameterString += "-x;"
            }
            if ($newStartup.IncreasedExtents) {
                $parameterString += "-E;"
            }
            if ($newStartup.TraceFlags -eq 'None') {
                $newStartup.TraceFlags = ''
            }
            if ($TraceFlagOverride -and 'TraceFlag' -in $PSBoundParameters.Keys) {
                if ($null -ne $TraceFlag -and '' -ne $TraceFlag) {
                    $newStartup.TraceFlags = $TraceFlag -join ','
                    $parameterString += (($TraceFlag.Split(',') | ForEach-Object { "-T$_" }) -join ';') + ";"
                }
            } else {
                if ('TraceFlag' -in $PSBoundParameters.Keys) {
                    if ($null -eq $TraceFlag) { $TraceFlag = '' }
                    $oldFlags = @($currentStartup.TraceFlags) -split ',' | Where-Object { $_ -ne 'None' }
                    $newFlags = $TraceFlag
                    $newStartup.TraceFlags = (@($oldFlags) + @($newFlags) | Sort-Object -Unique) -join ','
                } elseif ($TraceFlagOverride) {
                    $newStartup.TraceFlags = ''
                } else {
                    $newStartup.TraceFlags = if ($currentStartup.TraceFlags -eq 'None') { }
                    else { $currentStartup.TraceFlags -join ',' }
                }
                If ($newStartup.TraceFlags.Length -ne 0) {
                    $parameterString += (($newStartup.TraceFlags.Split(',') | ForEach-Object { "-T$_" }) -join ';') + ";"
                }
            }

            $instanceName = $instance.InstanceName
            $displayName = "SQL Server ($instanceName)"

            $scriptBlock = {
                #Variable marked as unused by PSScriptAnalyzer
                #$instance = $args[0]
                $displayName = $args[1]
                $parameterString = $args[2]

                $wmiSvc = $wmi.Services | Where-Object { $_.DisplayName -eq $displayName }
                $wmiSvc.StartupParameters = $parameterString
                $wmiSvc.Alter()
                $wmiSvc.Refresh()
                if ($wmiSvc.StartupParameters -eq $parameterString) {
                    $true
                } else {
                    $false
                }
            }
            if ($PSCmdlet.ShouldProcess("Setting startup parameters on $instance to $parameterString")) {
                try {
                    if ($Credential) {
                        $null = Invoke-ManagedComputerCommand -ComputerName $server.ComputerName -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $server.ComputerName, $displayName, $parameterString -EnableException

                        $output = Get-DbaStartupParameter -SqlInstance $server -Credential $Credential -EnableException
                        Add-Member -Force -InputObject $output -MemberType NoteProperty -Name OriginalStartupParameters -Value $originalParamString
                    } else {
                        $null = Invoke-ManagedComputerCommand -ComputerName $server.ComputerName -scriptBlock $scriptBlock -ArgumentList $server.ComputerName, $displayName, $parameterString -EnableException

                        $output = Get-DbaStartupParameter -SqlInstance $server -EnableException
                        Add-Member -Force -InputObject $output -MemberType NoteProperty -Name OriginalStartupParameters -Value $originalParamString
                        Add-Member -Force -InputObject $output -MemberType NoteProperty -Name Notes -Value "Startup parameters changed on $instance. You must restart SQL Server for changes to take effect."
                    }
                    $output
                } catch {
                    Stop-Function -Message "Startup parameter update failed on $instance. " -Target $instance -ErrorRecord $_
                    return
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU57rgidtiLfJ9iQhVfARV2B/m
# 28SgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFPCP2IzOcUE+mpVAmM4EZYtZN4apMA0GCSqGSIb3DQEBAQUABIIBADVqC8G7
# Gn47m3OYIGtQfqeC60ly15/LjtVlwJuDG31BGmHp4OxKf/AasIWhouLxh3gw0o9m
# K1TJgLdBu11IYHwup3bvdyZPQsK9x39RGsT1SpQoxrzq0Yh5LHuE+8vw0TgCd29V
# eyOCu4eRyi7/KHrylKlDEh48/jdB0H2tmTUnP37OccPZgXagfT8G5IKoM4Wx9S+A
# OlPz6qhgYQzoIIyu541ZhkgTBE9MRQ2e6hKy2gE09XbLPgl4NhE96lNx4V1sGwXH
# P40g/oPZhzAoy+WFcpcVHstOrEQZEMI6f8IN164ohMfaUWVm3CYDDx5UJub5DpA0
# MBNuQsFSN/Al+S6hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAxMFowLwYJKoZIhvcNAQkEMSIEIBRRCzo4sNqpQKubOp4weoGYYIy9
# SwSpeLL2XcW/BLgwMA0GCSqGSIb3DQEBAQUABIIBAL0Whv91MGkI9pKaARB0yleV
# 7xRG4Th0rlo1Y66bzVivbSTeV/mTl5N1I+iK/9cOuwtKe9vaukLy8sfPL5IZ/0Bs
# 9Zb6Pj25jiBFmrN1ruk56mQJuchYscVNi6TPQun8EEBMuI12b27y6LSCjMZBoywb
# 7epCXqcLFYX9y/6zKIfAPKKp/0bmmJQ41vk5auHvKsmXXFn+LM+Ke4gvJlleTang
# VldUdwZoevcaAsQ3iiez8oFZq2xU63J1NpAHUfAWc0MZOCWyDF3BqUKNgB/knAKG
# 0eN4Xvg5m5ZEacyQZm2TxE5jOU+U3xIYI1TGtxYEK1EFapeYbmve3d8smJaqEUo=
# SIG # End signature block
