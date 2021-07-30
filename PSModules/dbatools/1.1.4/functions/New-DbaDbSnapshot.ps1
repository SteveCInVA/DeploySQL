function New-DbaDbSnapshot {
    <#
    .SYNOPSIS
        Creates database snapshots

    .DESCRIPTION
        Creates database snapshots without hassles

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AllDatabases
        Creates snapshot for all eligible databases

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step.

    .PARAMETER Name
        The specific snapshot name you want to create. Works only if you target a single database. If you need to create multiple snapshot,
        you must use the NameSuffix parameter

    .PARAMETER NameSuffix
        When you pass a simple string, it'll be appended to use it to build the name of the snapshot. By default snapshots are created with yyyyMMdd_HHmmss suffix
        You can also pass a standard placeholder, in which case it'll be interpolated (e.g. '{0}' gets replaced with the database name)

    .PARAMETER Path
        Snapshot files will be created here (by default the file structure will be created in the same folder as the base db)

    .PARAMETER InputObject
        Allows Piping from Get-DbaDatabase

    .PARAMETER Force
        Databases with Filestream FG can be snapshotted, but the Filestream FG is marked offline
        in the snapshot. To create a "partial" snapshot, you need to pass -Force explicitly

        NB: You can't then restore the Database from the newly-created snapshot.
        For details, check https://msdn.microsoft.com/en-us/library/bb895334.aspx

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Snapshot, Restore, Database
        Author: Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbSnapshot

    .EXAMPLE
        PS C:\> New-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting

        Creates snapshot for HR and Accounting, returning a custom object displaying Server, Database, DatabaseCreated, SnapshotOf, SizeMB, DatabaseCreated, PrimaryFilePath, Status, Notes

    .EXAMPLE
        PS C:\> New-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR -Name HR_snap

        Creates snapshot named "HR_snap" for HR

    .EXAMPLE
        PS C:\> New-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR -NameSuffix 'fool_{0}_snap'

        Creates snapshot named "fool_HR_snap" for HR

    .EXAMPLE
        PS C:\> New-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting -Path F:\snapshotpath

        Creates snapshots for HR and Accounting databases, storing files under the F:\snapshotpath\ dir

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database df | New-DbaDbSnapshot

        Creates a snapshot for the database df on sql2016

    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [string]$Name,
        [string]$NameSuffix,
        [string]$Path,
        [switch]$Force,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $NoSupportForSnap = @('model', 'master', 'tempdb')
        # Evaluate the default suffix here for naming consistency
        $DefaultSuffix = (Get-Date -Format "yyyyMMdd_HHmmss")
        if ($NameSuffix.Length -gt 0) {
            #Validate if Name can be interpolated
            try {
                $null = $NameSuffix -f 'some_string'
            } catch {
                Stop-Function -Message "NameSuffix parameter must be a template only containing one parameter {0}" -ErrorRecord $_
            }
        }

        function Resolve-SnapshotError($server) {
            $errHelp = ''
            $CurrentEdition = $server.Edition.ToLowerInvariant()
            $CurrentVersion = $server.Version.Major * 1000000 + $server.Version.Minor * 10000 + $server.Version.Build
            if ($server.Version.Major -lt 9) {
                $errHelp = 'Not supported before 2005'
            }
            if ($CurrentVersion -lt 12002000 -and $errHelp.Length -eq 0) {
                if ($CurrentEdition -notmatch '.*enterprise.*|.*developer.*|.*datacenter.*') {
                    $errHelp = 'Supported only for Enterprise, Developer or Datacenter editions'
                }
            }
            $message = ""
            if ($errHelp.Length -gt 0) {
                $message += "Please make sure your version supports snapshots : ($errHelp)"
            } else {
                $message += "This module can't tell you why the snapshot creation failed. Feel free to report back to dbatools what happened"
            }
            Write-Message -Level Warning -Message $message
        }
    }
    process {
        if (-not $InputObject -and -not $Database -and $AllDatabases -eq $false) {
            Stop-Function -Message "You must specify a -AllDatabases or -Database to continue" -EnableException $EnableException
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            #Checks for path existence, left the length test because test-bound wasn't working for some reason
            if ($Path.Length -gt 0) {
                if (!(Test-DbaPath -SqlInstance $server -Path $Path)) {
                    Stop-Function -Message "$instance cannot access the directory $Path" -ErrorRecord $_ -Target $instance -Continue -EnableException $EnableException
                }
            }

            if ($AllDatabases) {
                $dbs = $server.Databases
            }

            if ($Database) {
                $dbs = $server.Databases | Where-Object { $Database -contains $_.Name }
            }

            if ($ExcludeDatabase) {
                $dbs = $server.Databases | Where-Object { $ExcludeDatabase -notcontains $_.Name }
            }

            ## double check for gotchas
            foreach ($db in $dbs) {
                if ($db.IsMirroringEnabled) {
                    $InputObject += $db
                } elseif ($db.IsDatabaseSnapshot) {
                    Write-Message -Level Warning -Message "$($db.name) is a snapshot, skipping"
                } elseif ($db.name -in $NoSupportForSnap) {
                    Write-Message -Level Warning -Message "$($db.name) snapshots are prohibited"
                } elseif ($db.IsAccessible -ne $true) {
                    Write-Message -Level Verbose -Message "$($db.name) is not accessible, skipping"
                } else {
                    $InputObject += $db
                }
            }

            if ($InputObject.Count -gt 1 -and $Name) {
                Stop-Function -Message "You passed the Name parameter that is fixed but selected multiple databases to snapshot: use the NameSuffix parameter" -Continue -EnableException $EnableException
            }
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            # In case stuff is piped in
            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "SQL Server version 9 required - $server not supported" -Continue
            }

            if ($NameSuffix.Length -gt 0) {
                $SnapName = $NameSuffix -f $db.Name
                if ($SnapName -eq $NameSuffix) {
                    #no interpolation, just append
                    $SnapName = '{0}{1}' -f $db.Name, $NameSuffix
                }
            } elseif ($Name.Length -gt 0) {
                $SnapName = $Name
            } else {
                $SnapName = "{0}_{1}" -f $db.Name, $DefaultSuffix
            }
            if ($SnapName -in $server.Databases.Name) {
                Write-Message -Level Warning -Message "A database named $SnapName already exists, skipping"
                continue
            }
            $all_FSD = $db.FileGroups | Where-Object FileGroupType -eq 'FileStreamDataFileGroup'
            $all_MMO = $db.FileGroups | Where-Object FileGroupType -eq 'MemoryOptimizedDataFileGroup'
            $has_FSD = $all_FSD.Count -gt 0
            $has_MMO = $all_MMO.Count -gt 0
            if ($has_MMO) {
                Write-Message -Level Warning -Message "MEMORY_OPTIMIZED_DATA detected, snapshots are not possible"
                continue
            }
            if ($has_FSD -and $Force -eq $false) {
                Write-Message -Level Warning -Message "Filestream detected, skipping. You need to specify -Force. See Get-Help for details"
                continue
            }
            $snapType = "db snapshot"
            if ($has_FSD) {
                $snapType = "partial db snapshot"
            }
            If ($PSCmdlet.ShouldProcess($server, "Create $snapType $SnapName of $($db.Name)")) {
                $CustomFileStructure = @{ }
                $counter = 0
                foreach ($fg in $db.FileGroups) {
                    $CustomFileStructure[$fg.Name] = @()
                    if ($fg.FileGroupType -eq 'FileStreamDataFileGroup') {
                        Continue
                    }
                    foreach ($file in $fg.Files) {
                        $counter += 1
                        # Linux can't handle windows paths, so split it
                        $basename = [IO.Path]::GetFileNameWithoutExtension((Split-Path $file.FileName -Leaf))
                        $basePath = Split-Path $file.FileName -Parent
                        # change path if specified
                        if ($Path.Length -gt 0) {
                            $basePath = $Path
                        }

                        # we need to avoid cases where basename is the same for multiple FG
                        $fName = [IO.Path]::Combine($basePath, ("{0}_{1}_{2:0000}_{3:000}" -f $basename, $DefaultSuffix, (Get-Date).MilliSecond, $counter))
                        # fixed extension is hardcoded as "ss", which seems a "de-facto" standard
                        $fName = [IO.Path]::ChangeExtension($fName, "ss")
                        Write-Message -Level Debug -Message "$fName"

                        # change slashes for Linux, change slashes for Windows
                        if ($server.HostPlatform -eq 'Linux') {
                            $fName = $fName.Replace("\", "/")
                        } else {
                            $fName = $fName.Replace("/", "\")
                        }
                        $CustomFileStructure[$fg.Name] += @{ 'name' = $file.name; 'filename' = $fName }
                    }
                }

                $SnapDB = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $SnapName
                $SnapDB.DatabaseSnapshotBaseName = $db.Name

                foreach ($fg in $CustomFileStructure.Keys) {
                    $SnapFG = New-Object -TypeName Microsoft.SqlServer.Management.Smo.FileGroup $SnapDB, $fg
                    $SnapDB.FileGroups.Add($SnapFG)
                    foreach ($file in $CustomFileStructure[$fg]) {
                        $SnapFile = New-Object -TypeName Microsoft.SqlServer.Management.Smo.DataFile $SnapFG, $file['name'], $file['filename']
                        $SnapDB.FileGroups[$fg].Files.Add($SnapFile)
                    }
                }

                # we're ready to issue a Create, but SMO is a little uncooperative here
                # there are cases we can manage and others we can't, and we need all the
                # info we can get both from testers and from users

                $sql = $SnapDB.Script()

                try {
                    $SnapDB.Create()
                    $server.Databases.Refresh()
                    Get-DbaDbSnapshot -SqlInstance $server -Snapshot $SnapName
                } catch {
                    try {
                        $server.Databases.Refresh()
                        if ($SnapName -notin $server.Databases.Name) {
                            # previous creation failed completely, snapshot is not there already
                            $null = $server.Query($sql[0])
                            $server.Databases.Refresh()
                            $SnapDB = Get-DbaDbSnapshot -SqlInstance $server -Snapshot $SnapName
                        } else {
                            $SnapDB = Get-DbaDbSnapshot -SqlInstance $server -Snapshot $SnapName
                        }

                        $Notes = @()
                        if ($db.ReadOnly -eq $true) {
                            $Notes += 'SMO is probably trying to set a property on a read-only snapshot, run with -Debug to find out and report back'
                        }
                        if ($has_FSD) {
                            #Variable marked as unused by PSScriptAnalyzer
                            #$Status = 'Partial'
                            $Notes += 'Filestream groups are not viable for snapshot'
                        }
                        $Notes = $Notes -Join ';'

                        $hints = @("Executing these commands led to a partial failure")
                        foreach ($stmt in $sql) {
                            $hints += $stmt
                        }

                        Write-Message -Level Debug -Message ($hints -Join "`n")

                        $SnapDB
                    } catch {
                        # Resolve-SnapshotError $server
                        $hints = @("Executing these commands led to a failure")
                        foreach ($stmt in $sql) {
                            $hints += $stmt
                        }
                        Write-Message -Level Debug -Message ($hints -Join "`n")

                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $SnapDB -Continue
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUsXeYBehUQveU+AD5dcplNKAH
# /KigghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFIFR+tBAdoBhICPPiZVK8EbAyOc+MA0GCSqGSIb3DQEBAQUABIIBAGn2MI3a
# L+Sfe24fwod1GE6WzSJsjFa8OiYpJPhmn1mzgHxq/4JlmnhIBkLnEDVtN09eTxJS
# nqGxw5uRQxietZreCaToUPlv+YR6vrO+y1bcyqiibMDMPfv3u6krVsETDRvHPwyp
# H3mMY//DgSfmiQtZbfdfjfwU5TZdWJLxE0GV1zXKdjuxFi9hfWzcO3MCCnC8w/HG
# 71nVytNxpYOvYxLVz9u+c8mBU2lZMerHgZ4ftAGoa2sdUogVIiWFAizICcqKxz2O
# 5lAYIpfV7fmumrwkF7NCkxPDHfW4494N36aKTXstMrjv1xX/fIQx1hPtWt4vZUwF
# I6aO1OWHjeh//YyhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk1NlowLwYJKoZIhvcNAQkEMSIEICwDFALxha7g9dgHOS1qumd7r/h8
# 0tNIjHvZaee8SFnjMA0GCSqGSIb3DQEBAQUABIIBAKP/k2CEHBs2T4Pdg4yXXrTz
# Pgqg1kodsiuC8wUeYY1TyENSvTdufN8id8Tp7NIyTkvmpw1lYxA8KOj/co22hWhn
# /4ZsNM5YEnq0i3ZeLSFwZY+SXPainwMPeDrrG2kzrmHeck+Ssl6Cjvgo7ZeTmIOU
# Ujwvm1ogeaNtLGo2XnAPaPMFddj6sMUKBx8Agt/AEqLTiE/RsZYQQaI2P8DpgxUS
# kNcO4QFXq4DuFHkmODcT0WY7+du9l9iLnx7VMVVFt01S8P8cqsHCeFYqcN7aMbec
# 1JpuliNv0GpoCkoWjDSzvn16wYvb4rLZIVuMDDx79yqhg26XveLWzqds78HjCts=
# SIG # End signature block
