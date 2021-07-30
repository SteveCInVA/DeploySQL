function New-DbaLogShippingSecondaryDatabase {
    <#
        .SYNOPSIS
            New-DbaLogShippingSecondaryDatabase sets up a secondary databases for log shipping.

        .DESCRIPTION
            New-DbaLogShippingSecondaryDatabase sets up a secondary databases for log shipping.
            This is executed on the secondary server.

        .PARAMETER SqlInstance
            SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER BufferCount
            The total number of buffers used by the backup or restore operation.
            The default is -1.

        .PARAMETER BlockSize
            The size, in bytes, that is used as the block size for the backup device.
            The default is -1.

        .PARAMETER DisconnectUsers
            If set to 1, users are disconnected from the secondary database when a restore operation is performed.
            Te default is 0.

        .PARAMETER HistoryRetention
            Is the length of time in minutes in which the history is retained.
            The default is 14420.

        .PARAMETER MaxTransferSize
            The size, in bytes, of the maximum input or output request which is issued by SQL Server to the backup device.

        .PARAMETER PrimaryServer
            The name of the primary instance of the Microsoft SQL Server Database Engine in the log shipping configuration.

        .PARAMETER PrimaryDatabase
            Is the name of the database on the primary server.

        .PARAMETER RestoreAll
            If set to 1, the secondary server restores all available transaction log backups when the restore job runs.
            The default is 1.

        .PARAMETER RestoreDelay
            The amount of time, in minutes, that the secondary server waits before restoring a given backup file.
            The default is 0.

        .PARAMETER RestoreMode
            The restore mode for the secondary database. The default is 0.
            0 = Restore log with NORECOVERY.
            1 = Restore log with STANDBY.

        .PARAMETER RestoreThreshold
            The number of minutes allowed to elapse between restore operations before an alert is generated.

        .PARAMETER SecondaryDatabase
            Is the name of the secondary database.

        .PARAMETER ThresholdAlert
            Is the alert to be raised when the backup threshold is exceeded.
            The default is 14420.

        .PARAMETER ThresholdAlertEnabled
            Specifies whether an alert is raised when backup_threshold is exceeded.

        .PARAMETER MonitorServer
            Is the name of the monitor server.
            The default is the name of the primary server.

        .PARAMETER MonitorCredential
            Allows you to login to enter a secure credential.
            This is only needed in combination with MonitorServerSecurityMode having either a 0 or 'sqlserver' value.
            To use: $scred = Get-Credential, then pass $scred object to the -MonitorCredential parameter.

        .PARAMETER MonitorServerSecurityMode
            The security mode used to connect to the monitor server. Allowed values are 0, "sqlserver", 1, "windows"
            The default is 1 or Windows.

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER Confirm
            Prompts you for confirmation before executing any changing operations within the command.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER Force
            The force parameter will ignore some errors in the parameters and assume defaults.
            It will also remove the any present schedules with the same name for the specific job.

        .NOTES
            Author: Sander Stad (@sqlstad, sqlstad.nl)
            Website: https://dbatools.io
            Copyright: (c) 2018 by dbatools, licensed under MIT
            License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
            New-DbaLogShippingSecondaryDatabase -SqlInstance sql2 -SecondaryDatabase DB1_DR -PrimaryServer sql1 -PrimaryDatabase DB1 -RestoreDelay 0 -RestoreMode standby -DisconnectUsers -RestoreThreshold 45 -ThresholdAlertEnabled -HistoryRetention 14420
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]

    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$BufferCount = -1,
        [int]$BlockSize = -1,
        [switch]$DisconnectUsers,
        [int]$HistoryRetention = 14420,
        [int]$MaxTransferSize,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter]$PrimaryServer,
        [PSCredential]$PrimarySqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$PrimaryDatabase,
        [int]$RestoreAll = 1,
        [int]$RestoreDelay = 0,
        [ValidateSet(0, 'NoRecovery', 1, 'Standby')]
        [object]$RestoreMode = 0,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [int]$RestoreThreshold,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SecondaryDatabase,
        [int]$ThresholdAlert = 14420,
        [switch]$ThresholdAlertEnabled,
        [string]$MonitorServer,
        [ValidateSet(0, "sqlserver", 1, "windows")]
        [object]$MonitorServerSecurityMode = 1,
        [System.Management.Automation.PSCredential]$MonitorCredential,
        [switch]$EnableException,
        [switch]$Force
    )

    # Try connecting to the instance
    try {
        $ServerSecondary = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -Target $SqlInstance -ErrorRecord $_ -Continue
    }

    # Try connecting to the instance
    try {
        $ServerPrimary = Connect-SqlInstance -SqlInstance $PrimaryServer -SqlCredential $PrimarySqlCredential
    } catch {
        Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -Target $PrimaryServer -ErrorRecord $_ -Continue
    }

    # Check if the database is present on the primary sql server
    if ($ServerPrimary.Databases.Name -notcontains $PrimaryDatabase) {
        Stop-Function -Message "Database $PrimaryDatabase is not available on instance $PrimaryServer" -Target $PrimaryServer -Continue
    }

    # Check if the database is present on the primary sql server
    if ($ServerSecondary.Databases.Name -notcontains $SecondaryDatabase) {
        Stop-Function -Message "Database $SecondaryDatabase is not available on instance $ServerSecondary" -Target $SqlInstance -Continue
    }

    # Check the restore mode
    if ($RestoreMode -notin 0, 1) {
        $RestoreMode = switch ($RestoreMode) { "NoRecovery" { 0 }  "Standby" { 1 } }
        Write-Message -Message "Setting restore mode to $RestoreMode." -Level Verbose
    }

    # Check the if Threshold alert needs to be enabled
    if ($ThresholdAlertEnabled) {
        [int]$ThresholdAlertEnabled = 1
        Write-Message -Message "Setting Threshold alert to $ThresholdAlertEnabled." -Level Verbose
    } else {
        [int]$ThresholdAlertEnabled = 0
        Write-Message -Message "Setting Threshold alert to $ThresholdAlertEnabled." -Level Verbose
    }

    # Checking the option to disconnect users
    if ($DisconnectUsers) {
        [int]$DisconnectUsers = 1
        Write-Message -Message "Setting disconnect users to $DisconnectUsers." -Level Verbose
    } else {
        [int]$DisconnectUsers = 0
        Write-Message -Message "Setting disconnect users to $DisconnectUsers." -Level Verbose
    }

    # Check hte combination of the restore mode with the option to disconnect users
    if ($RestoreMode -eq 0 -and $DisconnectUsers -ne 0) {
        if ($Force) {
            [int]$DisconnectUsers = 0
            Write-Message -Message "Illegal combination of database restore mode $RestoreMode and disconnect users $DisconnectUsers. Setting it to $DisconnectUsers." -Level Warning
        } else {
            Stop-Function -Message "Illegal combination of database restore mode $RestoreMode and disconnect users $DisconnectUsers." -Target $SqlInstance -Continue
        }
    }

    # Set up the query
    $Query = "EXEC master.sys.sp_add_log_shipping_secondary_database
        @secondary_database = '$SecondaryDatabase'
        ,@primary_server = '$PrimaryServer'
        ,@primary_database = '$PrimaryDatabase'
        ,@restore_delay = $RestoreDelay
        ,@restore_all = $RestoreAll
        ,@restore_mode = $RestoreMode
        ,@disconnect_users = $DisconnectUsers
        ,@restore_threshold = $RestoreThreshold
        ,@threshold_alert = $ThresholdAlert
        ,@threshold_alert_enabled = $ThresholdAlertEnabled
        ,@history_retention_period = $HistoryRetention "


    if ($ServerSecondary.Version.Major -le 12) {
        $Query += "
        ,@ignoreremotemonitor = 1"
    }

    # Add inf extra options to the query when needed
    if ($BlockSize -ne -1) {
        $Query += ",@block_size = $BlockSize"
    }

    if ($BufferCount -ne -1) {
        $Query += ",@buffer_count = $BufferCount"
    }

    if ($MaxTransferSize -ge 1) {
        $Query += ",@max_transfer_size = $MaxTransferSize"
    }

    if ($Force -and ($ServerSecondary.Version.Major -gt 9)) {
        $Query += ",@overwrite = 1;"
    } else {
        $Query += ";"
    }

    # Execute the query to add the log shipping primary
    if ($PSCmdlet.ShouldProcess($SqlServer, ("Configuring logshipping for secondary database $SecondaryDatabase on $SqlInstance"))) {
        try {
            Write-Message -Message "Configuring logshipping for secondary database $SecondaryDatabase on $SqlInstance." -Level Verbose
            Write-Message -Message "Executing query:`n$Query" -Level Verbose
            $ServerSecondary.Query($Query)

            # For versions prior to SQL Server 2014, adding a monitor works in a different way.
            # The next section makes sure the settings are being synchronized with earlier versions
            if ($MonitorServer -and ($ServerSecondary.Version.Major -lt 12)) {
                # Get the details of the primary database
                $query = "SELECT * FROM msdb.dbo.log_shipping_monitor_secondary WHERE primary_database = '$PrimaryDatabase' AND primary_server = '$PrimaryServer'"
                $lsDetails = $ServerSecondary.Query($query)

                # Setup the procedure script for adding the monitor for the primary
                $query = "EXEC msdb.dbo.sp_processlogshippingmonitorsecondary @mode = $MonitorServerSecurityMode
                    ,@secondary_server = '$SqlInstance'
                    ,@secondary_database = '$SecondaryDatabase'
                    ,@secondary_id = '$($lsDetails.secondary_id)'
                    ,@primary_server = '$($lsDetails.primary_server)'
                    ,@primary_database = '$($lsDetails.primary_database)'
                    ,@restore_threshold = $RestoreThreshold
                    ,@threshold_alert = $([int]$lsDetails.threshold_alert)
                    ,@threshold_alert_enabled = $([int]$lsDetails.threshold_alert_enabled)
                    ,@history_retention_period = $([int]$lsDetails.history_retention_period)
                    ,@monitor_server = '$MonitorServer'
                    ,@monitor_server_security_mode = $MonitorServerSecurityMode "

                # Check the MonitorServerSecurityMode if it's SQL Server authentication
                if ($MonitorServer -and $MonitorServerSecurityMode -eq 0 ) {
                    $query += ",@monitor_server_login = N'$MonitorLogin'
                        ,@monitor_server_password = N'$MonitorPassword' "
                }

                Write-Message -Message "Configuring monitor server for secondary database $SecondaryDatabase." -Level Verbose
                Write-Message -Message "Executing query:`n$query" -Level Verbose
                Invoke-DbaQuery -SqlInstance $MonitorServer -SqlCredential $MonitorCredential -Database msdb -Query $query

                $query = "
                UPDATE msdb.dbo.log_shipping_secondary
                SET monitor_server = '$MonitorServer', user_specified_monitor = 1
                WHERE secondary_id = '$($lsDetails.secondary_id)'
                "

                Write-Message -Message "Updating monitor information for the secondary database $Database." -Level Verbose
                Write-Message -Message "Executing query:`n$query" -Level Verbose
                $ServerSecondary.Query($query)

            }
        } catch {
            Write-Message -Message "$($_.Exception.InnerException.InnerException.InnerException.InnerException.Message)" -Level Warning
            Stop-Function -Message "Error executing the query.`n$($_.Exception.Message)`n$Query"  -ErrorRecord $_ -Target $SqlInstance -Continue
        }
    }

    Write-Message -Message "Finished adding the secondary database $SecondaryDatabase to log shipping." -Level Verbose

}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUMYSU9aSOd3tGWoxZwlptqLqB
# TkGgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFNpgdn/c5mgKvvkNT5zXgf2CWSlIMA0GCSqGSIb3DQEBAQUABIIBAIVST7Ox
# 2M6yYmtVsMLDJ6qf0dcPbtWYRoySCNn0CZfllM8XkuSWp47tKeiDkrFrSvXKFi/x
# JIrrTd/eckSpasttVG+YYiQ2WXRSVRCKtrgixQrJufvBv13jSlfVY6gacEqvKdeF
# joYN/kr8bBfva0sUf5rcUDbgV1FCWIvhG8z0EWMdxeJgvaUdXsY+q/ZCeKkkm3gC
# fsjpbROz4b9KydZL2II6mXy1RDuxKpkBnsLAgC9YyxviAnn9UhCe43jhrNLnmZ9k
# tmHU9HcCVRSDuL882oyLEVqd7VaQbf11J1bRSYdE4tTL/SJPWh7SaFoDDu/f4k6S
# 8YCcWYhH82F+d/ShggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAzNlowLwYJKoZIhvcNAQkEMSIEILG/andg5NwVGl3iShSJXrsqmvAl
# ZKkptyNHWO/TmuMrMA0GCSqGSIb3DQEBAQUABIIBAFzopDgCUjIobkJ88yNnS2kQ
# gxjZFGgt5EKIgnfrACM79pSKxBUHQ6DAyK1YoaO5DDqWC5fxrGGWkhsXs9/03uoS
# eRdrK6X4Ofbtj6XuI1ntth2cZ6Pe4zv2VRWlhtm/bKQu3O4KRqDSe+e2c6mEGJCx
# lANoaKbDX9Jd1G3xkFD2BxcG35GHujVYq0FPEJVgqi4Io+6jywJkETXUlnbSqjDw
# EFj2RcZKfN6P7N09Ik5nLXs9YeqWZ/hy1hjHItg04Owey65sSA/PcO9wGYK8QF//
# MCZ3Dpd1uuzNL1PwopCMYRmCUX8L6n5cObDxdCL4lwbmFhOTkCYUq53ynQBbmtM=
# SIG # End signature block
