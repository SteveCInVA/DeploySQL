function Format-DbaBackupInformation {
    <#
    .SYNOPSIS
        Transforms the data in a dbatools BackupHistory object for a restore

    .DESCRIPTION
        Performs various mapping on Backup History, ready restoring
        Options include changing restore paths, backup paths, database name and many others

    .PARAMETER BackupHistory
        A dbatools backupHistory object, normally this will have been created using Select-DbaBackupInformation

    .PARAMETER ReplaceDatabaseName
        If a single value is provided, this will be replaced do all occurrences a database name
        If a Hashtable is passed in, each database name mention will be replaced as specified. If a database's name does not appear it will not be replace
        DatabaseName will also be replaced where it  occurs in the file paths of data and log files.
        Please note, that this won't change the Logical Names of data files, that has to be done with a separate Alter DB call

    .PARAMETER DatabaseNamePrefix
        This string will be prefixed to all restored database's name

    .PARAMETER DataFileDirectory
        This will move ALL restored files to this location during the restore

    .PARAMETER LogFileDirectory
        This will move all log files to this location, overriding DataFileDirectory

    .PARAMETER DestinationFileStreamDirectory
        This move the FileStream folder and contents to the new location, overriding DataFileDirectory

    .PARAMETER FileNamePrefix
        This string will  be prefixed to all restored files (Data and Log)

    .PARAMETER RebaseBackupFolder
        Use this to rebase where your backups are stored.

    .PARAMETER Continue
        Indicates that this is a continuing restore

    .PARAMETER DatabaseFilePrefix
        A string that will be prefixed to every file restored

    .PARAMETER DatabaseFileSuffix
        A string that will be suffixed to every file restored

    .PARAMETER ReplaceDbNameInFile
        If set, will replace the old database name with the new name if it occurs in the file name

    .PARAMETER FileMapping
        A hashtable that can be used to move specific files to a location.
        `$FileMapping = @{'DataFile1'='c:\restoredfiles\Datafile1.mdf';'DataFile3'='d:\DataFile3.mdf'}`
        And files not specified in the mapping will be restored to their original location
        This Parameter is exclusive with DestinationDataDirectory
        If specified, this will override any other file renaming/relocation options.

    .PARAMETER PathSep
        By default is Windows's style (`\`) but you can pass also, e.g., `/` for Unix's style paths

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Format-DbaBackupInformation

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -ReplaceDatabaseName NewDb

        Changes as database name references to NewDb, both in the database name and any restore paths. Note, this will fail if the BackupHistory object contains backups for more than 1 database

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -ReplaceDatabaseName @{'OldB'='NewDb';'ProdHr'='DevHr'}

        Will change all occurrences of original database name in the backup history (names and restore paths) using the mapping in the hashtable.
        In this example any occurrence of OldDb will be replaced with NewDb and ProdHr with DevPR

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -DataFileDirectory 'D:\DataFiles\' -LogFileDirectory 'E:\LogFiles\

        This example with change the restore path for all data files (everything that is not a log file) to d:\datafiles
        And all Transaction Log files will be restored to E:\Logfiles

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -RebaseBackupFolder f:\backups

        This example changes the location that SQL Server will look for the backups. This is useful if you've moved the backups to a different location

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$BackupHistory,
        [object]$ReplaceDatabaseName,
        [switch]$ReplaceDbNameInFile,
        [string]$DataFileDirectory,
        [string]$LogFileDirectory,
        [string]$DestinationFileStreamDirectory,
        [string]$DatabaseNamePrefix,
        [string]$DatabaseFilePrefix,
        [string]$DatabaseFileSuffix,
        [string]$RebaseBackupFolder,
        [switch]$Continue,
        [hashtable]$FileMapping,
        [string]$PathSep = '\',
        [switch]$EnableException
    )
    begin {

        Write-Message -Message "Starting" -Level Verbose
        if ($null -ne $ReplaceDatabaseName) {
            if ($ReplaceDatabaseName -is [string] -or $ReplaceDatabaseName.ToString() -ne 'System.Collections.Hashtable') {
                Write-Message -Message "String passed in for DB rename" -Level Verbose
                $ReplaceDatabaseNameType = 'single'
            } elseif ($ReplaceDatabaseName -is [HashTable] -or $ReplaceDatabaseName.ToString() -eq 'System.Collections.Hashtable' ) {
                Write-Message -Message "Hashtable passed in for DB rename" -Level Verbose
                $ReplaceDatabaseNameType = 'multi'
            } else {
                Write-Message -Message "ReplacemenDatabaseName is $($ReplaceDatabaseName.Gettype().ToString()) - $ReplaceDatabaseName" -level Verbose
            }
        }
        if ((Test-Bound -Parameter DataFileDirectory) -and $DataFileDirectory.EndsWith($PathSep)) {
            $DataFileDirectory = $DataFileDirectory -Replace '.$'
        }
        if ((Test-Bound -Parameter DestinationFileStreamDirectory) -and $DestinationFileStreamDirectory.EndsWith($PathSep) ) {
            $DestinationFileStreamDirectory = $DestinationFileStreamDirectory -Replace '.$'
        }
        if ((Test-Bound -Parameter LogFileDirectory) -and $LogFileDirectory.EndsWith($PathSep) ) {
            $LogFileDirectory = $LogFileDirectory -Replace '.$'
        }
        if ((Test-Bound -Parameter RebaseBackupFolder) -and $RebaseBackupFolder.EndsWith($PathSep) ) {
            $RebaseBackupFolder = $RebaseBackupFolder -Replace '.$'
        }
    }


    process {

        foreach ($History in $BackupHistory) {
            if ("OriginalDatabase" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'OriginalDatabase' -Type NoteProperty -Value $History.Database
            }
            if ("OriginalFileList" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'OriginalFileList' -Type NoteProperty -Value ''
                $History | ForEach-Object { $_.OriginalFileList = $_.FileList }
            }
            if ("OriginalFullName" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'OriginalFullName' -Type NoteProperty -Value $History.FullName
            }
            if ("IsVerified" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'IsVerified' -Type NoteProperty -Value $False
            }
            switch ($History.Type) {
                'Full' { $History.Type = 'Database' }
                'Differential' { $History.Type = 'Database Differential' }
                'Log' { $History.Type = 'Transaction Log' }
            }


            if ($ReplaceDatabaseNameType -eq 'single' -and $ReplaceDatabaseName -ne '' ) {
                $History.Database = $ReplaceDatabaseName
                Write-Message -Message "New DbName (String) = $($History.Database)" -Level Verbose
            } elseif ($ReplaceDatabaseNameType -eq 'multi') {
                if ($null -ne $ReplaceDatabaseName[$History.Database]) {
                    $History.Database = $ReplaceDatabaseName[$History.Database]
                    Write-Message -Message "New DbName (Hash) = $($History.Database)" -Level Verbose
                }
            }
            $History.Database = $DatabaseNamePrefix + $History.Database

            $History.FileList | ForEach-Object {
                if ($null -ne $FileMapping ) {
                    if ($null -ne $FileMapping[$_.LogicalName]) {
                        $_.PhysicalName = $FileMapping[$_.LogicalName]
                    }
                } else {
                    if ($ReplaceDbNameInFile -eq $true) {
                        $_.PhysicalName = $_.PhysicalName -Replace $History.OriginalDatabase, $History.Database
                    }
                    Write-Message -Message " 1 PhysicalName = $($_.PhysicalName) " -Level Verbose
                    $Pname = [System.Io.FileInfo]$_.PhysicalName
                    $RestoreDir = $Pname.DirectoryName
                    if ($_.Type -eq 'D' -or $_.FileType -eq 'D') {
                        if ('' -ne $DataFileDirectory) {
                            $RestoreDir = $DataFileDirectory
                        }
                    } elseif ($_.Type -eq 'L' -or $_.FileType -eq 'L') {
                        if ('' -ne $LogFileDirectory) {
                            $RestoreDir = $LogFileDirectory
                        } elseif ('' -ne $DataFileDirectory) {
                            $RestoreDir = $DataFileDirectory
                        }
                    } elseif ($_.Type -eq 'S' -or $_.FileType -eq 'S') {
                        if ('' -ne $DestinationFileStreamDirectory) {
                            $RestoreDir = $DestinationFileStreamDirectory
                        } elseif ('' -ne $DataFileDirectory) {
                            $RestoreDir = $DataFileDirectory
                        }
                    }

                    $_.PhysicalName = $RestoreDir + $PathSep + $DatabaseFilePrefix + $Pname.BaseName + $DatabaseFileSuffix + $Pname.extension
                    Write-Message -Message "PhysicalName = $($_.PhysicalName) " -Level Verbose
                }
            }
            if ('' -ne $RebaseBackupFolder -and $History.FullName[0] -notmatch 'http') {
                Write-Message -Message 'Rebasing backup files' -Level Verbose

                for ($j = 0; $j -lt $History.fullname.count; $j++) {
                    $file = [System.IO.FileInfo]($History.fullname[$j])
                    $History.fullname[$j] = $RebaseBackupFolder + $PathSep + $file.BaseName + $file.Extension
                }

            }

            $History
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUR9gHHxJCF3H0SV5VsGa8ls/R
# 2AqgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFBABqlFXjcjcoBBCQqcPM1OdomaaMA0GCSqGSIb3DQEBAQUABIIBABUgNqkz
# 9cxqRZCjMixqo/X93DOl8KZfgy74sBG1mNcbs8ID5mkS4p0XBLoLePTt63Cqs2wY
# LnyBkuHs48ajIDZdsFpO7enJhbqK62V94ZTGbm0oyEcBlJLj8WdrhQ/QVcbY0dil
# +kw8JucI7BVZhwucA3YgwFg1/lzO+CkzDVGRFjiHn0K1OlE5w3RDMJeGqy0rSsHt
# g9BdFwswyJiCtiWY8qfiorkOwQQBNGYFH3I0Qc3NqjvxdnGRSu7M60XJkfdOUEah
# +KThI3BFenDU6e9QfshXMbDxweEuPVZb+2fstEB55Yo7qFuSljrEWDEG2yMUrybd
# 3O9Porqm9wlOk+yhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUwN1owLwYJKoZIhvcNAQkEMSIEIA2WLUGWl89P8Gmv0rsf1Y0KofGP
# /bPd2swL2nOzPt8oMA0GCSqGSIb3DQEBAQUABIIBAE2BmDfbmF62KZbrVGF2r/lf
# rsYID5wnXLFFTyi8BctleETNyOAZ6MdmlOLD9wX6sP2ULrMLPgg3f6tnWYM0iIJE
# XKmZ7vOvV+rN3/Y8dxcxk/aN/gsQzz/6j2QL7wLd6SOzfXTCt3o9F46fouO7Zqr+
# E++FwHV2R8RVpZ/JUE3XZDzvTgXSfSgk+dh+x+8/p7lB/OcHnTq42PNrRt3H5jzx
# +tHHQAYmiLjYcASvu27QcjNo6lpBI581dzHsZ/wwsH2lFKYp6mKTlxcUaTBOtw8I
# vHoH+hGztwz0uajzKN1/hZUHezZw535FcX2ZLy2kWnT6pqGIKMlzRnUOvE7a+ts=
# SIG # End signature block
