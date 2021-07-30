function Invoke-DbaDbLogShipRecovery {
    <#
    .SYNOPSIS
        Invoke-DbaDbLogShipRecovery recovers log shipped databases to a normal state to act upon a migration or disaster.

    .DESCRIPTION
        By default all the databases for a particular instance are recovered.
        If the database is in the right state, either standby or recovering, the process will try to recover the database.

        At first the function will check if the backup source directory can still be reached.
        If so it will look up the last transaction log backup for the database. If that backup file is not the last copied file the log shipping copy job will be started.
        If the directory cannot be reached for the function will continue to the restoring process.
        After the copy job check is performed the job is disabled to prevent the job to run.

        For the restore the log shipping status is checked in the msdb database.
        If the last restored file is not the same as the last file name found, the log shipping restore job will be executed.
        After the restore job check is performed the job is disabled to prevent the job to run

        The last part is to set the database online by restoring the databases with recovery

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Database
        Database to perform the restore for. This value can also be piped enabling multiple databases to be recovered.
        If this value is not supplied all databases will be recovered.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER NoRecovery
        Allows you to choose to not restore the database to a functional state (Normal) in the final steps of the process.
        By default the database is restored to a functional state (Normal).

    .PARAMETER InputObject
        Allows piped input from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Use this parameter to force the function to continue and perform any adjusting actions to successfully execute

    .PARAMETER Delay
        Set the delay in seconds to wait for the copy and/or restore jobs.
        By default the delay is 5 seconds

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: LogShipping
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbLogShipRecovery

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1

        Recovers all the databases on the instance that are enabled for log shipping

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -SqlCredential $cred -Verbose

        Recovers all the databases on the instance that are enabled for log shipping using a credential

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -database db_logship -Verbose

        Recovers the database "db_logship" to a normal status

    .EXAMPLE
        PS C:\> db1, db2, db3, db4 | Invoke-DbaDbLogShipRecovery -SqlInstance server1 -Verbose

        Recovers the database db1, db2, db3, db4 to a normal status

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -WhatIf

        Shows what would happen if the command were executed.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param
    (
        [DbaInstanceParameter[]]$SqlInstance,
        [string[]]$Database,
        [PSCredential]$SqlCredential,
        [switch]$NoRecovery,
        [switch]$EnableException,
        [switch]$Force,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [int]$Delay = 5
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $stepCounter = 0
    }
    process {
        foreach ($instance in $SqlInstance) {
            if (-not $Force -and -not $Database) {
                Stop-Function -Message "You must specify a -Database or -Force for all databases" -Target $server.name
                return
            }
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        # Loop through all the databases
        foreach ($db in $InputObject) {
            $stepCounter = 0
            $server = $db.Parent
            $instance = $server.Name
            $activity = "Performing log shipping recovery for $($db.Name) on $($server.Name)"
            # Try to get the agent service details
            try {
                # Get the service details
                $agentStatus = $server.Query("SELECT COUNT(*) as AgentCount FROM master.dbo.sysprocesses WITH (nolock) WHERE Program_Name LIKE 'SQLAgent%'")

                if ($agentStatus.AgentCount -lt 1) {
                    Stop-Function -Message "The agent service is not in a running state. Please start the service." -ErrorRecord $_ -Target $server.name
                    return
                }
            } catch {
                Stop-Function -Message "Unable to get SQL Server Agent Service status" -ErrorRecord $_ -Target $server.name
                return
            }
            # Query for retrieving the log shipping information
            $query = "SELECT lss.primary_server, lss.primary_database, lsd.secondary_database, lss.backup_source_directory,
                    lss.backup_destination_directory, lss.last_copied_file, lss.last_copied_date,
                    lsd.last_restored_file, sj1.name AS 'copyjob', sj2.name AS 'restorejob'
                FROM msdb.dbo.log_shipping_secondary AS lss
                    INNER JOIN msdb.dbo.log_shipping_secondary_databases AS lsd ON lsd.secondary_id = lss.secondary_id
                    INNER JOIN msdb.dbo.sysjobs AS sj1 ON sj1.job_id = lss.copy_job_id
                    INNER JOIN msdb.dbo.sysjobs AS sj2 ON sj2.job_id = lss.restore_job_id
                WHERE lsd.secondary_database = '$($db.Name)'"

            # Retrieve the log shipping information from the secondary instance
            try {
                Write-Message -Message "Retrieving log shipping information from the secondary instance" -Level Verbose
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Retrieving log shipping information from the secondary instance"
                $logshipping_details = $server.Query($query)
            } catch {
                Stop-Function -Message "Error retrieving the log shipping details: $($_.Exception.Message)" -ErrorRecord $_ -Target $server.name
                return
            }

            # Check if there are any databases to recover
            if ($null -eq $logshipping_details) {
                Stop-Function -Message "The database $db is not configured as a secondary database for log shipping." -Continue
            } else {
                # Loop through each of the log shipped databases
                foreach ($ls in $logshipping_details) {
                    $secondarydb = $ls.secondary_database

                    $recoverResult = "Success"
                    $comment = ""
                    $jobOutputs = @()

                    # Check if the database is in the right state
                    if ($server.Databases[$secondarydb].Status -notin ('Normal, Standby', 'Standby', 'Restoring')) {
                        Stop-Function -Message "The database $db doesn't have the right status to be recovered" -Continue
                    } else {
                        Write-Message -Message "Started Recovery for $secondarydb" -Level Verbose

                        # Start the job to get the latest files
                        if ($PSCmdlet.ShouldProcess($server.name, ("Starting copy job $($ls.copyjob)"))) {
                            Write-Message -Message "Starting copy job $($ls.copyjob)" -Level Verbose

                            Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Starting copy job"
                            try {
                                $null = Start-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob
                            } catch {
                                $recoverResult = "Failed"
                                $comment = "Something went wrong starting the copy job $($ls.copyjob)"
                                Stop-Function -Message "Something went wrong starting the copy job.`n$($_)" -ErrorRecord $_ -Target $server.name
                            }

                            if ($recoverResult -ne 'Failed') {
                                Write-Message -Message "Copying files to $($ls.backup_destination_directory)" -Level Verbose

                                Write-Message -Message "Waiting for the copy action to complete.." -Level Verbose

                                # Get the job status
                                $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob

                                while ($jobStatus.CurrentRunStatus -ne 'Idle') {
                                    # Sleep for while to let the files be copied
                                    Start-Sleep -Seconds $Delay

                                    # Get the job status
                                    $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob
                                }

                                # Check the lat outcome of the job
                                if ($jobStatus.LastRunOutcome -eq 'Failed') {
                                    $recoverResult = "Failed"
                                    $comment = "The copy job for database $db failed. Please check the error log."
                                    Stop-Function -Message "The copy job for database $db failed. Please check the error log."
                                }

                                $jobOutputs += $jobStatus

                                Write-Message -Message "Copying of backup files finished" -Level Verbose
                            }
                        } # if should process

                        # Disable the log shipping copy job on the secondary instance
                        if ($recoverResult -ne 'Failed') {
                            Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Disabling copy job"

                            if ($PSCmdlet.ShouldProcess($server.name, "Disabling copy job $($ls.copyjob)")) {
                                try {
                                    Write-Message -Message "Disabling copy job $($ls.copyjob)" -Level Verbose
                                    $null = Set-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob -Disabled
                                } catch {
                                    $recoverResult = "Failed"
                                    $comment = "Something went wrong disabling the copy job."
                                    Stop-Function -Message "Something went wrong disabling the copy job.`n$($_)" -ErrorRecord $_ -Target $server.name
                                }
                            }
                        }

                        if ($recoverResult -ne 'Failed') {
                            # Start the restore job
                            Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Starting restore job"

                            if ($PSCmdlet.ShouldProcess($server.name, ("Starting restore job " + $ls.restorejob))) {
                                Write-Message -Message "Starting restore job $($ls.restorejob)" -Level Verbose
                                try {
                                    $null = Start-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob
                                } catch {
                                    $comment = "Something went wrong starting the restore job."
                                    Stop-Function -Message "Something went wrong starting the restore job.`n$($_)" -ErrorRecord $_ -Target $server.name
                                }

                                Write-Message -Message "Waiting for the restore action to complete.." -Level Verbose

                                # Get the job status
                                $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob

                                while ($jobStatus.CurrentRunStatus -ne 'Idle') {
                                    # Sleep for while to let the files be copied
                                    Start-Sleep -Seconds $Delay

                                    # Get the job status
                                    $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob
                                }

                                # Check the lat outcome of the job
                                if ($jobStatus.LastRunOutcome -eq 'Failed') {
                                    $recoverResult = "Failed"
                                    $comment = "The restore job for database $db failed. Please check the error log."
                                    Stop-Function -Message "The restore job for database $db failed. Please check the error log."
                                }

                                $jobOutputs += $jobStatus
                            }
                        }

                        if ($recoverResult -ne 'Failed') {
                            # Disable the log shipping restore job on the secondary instance
                            if ($PSCmdlet.ShouldProcess($server.name, "Disabling restore job $($ls.restorejob)")) {
                                try {
                                    Write-Message -Message ("Disabling restore job " + $ls.restorejob) -Level Verbose
                                    $null = Set-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob -Disabled
                                } catch {
                                    $recoverResult = "Failed"
                                    $comment = "Something went wrong disabling the restore job."
                                    Stop-Function -Message "Something went wrong disabling the restore job.`n$($_)" -ErrorRecord $_ -Target $server.name
                                }
                            }
                        }

                        if ($recoverResult -ne 'Failed') {
                            # Check if the database needs to recovered to its normal state
                            if ($NoRecovery -eq $false) {
                                if ($PSCmdlet.ShouldProcess($secondarydb, "Restoring database with recovery")) {
                                    Write-Message -Message "Restoring the database to it's normal state" -Level Verbose
                                    try {
                                        $query = "RESTORE DATABASE [$secondarydb] WITH RECOVERY"
                                        $server.Query($query)

                                    } catch {
                                        $recoverResult = "Failed"
                                        $comment = "Something went wrong restoring the database to a normal state."
                                        Stop-Function -Message "Something went wrong restoring the database to a normal state.`n$($_)" -ErrorRecord $_ -Target $secondarydb
                                    }
                                }
                            } else {
                                $comment = "Skipping restore with recovery."
                                Write-Message -Message "Skipping restore with recovery" -Level Verbose
                            }

                            Write-Message -Message ("Finished Recovery for $secondarydb") -Level Verbose
                        }

                        # Reset the log ship details
                        $logshipping_details = $null

                        [PSCustomObject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.InstanceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $secondarydb
                            RecoverResult = $recoverResult
                            Comment       = $comment
                        }

                    }
                }
            }
            Write-Progress -Activity $activity -Completed
            $stepCounter = 0
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUF0sBC+OMQWZah+Mupj2IqlII
# YdGgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFFkYdtiZhBtP0U3KYIFGgiIzw/MfMA0GCSqGSIb3DQEBAQUABIIBAFhCu0KG
# G2QHIFY4oGJDryv2acDSnQiNJ5Jyyb/CUUW5mpsjqrN7/rSvknSeDhh1keyTUbXo
# 7PatjfdlRml5ESe1DbQmg8ayqnGB5A9TVIG6NXpLsQ9G+Cq32+q3ogerAu0lMjO5
# 03spbRxlx6onMvr9l8UDYtUMZ6WXSS3yiAIPqIfeu5FN5fJ+No8LOd62E4nBK703
# 7b+BYA8CrjoIUMiYaWt7JSXwDj7LGORi0BavnqGsCF9XxspLQOIfr5XYmsAaxHDC
# eDu0K+jJbUQ/jYv/yDCeesLllI2o4I8XVsvBJuF8qwi/Nth1X1V+0SxKaec9pmHD
# pAU9opo/MmY6c+OhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk1MFowLwYJKoZIhvcNAQkEMSIEIE/5eYdZegN5LnA+ew0bps2WMoWo
# QgtoWYAd1n4vRtdZMA0GCSqGSIb3DQEBAQUABIIBAFrtXE1WCCxjrYbHwXNpzLyF
# SINIbQQ46aq2LmmcDp0Ppq7GjhVC5AWTOSVWkmQwzPJIRjv1NKTJY3cHDdZjd3Ry
# jW6QewTj7/4O5qTUfxvdn0JYoHwm6T1FAeDrbLEj0SybKpugZUm1XMG4lz/EDLfG
# XT4wTbCjJ8bEW+IGd5JytugGxXAAtETGJf5BGnt7qHTI/jP7UhXM6H98kcBX9mDF
# fGsgr/QNDZ0eBIvv5iLl8HCvpyH2w1wFRWxfW6kk7uMnFSrBMpgzL/qS25tp95mJ
# e0s4z2lfHni5maY9AjjPdWHXWvj2Y1jXB7U3ACsF2k2pQJqvWdJKh2g9WaMohWs=
# SIG # End signature block
