function Invoke-DbaDbMirroring {
    <#
    .SYNOPSIS
        Automates the creation of database mirrors.

    .DESCRIPTION
        Automates the creation of database mirrors.

        * Verifies that a mirror is possible
        * Sets the recovery model to Full if needed
        * If the database does not exist on mirror or witness, a backup/restore is performed
        * Sets up endpoints if necessary
        * Creates a login and grants permissions to service accounts if needed
        * Starts endpoints if needed
        * Sets up partner for mirror
        * Sets up partner for primary
        * Sets up witness if one is specified

        NOTE: If a backup / restore is performed, the backups will be left in tact on the network share.

    .PARAMETER Primary
        SQL Server name or SMO object representing the primary SQL Server.

    .PARAMETER PrimarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Mirror
        SQL Server name or SMO object representing the mirror SQL Server.

    .PARAMETER MirrorSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Witness
        SQL Server name or SMO object representing the witness SQL Server.

    .PARAMETER WitnessSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases to mirror.

    .PARAMETER SharedPath
        The network share where the backups will be backed up and restored from.

        Each SQL Server service account must have access to this share.

        NOTE: If a backup / restore is performed, the backups will be left in tact on the network share.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase.

    .PARAMETER UseLastBackup
        Use the last full backup of database.

    .PARAMETER Force
        Drop and recreate the database on remote servers using fresh backup.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Mirroring, Mirror, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbMirroring

    .EXAMPLE
        PS C:\> $params = @{
        >> Primary = 'sql2017a'
        >> Mirror = 'sql2017b'
        >> MirrorSqlCredential = 'sqladmin'
        >> Witness = 'sql2019'
        >> Database = 'pubs'
        >> SharedPath = '\\nas\sql\share'
        >> }
        >>
        PS C:\> Invoke-DbaDbMirroring @params

        Performs a bunch of checks to ensure the pubs database on sql2017a
        can be mirrored from sql2017a to sql2017b. Logs in to sql2019 and sql2017a
        using Windows credentials and sql2017b using a SQL credential.

        Prompts for confirmation for most changes. To avoid confirmation, use -Confirm:$false or
        use the syntax in the second example.

    .EXAMPLE
        PS C:\> $params = @{
        >> Primary = 'sql2017a'
        >> Mirror = 'sql2017b'
        >> MirrorSqlCredential = 'sqladmin'
        >> Witness = 'sql2019'
        >> Database = 'pubs'
        >> SharedPath = '\\nas\sql\share'
        >> Force = $true
        >> Confirm = $false
        >> }
        >>
        PS C:\> Invoke-DbaDbMirroring @params

        Performs a bunch of checks to ensure the pubs database on sql2017a
        can be mirrored from sql2017a to sql2017b. Logs in to sql2019 and sql2017a
        using Windows credentials and sql2017b using a SQL credential.

        Drops existing pubs database on Mirror and Witness and restores them with
        a fresh backup.

        Does all the things in the description, does not prompt for confirmation.

    .EXAMPLE
        PS C:\> $map = @{ 'database_data' = 'M:\Data\database_data.mdf' 'database_log' = 'L:\Log\database_log.ldf' }
        PS C:\> Get-ChildItem \\nas\seed | Restore-DbaDatabase -SqlInstance sql2017b -FileMapping $map -NoRecovery
        PS C:\> Get-DbaDatabase -SqlInstance sql2017a -Database pubs | Invoke-DbaDbMirroring -Mirror sql2017b -Confirm:$false

        Restores backups from sql2017a to a specific file structure on sql2017b then creates mirror with no prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017a -Database pubs |
        >> Invoke-DbaDbMirroring -Mirror sql2017b -UseLastBackup -Confirm:$false

        Mirrors pubs on sql2017a to sql2017b and uses the last full and logs from sql2017a to seed. Doesn't prompt for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter]$Primary,
        [PSCredential]$PrimarySqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Mirror,
        [PSCredential]$MirrorSqlCredential,
        [DbaInstanceParameter]$Witness,
        [PSCredential]$WitnessSqlCredential,
        [string[]]$Database,
        [string]$SharedPath,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$UseLastBackup,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $params = $PSBoundParameters
        $null = $params.Remove('UseLastBackup')
        $null = $params.Remove('Force')
        $null = $params.Remove('Confirm')
        $null = $params.Remove('Whatif')
    }
    process {
        if ((Test-Bound -ParameterName Primary) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when Primary is specified"
            return
        }

        if ($Force -and (-not $SharedPath -and -not $UseLastBackup)) {
            Stop-Function -Message "SharedPath or UseLastBackup is required when Force is used"
            return
        }

        if ($Primary) {
            $InputObject += Get-DbaDatabase -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Database $Database
        }

        foreach ($primarydb in $InputObject) {
            $stepCounter = 0
            $Primary = $source = $primarydb.Parent
            foreach ($currentmirror in $Mirror) {
                $stepCounter = 0
                try {
                    $dest = Connect-SqlInstance -SqlInstance $currentmirror -SqlCredential $MirrorSqlCredential

                    if ($Witness) {
                        $witserver = Connect-SqlInstance -SqlInstance $Witness -SqlCredential $WitnessSqlCredential
                    }
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                $dbName = $primarydb.Name

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Validating mirror setup"
                # Thanks to https://github.com/mmessano/PowerShell/blob/master/SQL-ConfigureDatabaseMirroring.ps1 for the tips

                $params.Database = $dbName
                $validation = Invoke-DbMirrorValidation @params

                if ((Test-Bound -ParameterName SharedPath) -and -not $validation.AccessibleShare) {
                    Stop-Function -Continue -Message "Cannot access $SharedPath from $($dest.Name)"
                }

                if (-not $validation.EditionMatch) {
                    Stop-Function -Continue -Message "This mirroring configuration is not supported. Because the principal server instance, $source, is $($source.EngineEdition) Edition, the mirror server instance must also be $($source.EngineEdition) Edition."
                }

                foreach ($status in $validation.MirroringStatus) {
                    if ($status -ne "None") {
                        Stop-Function -Continue -Message "Cannot setup mirroring on database ($dbName) due to its current mirroring state on primary: $status"
                    }
                }

                if ($primarydb.Status -ne "Normal") {
                    Stop-Function -Continue -Message "Cannot setup mirroring on database ($dbName) due to its current state: $($primarydb.Status)"
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting recovery model for $dbName on $($source.Name) to Full"

                if ($primarydb.RecoveryModel -ne "Full") {
                    if ((Test-Bound -ParameterName UseLastBackup)) {
                        Stop-Function -Continue -Message "$dbName not set to full recovery. UseLastBackup cannot be used."
                    } else {
                        Set-DbaDbRecoveryModel -SqlInstance $source -Database $primarydb.Name -RecoveryModel Full
                    }
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Copying $dbName from primary to mirror"
                if (-not $validation.DatabaseExistsOnMirror -or $Force) {
                    if ($UseLastBackup) {
                        $allbackups = Get-DbaDbBackupHistory -SqlInstance $primarydb.Parent -Database $primarydb.Name -IncludeCopyOnly -Last
                    } else {
                        if ($Force -or $Pscmdlet.ShouldProcess("$Primary", "Creating full and log backups of $primarydb on $SharedPath")) {
                            $fullbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Full
                            $logbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Log
                            $allbackups = $fullbackup, $logbackup
                        }
                    }
                    if ($Pscmdlet.ShouldProcess("$currentmirror", "Restoring full and log backups of $primarydb from $Primary")) {
                        foreach ($currentmirrorinstance in $currentmirror) {
                            try {
                                $null = $allbackups | Restore-DbaDatabase -SqlInstance $currentmirrorinstance -SqlCredential $MirrorSqlCredential -WithReplace -NoRecovery -TrustDbBackupHistory -EnableException
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $dest -Continue
                            }
                        }
                    }

                    if ($SharedPath) {
                        Write-Message -Level Verbose -Message "Backups still exist on $SharedPath"
                    }
                }

                $currentmirrordb = Get-DbaDatabase -SqlInstance $dest -Database $dbName

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Copying $dbName from primary to witness"

                if ($Witness -and (-not $validation.DatabaseExistsOnWitness -or $Force)) {
                    if (-not $allbackups) {
                        if ($UseLastBackup) {
                            $allbackups = Get-DbaDbBackupHistory -SqlInstance $primarydb.Parent -Database $primarydb.Name -IncludeCopyOnly -Last
                        } else {
                            if ($Force -or $Pscmdlet.ShouldProcess("$Primary", "Creating full and log backups of $primarydb on $SharedPath")) {
                                $fullbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Full
                                $logbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Log
                                $allbackups = $fullbackup, $logbackup
                            }
                        }
                    }

                    if ($Pscmdlet.ShouldProcess("$Witness", "Restoring full and log backups of $primarydb from $Primary")) {
                        try {
                            $null = $allbackups | Restore-DbaDatabase -SqlInstance $Witness -SqlCredential $WitnessSqlCredential -WithReplace -NoRecovery -TrustDbBackupHistory -EnableException
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $witserver -Continue
                        }
                    }
                }

                $primaryendpoint = Get-DbaEndpoint -SqlInstance $source | Where-Object EndpointType -eq DatabaseMirroring
                $currentmirrorendpoint = Get-DbaEndpoint -SqlInstance $dest | Where-Object EndpointType -eq DatabaseMirroring

                if (-not $primaryendpoint) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting up endpoint for primary"
                    $primaryendpoint = New-DbaEndpoint -SqlInstance $source -Type DatabaseMirroring -Role Partner -Name Mirroring -EncryptionAlgorithm RC4
                    $null = $primaryendpoint | Stop-DbaEndpoint
                    $null = $primaryendpoint | Start-DbaEndpoint
                }

                if (-not $currentmirrorendpoint) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting up endpoint for mirror"
                    $currentmirrorendpoint = New-DbaEndpoint -SqlInstance $dest -Type DatabaseMirroring -Role Partner -Name Mirroring -EncryptionAlgorithm RC4
                    $null = $currentmirrorendpoint | Stop-DbaEndpoint
                    $null = $currentmirrorendpoint | Start-DbaEndpoint
                }

                if ($witserver) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting up endpoint for witness"
                    $witnessendpoint = Get-DbaEndpoint -SqlInstance $witserver | Where-Object EndpointType -eq DatabaseMirroring
                    if (-not $witnessendpoint) {
                        $witnessendpoint = New-DbaEndpoint -SqlInstance $witserver -Type DatabaseMirroring -Role Witness -Name Mirroring -EncryptionAlgorithm RC4
                        $null = $witnessendpoint | Stop-DbaEndpoint
                        $null = $witnessendpoint | Start-DbaEndpoint
                    }
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Granting permissions to service account"

                $serviceAccounts = $source.ServiceAccount, $dest.ServiceAccount, $witserver.ServiceAccount | Select-Object -Unique

                foreach ($account in $serviceAccounts) {
                    if ($account) {
                        if ($Pscmdlet.ShouldProcess("primary, mirror and witness (if specified)", "Creating login $account and granting CONNECT ON ENDPOINT")) {
                            $null = New-DbaLogin -SqlInstance $source -Login $account -WarningAction SilentlyContinue
                            $null = New-DbaLogin -SqlInstance $dest -Login $account -WarningAction SilentlyContinue
                            try {
                                $null = $source.Query("GRANT CONNECT ON ENDPOINT::$primaryendpoint TO [$account]")
                                $null = $dest.Query("GRANT CONNECT ON ENDPOINT::$currentmirrorendpoint TO [$account]")
                                if ($witserver) {
                                    $null = New-DbaLogin -SqlInstance $witserver -Login $account -WarningAction SilentlyContinue
                                    $witserver.Query("GRANT CONNECT ON ENDPOINT::$witnessendpoint TO [$account]")
                                }
                            } catch {
                                Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                            }
                        }
                    }
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Starting endpoints if necessary"
                try {
                    $null = $primaryendpoint, $currentmirrorendpoint, $witnessendpoint | Start-DbaEndpoint -EnableException
                } catch {
                    Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                }

                try {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting up partner for mirror"
                    $null = $currentmirrordb | Set-DbaDbMirror -Partner $primaryendpoint.Fqdn -EnableException
                } catch {
                    Stop-Function -Continue -Message "Failure on mirror" -ErrorRecord $_
                }

                try {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting up partner for primary"
                    $null = $primarydb | Set-DbaDbMirror -Partner $currentmirrorendpoint.Fqdn -EnableException
                } catch {
                    Stop-Function -Continue -Message "Failure on primary" -ErrorRecord $_
                }

                try {
                    if ($witnessendpoint) {
                        $null = $primarydb | Set-DbaDbMirror -Witness $witnessendpoint.Fqdn -EnableException
                    }
                } catch {
                    Stop-Function -Continue -Message "Failure with the new last part" -ErrorRecord $_
                }
            }

            if ($Pscmdlet.ShouldProcess("console", "Showing results")) {
                $results = [pscustomobject]@{
                    Primary  = $Primary
                    Mirror   = $Mirror -join ", "
                    Witness  = $Witness
                    Database = $primarydb.Name
                    Status   = "Success"
                }
                if ($Witness) {
                    $results | Select-DefaultView -Property Primary, Mirror, Witness, Database, Status
                } else {
                    $results | Select-DefaultView -Property Primary, Mirror, Database, Status
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUFl2ySViqO5TpWdYdxl4SzEW+
# MEagghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFNxgz5u2BRUKdptmXXnAcVqxh5+nMA0GCSqGSIb3DQEBAQUABIIBAIEy04wx
# Yi4i1883XG6uRt/4UCyrJYaVC0XGBAMt2BDIlOapUqrTrmIBkJd/CyngG1pUehuK
# IUYHyyQgn7ugkn+Hp0fHav8XkhxD2gidXqWUKbEp2HS3f9ryMNRbY/OrU1DZQoSg
# jNf9RmFLU5PgJ07xdjVZlWNpo94I7z3p7uKAszkL3LZ2U+kE5KAMItvpWk70LhTS
# 8KqeRJLC57b9ARizGf56BO2Sp2cGC55W00N5NAWkwps8w1/61baik4Hk82C4ElfL
# BSJ7BQgDYuYBd8ElmaNHUU45/tcPyNF5SA8lzX+Xcvppn0yb1fTdawVj8aMPrtqz
# 0Yp/6lvivIGBSbShggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzNlowLwYJKoZIhvcNAQkEMSIEIGchN23flDdZkwquSHYOy7tEMyFm
# fo1U0NkUJY7t9EElMA0GCSqGSIb3DQEBAQUABIIBAD/6i6b32ZJ5kr8bmxs8Nf6x
# 1DxidR49SsgB7AMWPp7YZNnTflXRDFhhw70nQy9KIN2FIB7ku8Ats0n9qslFi9fy
# Ph+BRLiyzhUr8uy5M02+k+OnZ/xcxB34inL4OcV285Mbteszy5dVtue1yk0FdRn0
# 682od9jZkqIcrSP3ulLr5pxjhG7ZBIKInNblmZ2Ff8eQS8W6DnDJ8DE71NVPhLJP
# 9pKCFQriTue/I8xhktSAVNAbTyLAR7ekky26x9wjH4MROYCYEdNAJD2fnzkstyRP
# H10oWD/T/izrJH73MaGeiLvSYE0KgI88gtDL9AaVccImKkdjpwtCQ0GKGZfRz5I=
# SIG # End signature block
