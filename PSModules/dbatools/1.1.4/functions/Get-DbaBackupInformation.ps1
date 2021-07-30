function Get-DbaBackupInformation {
    <#
    .SYNOPSIS
        Scan backup files and creates a set, compatible with Restore-DbaDatabase

    .DESCRIPTION
        Upon being passed a list of potential backups files this command will scan the files, select those that contain SQL Server
        backup sets. It will then filter those files down to a set

        The function defaults to working on a remote instance. This means that all paths passed in must be relative to the remote instance.
        XpDirTree will be used to perform the file scans

        Various means can be used to pass in a list of files to be considered. The default is to non recursively scan the folder
        passed in.

    .PARAMETER Path
        Path to SQL Server backup files.

        Paths passed in as strings will be scanned using the desired method, default is a non recursive folder scan
        Accepts multiple paths separated by ','

        Or it can consist of FileInfo objects, such as the output of Get-ChildItem or Get-Item. This allows you to work with
        your own file structures as needed

    .PARAMETER SqlInstance
        The SQL Server instance to be used to read the headers of the backup files

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DatabaseName
        An array of Database Names to filter by. If empty all databases are returned.

    .PARAMETER SourceInstance
        If provided only backup originating from this destination will be returned. This SQL instance will not be connected to or involved in this work

    .PARAMETER NoXpDirTree
        If specified, this switch will cause the files to be parsed as local files to the SQL Server Instance provided. Errors may be observed when the SQL Server Instance cannot access the files being parsed.

    .PARAMETER NoXpDirRecurse
        If specified, this switch changes xp_dirtree behavior to not recurse the folder structure.

    .PARAMETER DirectoryRecurse
        If specified the provided path/directory will be traversed (only applies if not using XpDirTree)

    .PARAMETER Anonymise
        If specified we will output the results with ComputerName, InstanceName, Database, UserName, Paths, and Logical and Physical Names hashed out
        This options is mainly for use if we need you to submit details for fault finding to the dbatools team

    .PARAMETER ExportPath
        If specified the output will export via CliXml format to the specified file. This allows you to store the backup history object for later usage, or move it between computers

    .PARAMETER NoClobber
        If specified will stop Export from overwriting an existing file, the default is to overwrite

    .PARAMETER PassThru
        When data is exported the cmdlet will return no other output, this switch means it will also return the normal output which can be then piped into another command

    .PARAMETER MaintenanceSolution
        This switch tells the function that the folder is the root of a Ola Hallengren backup folder

    .PARAMETER IgnoreLogBackup
        This switch only works with the MaintenanceSolution switch. With an Ola Hallengren style backup we can be sure that the LOG folder contains only log backups and skip it.
        For all other scenarios we need to read the file headers to be sure.

    .PARAMETER IgnoreDiffBackup
        This switch only works with the MaintenanceSolution switch. With an Ola Hallengren style backup we can be sure that the DIFF folder contains only differential backups and skip it.
        For all other scenarios we need to read the file headers to be sure.

    .PARAMETER AzureCredential
        The name of the SQL Server credential to be used if restoring from an Azure hosted backup

    .PARAMETER Import
        When specified along with a path the command will import a previously exported BackupHistory object from an xml file.

    .PARAMETER EnableException
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Chrissy LeMaire (@cl) | Stuart Moore (@napalmgram)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaBackupInformation

    .EXAMPLE
        PS C:\> Get-DbaBackupInformation -SqlInstance Server1 -Path c:\backups\ -DirectoryRecurse

        Will use the Server1 instance to recursively read all backup files under c:\backups, and return a dbatools BackupHistory object

    .EXAMPLE
        PS C:\> Get-DbaBackupInformation -SqlInstance Server1 -Path c:\backups\ -DirectoryRecurse -ExportPath c:\store\BackupHistory.xml
        PS C:\> robocopy c:\store\ \\remoteMachine\C$\store\ BackupHistory.xml
        PS C:\> Get-DbaBackupInformation -Import -Path  c:\store\BackupHistory.xml | Restore-DbaDatabase -SqlInstance Server2 -TrustDbBackupHistory

        This example creates backup history output from server1 and copies the file to the remote machine in order to preserve backup history. It is then used to restore the databases onto server2.

    .EXAMPLE
        PS C:\> Get-DbaBackupInformation -SqlInstance Server1 -Path c:\backups\ -DirectoryRecurse -ExportPath C:\store\BackupHistory.xml -PassThru | Restore-DbaDatabase -SqlInstance Server2 -TrustDbBackupHistory

        In this example we gather backup information, export it to an xml file, and then pass it on through to Restore-DbaDatabase.
        This allows us to repeat the restore without having to scan all the backup files again

    .EXAMPLE
        PS C:\> Get-ChildItem c:\backups\ -recurse -files | Where-Object {$_.extension -in ('.bak','.trn') -and $_.LastWriteTime -gt (get-date).AddMonths(-1)} | Get-DbaBackupInformation -SqlInstance Server1 -ExportPath C:\backupHistory.xml

        This lets you keep a record of all backup history from the last month on hand to speed up refreshes

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\network\backups
        PS C:\> $Backups += Get-DbaBackupInformation -SqlInstance Server2 -NoXpDirTree -Path c:\backups

        Scan the unc folder \\network\backups with Server1, and then scan the C:\backups folder on
        Server2 not using xp_dirtree, adding the results to the first set.

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\network\backups -MaintenanceSolution

        When MaintenanceSolution is indicated we know we are dealing with the output from Ola Hallengren backup scripts. So we make sure that a FULL folder exists in the first level of Path, if not we shortcut scanning all the files as we have nothing to work with

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\network\backups -MaintenanceSolution -IgnoreLogBackup

        As we know we are dealing with an Ola Hallengren style backup folder from the MaintenanceSolution switch, when IgnoreLogBackup is also included we can ignore the LOG folder to skip any scanning of log backups. Note this also means they WON'T be restored

    #>
    [CmdletBinding( DefaultParameterSetName = "Create")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameter AzureCredential")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Path,
        [parameter(Mandatory, ParameterSetName = "Create")]
        [DbaInstanceParameter]$SqlInstance,
        [parameter(ParameterSetName = "Create")]
        [PSCredential]$SqlCredential,
        [string[]]$DatabaseName,
        [string[]]$SourceInstance,
        [parameter(ParameterSetName = "Create")]
        [Switch]$NoXpDirTree,
        [parameter(ParameterSetName = "Create")]
        [Switch]$NoXpDirRecurse = $false,
        [parameter(ParameterSetName = "Create")]
        [switch]$DirectoryRecurse,
        [switch]$EnableException,
        [switch]$MaintenanceSolution,
        [switch]$IgnoreLogBackup,
        [switch]$IgnoreDiffBackup,
        [string]$ExportPath,
        [string]$AzureCredential,
        [parameter(ParameterSetName = "Import")]
        [switch]$Import,
        [switch][Alias('Anonymize')]$Anonymise,
        [Switch]$NoClobber,
        [Switch]$PassThru

    )
    begin {
        function Get-HashString {
            param(
                [String]$InString
            )

            $StringBuilder = New-Object System.Text.StringBuilder
            [System.Security.Cryptography.HashAlgorithm]::Create("md5").ComputeHash([System.Text.Encoding]::UTF8.GetBytes($InString)) | ForEach-Object {
                [Void]$StringBuilder.Append($_.ToString("x2"))
            }
            return $StringBuilder.ToString()
        }
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Debug -Message "Parameters bound: $($PSBoundParameters.Keys -join ", ")"

        if (Test-Bound -ParameterName ExportPath) {
            if ($true -eq $NoClobber) {
                if (Test-Path $ExportPath) {
                    Stop-Function -Message "$ExportPath exists and NoClobber set"
                    return
                }
            }
        }
        if ($PSCmdlet.ParameterSetName -eq "Create") {
            try {
                $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                return
            }
        }

        if ($true -eq $IgnoreLogBackup -and $true -ne $MaintenanceSolution) {
            Write-Message -Message "IgnoreLogBackup can only by used with MaintenanceSolution. Will not be used" -Level Warning
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if ((Test-Bound -Parameter Import) -and ($true -eq $Import)) {
            foreach ($f in $Path) {
                if (Test-Path -Path $f) {
                    $groupResults += Import-Clixml -Path $f
                    foreach ($group in  $groupResults) {
                        $group.FirstLsn = [BigInt]$group.FirstLSN.ToString()
                        $group.CheckpointLSN = [BigInt]$group.CheckpointLSN.ToString()
                        $group.DatabaseBackupLsn = [BigInt]$group.DatabaseBackupLsn.ToString()
                        $group.LastLsn = [BigInt]$group.LastLsn.ToString()
                    }
                } else {
                    Write-Message -Message "$f does not exist or is unreadable" -Level Warning
                }
            }
        } else {
            $Files = @()
            $groupResults = @()
            if ($Path[0] -match 'http') { $NoXpDirTree = $true }
            if ($NoXpDirTree -ne $true) {
                foreach ($f in $path) {
                    if ([System.IO.Path]::GetExtension($f).Length -gt 1) {
                        if ("FullName" -notin $f.PSObject.Properties.name) {
                            $f = $f | Select-Object *, @{ Name = "FullName"; Expression = { $f } }
                        }
                        Write-Message -Message "Testing a single file $f " -Level Verbose
                        if ((Test-DbaPath -Path $f.FullName -SqlInstance $server)) {
                            $files += $f
                        } else {
                            Write-Message -Level Verbose -Message "$server cannot 'see' file $($f.FullName)"
                        }
                    } elseif ($True -eq $MaintenanceSolution) {
                        if ($true -eq $IgnoreLogBackup -and [System.IO.Path]::GetDirectoryName($f) -like '*LOG') {
                            Write-Message -Level Verbose -Message "Skipping Log Backups as requested"
                        } else {
                            Write-Message -Level Verbose -Message "OLA - Getting folder contents"
                            $Files += Get-XpDirTreeRestoreFile -Path $f -SqlInstance $server -NoRecurse:$NoXpDirRecurse
                        }
                    } else {
                        Write-Message -Message "Testing a folder $f" -Level Verbose
                        $Files += $Check = Get-XpDirTreeRestoreFile -Path $f -SqlInstance $server -NoRecurse:$NoXpDirRecurse
                        if ($null -eq $check) {
                            Write-Message -Message "Nothing returned from $f" -Level Verbose
                        }
                    }
                }
            } else {
                ForEach ($f in $path) {
                    Write-Message -Level VeryVerbose -Message "Not using sql for $f"
                    if ($f -is [System.IO.FileSystemInfo]) {
                        if ($f.PsIsContainer -eq $true -and $true -ne $MaintenanceSolution) {
                            Write-Message -Level VeryVerbose -Message "folder $($f.FullName)"
                            $Files += Get-ChildItem -Path $f.FullName -File -Recurse:$DirectoryRecurse
                        } elseif ($f.PsIsContainer -eq $true -and $true -eq $MaintenanceSolution) {
                            if ($IgnoreLogBackup -and $f -notlike '*LOG' ) {
                                Write-Message -Level Verbose -Message "Skipping Log backups for Maintenance backups"
                            } else {
                                $Files += Get-ChildItem -Path $f.FullName -File -Recurse:$DirectoryRecurse
                            }
                        } elseif ($true -eq $MaintenanceSolution) {
                            $Files += Get-ChildItem -Path $f.FullName -Recurse:$DirectoryRecurse
                        } else {
                            Write-Message -Level VeryVerbose -Message "File"
                            $Files += $f.FullName
                        }
                    } else {
                        if ($true -eq $MaintenanceSolution) {
                            $Files += Get-XpDirTreeRestoreFile -Path $f\FULL -SqlInstance $server -NoRecurse
                            $Files += Get-XpDirTreeRestoreFile -Path $f\DIFF -SqlInstance $server -NoRecurse
                            $Files += Get-XpDirTreeRestoreFile -Path $f\LOG -SqlInstance $server -NoRecurse
                        } else {
                            Write-Message -Level VeryVerbose -Message "File"
                            $Files += $f
                        }
                    }
                }
            }

            if ($True -eq $MaintenanceSolution -and $True -eq $IgnoreLogBackup) {
                Write-Message -Level Verbose -Message "Skipping Log Backups as requested"
                $Files = $Files | Where-Object { $_.FullName -notlike '*\LOG\*' }
            }

            if ($True -eq $MaintenanceSolution -and $True -eq $IgnoreDiffBackup) {
                Write-Message -Level Verbose -Message "Skipping Differential Backups as requested"
                $Files = $Files | Where-Object { $_.FullName -notlike '*\DIFF\*' }
            }

            if ($Files.Count -gt 0) {
                Write-Message -Level Verbose -Message "Reading backup headers of $($Files.Count) files"
                $FileDetails = Read-DbaBackupHeader -SqlInstance $server -Path $Files -AzureCredential $AzureCredential
            }

            $groupDetails = $FileDetails | Group-Object -Property BackupSetGUID

            foreach ($group in $groupDetails) {
                $dbLsn = $group.Group[0].DatabaseBackupLSN
                if (-not $dbLsn) {
                    $dbLsn = 0
                }
                $description = $group.Group[0].BackupTypeDescription
                if (-not $description) {
                    $header = Read-DbaBackupHeader -SqlInstance $server -Path $Path | Select-Object -First 1
                    $description = switch ($header.BackupType) {
                        1 { "Full" }
                        2 { "Differential" }
                        3 { "Log" }
                    }
                }
                $historyObject = New-Object Sqlcollaborative.Dbatools.Database.BackupHistory
                $historyObject.ComputerName = $group.Group[0].MachineName
                $historyObject.InstanceName = $group.Group[0].ServiceName
                $historyObject.SqlInstance = $group.Group[0].ServerName
                $historyObject.Database = $group.Group[0].DatabaseName
                $historyObject.UserName = $group.Group[0].UserName
                $historyObject.Start = [DateTime]$group.Group[0].BackupStartDate
                $historyObject.End = [DateTime]$group.Group[0].BackupFinishDate
                $historyObject.Duration = ([DateTime]$group.Group[0].BackupFinishDate - [DateTime]$group.Group[0].BackupStartDate)
                $historyObject.Path = [string[]]$group.Group.BackupPath
                $historyObject.FileList = ($group.Group.FileList | Select-Object Type, LogicalName, PhysicalName, @{
                        Name       = "Size"
                        Expression = { [dbasize]$PSItem.Size }
                    } -Unique)
                $historyObject.TotalSize = ($group.Group.BackupSize.Byte | Measure-Object -Sum).Sum
                $HistoryObject.CompressedBackupSize = ($group.Group.CompressedBackupSize.Byte | Measure-Object -Sum).Sum
                $historyObject.Type = $description
                $historyObject.BackupSetId = $group.group[0].BackupSetGUID
                $historyObject.DeviceType = 'Disk'
                $historyObject.FullName = $group.Group.BackupPath
                $historyObject.Position = $group.Group[0].Position
                $historyObject.FirstLsn = $group.Group[0].FirstLSN
                $historyObject.DatabaseBackupLsn = $dbLsn
                $historyObject.CheckpointLSN = $group.Group[0].CheckpointLSN
                $historyObject.LastLsn = $group.Group[0].LastLsn
                $historyObject.SoftwareVersionMajor = $group.Group[0].SoftwareVersionMajor
                $historyObject.RecoveryModel = $group.Group.RecoveryModel
                $groupResults += $historyObject
            }
        }
        if (Test-Bound 'SourceInstance') {
            $groupResults = $groupResults | Where-Object { $_.InstanceName -in $SourceInstance }
        }

        if (Test-Bound 'DatabaseName') {
            $groupResults = $groupResults | Where-Object { $_.Database -in $DatabaseName }
        }
        if ($true -eq $Anonymise) {
            foreach ($group in $groupResults) {
                $group.ComputerName = Get-HashString -InString $group.ComputerName
                $group.InstanceName = Get-HashString -InString $group.InstanceName
                $group.SqlInstance = Get-HashString -InString $group.SqlInstance
                $group.Database = Get-HashString -InString $group.Database
                $group.UserName = Get-HashString -InString $group.UserName
                $group.Path = Get-HashString -InString  $group.Path
                $group.FullName = Get-HashString -InString $group.FullName
                $group.FileList = ($group.FileList | Select-Object Type,
                    @{Name = "LogicalName"; Expression = { Get-HashString -InString $_."LogicalName" } },
                    @{Name = "PhysicalName"; Expression = { Get-HashString -InString $_."PhysicalName" } })
            }
        }
        if ((Test-Bound -parameterName ExportPath) -and $null -ne $ExportPath) {
            $groupResults | Export-Clixml -Path $ExportPath -Depth 5 -NoClobber:$NoClobber
            if ($true -ne $PassThru) {
                return
            }
        }
        $groupResults | Sort-Object -Property End -Descending
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUIP5eOrLOOZW/CyR6IlTznEdt
# k8GgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFPRndLg6N87UCJPAQiT51pEPEEraMA0GCSqGSIb3DQEBAQUABIIBAFIFHYK+
# XkgK0b6ogcFoLFIo/mLXbiZYAV5Nk/9qKK9y2zrG9OdZoXZUjgKDEiWonf66+k+E
# hsswm/snI62e365vGwRKPq1+iKpw5pi7cT/7g8E20z8w83mBFd557YDlr0JBYAdF
# fiyWXNiYfy9/IC3JCbIPdBKR5v5n6U3g1BiRB59X1ICRp8waT857Cyi+dJkBpJvU
# UikDTxsCMHiKrJ1+eCcAY5B5RubOQMV+Z3hPT/2YUktP3nPZjDxvF7XDufOJBE2X
# C3sOqIf3ZYIsMj/wfmjd6alSh+6R4Yz8+9JmPxlkdjfQWYUPuFLzbmtK0Msr+m8h
# 7cz5Zus4kxviq4ahggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkyNlowLwYJKoZIhvcNAQkEMSIEIOwZXnXouoCdvxfwfxzoy0rSjsxh
# e5nVv5WB03/iiVLeMA0GCSqGSIb3DQEBAQUABIIBAAZbaEIMRWfqgwSEwv+BCmug
# STizXLMWRquBdJm13ArURREXG+6Gkvh/RP/opGBO/4N2c9P3ncZTFMwa85tWjeKH
# PgdNYCiYcsEuuvkE6jL+3BhiBXcovZYks3huitPNms/tUuaHbS+xrnBK4Tyh/O7X
# 5v6Xqu3LqXm7eoqbfcmUEwxwGIYPJ+D5rgRrvTZalaLrxwyTfoQSG6pni2E+PaRn
# pI4GlT+O2Gi/D6oCKgJI+DuuvusCkCNaMUGXprvrW3E3/ryekR2YZC/I2+36I36L
# RgfpZw4buiVNP11I1Ietiv1iuO+bdCpY57aW3s24PH7CJY+xCr9k7xkw7yfnAmk=
# SIG # End signature block
