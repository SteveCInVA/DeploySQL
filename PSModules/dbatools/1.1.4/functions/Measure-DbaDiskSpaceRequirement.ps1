function Measure-DbaDiskSpaceRequirement {
    <#
    .SYNOPSIS
        Calculate the space needed to copy and possibly replace a database from one SQL server to another.

    .DESCRIPTION
        Returns a file list from source and destination where source file may overwrite destination. Complex scenarios where a new file may exist is taken into account.
        This command will accept a hash object in pipeline with the following keys: Source, SourceDatabase, Destination. Using this command will provide a way to prepare before a complex migration with multiple databases from different sources and destinations.

    .PARAMETER Source
        Source SQL Server.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database to copy. It MUST exist.

    .PARAMETER Destination
        Destination SQL Server instance.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationDatabase
        The database name at destination.
        May or may not be present, if unspecified it will default to the database name provided in SourceDatabase.

    .PARAMETER Credential
        The credentials to use to connect via CIM/WMI/PowerShell remoting.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Server, Management, Space, Database
        Author: Pollus Brodeur (@pollusb)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Measure-DbaDiskSpaceRequirement

    .EXAMPLE
        PS C:\> Measure-DbaDiskSpaceRequirement -Source INSTANCE1 -Database DB1 -Destination INSTANCE2

        Calculate space needed for a simple migration with one database with the same name at destination.

    .EXAMPLE
        PS C:\> @(
        >> [PSCustomObject]@{Source='SQL1';Destination='SQL2';Database='DB1'},
        >> [PSCustomObject]@{Source='SQL1';Destination='SQL2';Database='DB2'}
        >> ) | Measure-DbaDiskSpaceRequirement

        Using a PSCustomObject with 2 databases to migrate on SQL2.

    .EXAMPLE
        PS C:\> Import-Csv -Path .\migration.csv -Delimiter "`t" | Measure-DbaDiskSpaceRequirement | Format-Table -AutoSize

        Using a CSV file. You will need to use this header line "Source<tab>Destination<tab>Database<tab>DestinationDatabase".

    .EXAMPLE
        PS C:\> $qry = "SELECT Source, Destination, Database FROM dbo.Migrations"
        PS C:\> Invoke-DbaCmd -SqlInstance DBA -Database Migrations -Query $qry | Measure-DbaDiskSpaceRequirement

        Using a SQL table. We are DBA after all!
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter]$Source,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Database,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$SourceSqlCredential,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter]$Destination,
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DestinationDatabase,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$DestinationSqlCredential,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    begin {
        $local:cacheMP = @{ }
        $local:cacheDP = @{ }
        function Get-MountPoint {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                $computerName,
                [PSCredential]$credential
            )
            Get-DbaCmObject -Class Win32_MountPoint -ComputerName $computerName -Credential $credential | Select-Object @{n = 'Mountpoint'; e = { $_.Directory.split('=')[1].Replace('"', '').Replace('\\', '\') } }
        }
        function Get-MountPointFromPath {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                $path,
                [Parameter(Mandatory)]
                $computerName,
                [PSCredential]$credential
            )
            if (!$cacheMP[$computerName]) {
                try {
                    $cacheMP.Add($computerName, (Get-MountPoint -computerName $computerName -credential $credential))
                    Write-Message -Level Verbose -Message "cacheMP[$computerName] is now cached"
                } catch {
                    # This way, I won't be asking again for this computer.
                    $cacheMP.Add($computerName, '?')
                    Stop-Function -Message "Can't connect to $computerName. cacheMP[$computerName] = ?" -ErrorRecord $_ -Target $computerName -Continue
                }
            }
            if ($cacheMP[$computerName] -eq '?') {
                return '?'
            }
            foreach ($m in ($cacheMP[$computerName] | Sort-Object -Property Mountpoint -Descending)) {
                if ($path -like "$($m.Mountpoint)*") {
                    return $m.Mountpoint
                }
            }
            Write-Message -Level Warning -Message "Path $path can't be found in any MountPoints of $computerName"
        }
        function Get-MountPointFromDefaultPath {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [ValidateSet('Log', 'Data')]
                $DefaultPathType,
                [Parameter(Mandatory)]
                $SqlInstance,
                [PSCredential]$SqlCredential,
                # Could probably use the computer defined in SqlInstance but info was already available from the caller
                $computerName,
                [PSCredential]$Credential
            )
            if (!$cacheDP[$SqlInstance]) {
                try {
                    $cacheDP.Add($SqlInstance, (Get-DbaDefaultPath -SqlInstance $SqlInstance -SqlCredential $SqlCredential -EnableException))
                    Write-Message -Level Verbose -Message "cacheDP[$SqlInstance] is now cached"
                } catch {
                    Stop-Function -Message "Can't connect to $SqlInstance" -Continue
                    $cacheDP.Add($SqlInstance, '?')
                    return '?'
                }
            }
            if ($cacheDP[$SqlInstance] -eq '?') {
                return '?'
            }
            if (!$computerName) {
                $computerName = $cacheDP[$SqlInstance].ComputerName
            }
            if (!$cacheMP[$computerName]) {
                try {
                    $cacheMP.Add($computerName, (Get-MountPoint -computerName $computerName -Credential $Credential))
                } catch {
                    Stop-Function -Message "Can't connect to $computerName." -Continue
                    $cacheMP.Add($computerName, '?')
                    return '?'
                }
            }
            if ($DefaultPathType -eq 'Log') {
                $path = $cacheDP[$SqlInstance].Log
            } else {
                $path = $cacheDP[$SqlInstance].Data
            }
            foreach ($m in ($cacheMP[$computerName] | Sort-Object -Property Mountpoint -Descending)) {
                if ($path -like "$($m.Mountpoint)*") {
                    return $m.Mountpoint
                }
            }
        }
    }
    process {
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
        }

        try {
            $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $Destination
        }

        if (Test-Bound 'DestinationDatabase' -not) {
            $DestinationDatabase = $Database
        }
        Write-Message -Level Verbose -Message "$Source.[$Database] -> $Destination.[$DestinationDatabase]"

        $sourceDb = Get-DbaDatabase -SqlInstance $sourceServer -Database $Database -SqlCredential $SourceSqlCredential
        if (Test-Bound 'Database' -not) {
            Stop-Function -Message "Database [$Database] MUST exist on Source Instance $Source." -ErrorRecord $_
        }
        $sourceFiles = @($sourceDb.FileGroups.Files | Select-Object Name, FileName, Size, @{n = 'Type'; e = { 'Data' } })
        $sourceFiles += @($sourceDb.LogFiles | Select-Object Name, FileName, Size, @{n = 'Type'; e = { 'Log' } })

        if ($destDb = Get-DbaDatabase -SqlInstance $destServer -Database $DestinationDatabase -SqlCredential $DestinationSqlCredential) {
            $destFiles = @($destDb.FileGroups.Files | Select-Object Name, FileName, Size, @{n = 'Type'; e = { 'Data' } })
            $destFiles += @($destDb.LogFiles | Select-Object Name, FileName, Size, @{n = 'Type'; e = { 'Log' } })
            $computerName = $destDb.ComputerName
        } else {
            Write-Message -Level Verbose -Message "Database [$DestinationDatabase] does not exist on Destination Instance $Destination."
            $computerName = $destServer.ComputerName
        }

        foreach ($sourceFile in $sourceFiles) {
            foreach ($destFile in $destFiles) {
                if (($found = ($sourceFile.Name -eq $destFile.Name))) {
                    # Files found on both sides
                    [PSCustomObject]@{
                        SourceComputerName      = $sourceServer.ComputerName
                        SourceInstance          = $sourceServer.ServiceName
                        SourceSqlInstance       = $sourceServer.DomainInstanceName
                        DestinationComputerName = $destServer.ComputerName
                        DestinationInstance     = $destServer.ServiceName
                        DestinationSqlInstance  = $destServer.DomainInstanceName
                        SourceDatabase          = $sourceDb.Name
                        SourceLogicalName       = $sourceFile.Name
                        SourceFileName          = $sourceFile.FileName
                        SourceFileSize          = [DbaSize]($sourceFile.Size * 1000)
                        DestinationDatabase     = $destDb.Name
                        DestinationLogicalName  = $destFile.Name
                        DestinationFileName     = $destFile.FileName
                        DestinationFileSize     = [DbaSize]($destFile.Size * 1000) * -1
                        DifferenceSize          = [DbaSize]( ($sourceFile.Size * 1000) - ($destFile.Size * 1000) )
                        MountPoint              = Get-MountPointFromPath -Path $destFile.Filename -ComputerName $computerName -Credential $Credential
                        FileLocation            = 'Source and Destination'
                    } | Select-DefaultView -ExcludeProperty SourceComputerName, SourceInstance, DestinationInstance, DestinationLogicalName
                    break
                }
            }
            if (!$found) {
                # Files on source but not on destination
                [PSCustomObject]@{
                    SourceComputerName      = $sourceServer.ComputerName
                    SourceInstance          = $sourceServer.ServiceName
                    SourceSqlInstance       = $sourceServer.DomainInstanceName
                    DestinationComputerName = $destServer.ComputerName
                    DestinationInstance     = $destServer.ServiceName
                    DestinationSqlInstance  = $destServer.DomainInstanceName
                    SourceDatabase          = $sourceDb.Name
                    SourceLogicalName       = $sourceFile.Name
                    SourceFileName          = $sourceFile.FileName
                    SourceFileSize          = [DbaSize]($sourceFile.Size * 1000)
                    DestinationDatabase     = $DestinationDatabase
                    DestinationLogicalName  = $null
                    DestinationFileName     = $null
                    DestinationFileSize     = [DbaSize]0
                    DifferenceSize          = [DbaSize]($sourceFile.Size * 1000)
                    MountPoint              = Get-MountPointFromDefaultPath -DefaultPathType $sourceFile.Type -SqlInstance $Destination `
                        -SqlCredential $DestinationSqlCredential -computerName $computerName -credential $Credential
                    FileLocation            = 'Only on Source'
                } | Select-DefaultView -ExcludeProperty SourceComputerName, SourceInstance, DestinationInstance, DestinationLogicalName
            }
        }
        if ($destDb) {
            # Files on destination but not on source (strange scenario but possible)
            $destFilesNotSource = Compare-Object -ReferenceObject $destFiles -DifferenceObject $sourceFiles -Property Name -PassThru
            foreach ($destFileNotSource in $destFilesNotSource) {
                [PSCustomObject]@{
                    SourceComputerName      = $sourceServer.ComputerName
                    SourceInstance          = $sourceServer.ServiceName
                    SourceSqlInstance       = $sourceServer.DomainInstanceName
                    DestinationComputerName = $destServer.ComputerName
                    DestinationInstance     = $destServer.ServiceName
                    DestinationSqlInstance  = $destServer.DomainInstanceName
                    SourceDatabaseName      = $Database
                    SourceLogicalName       = $null
                    SourceFileName          = $null
                    SourceFileSize          = [DbaSize]0
                    DestinationDatabaseName = $destDb.Name
                    DestinationLogicalName  = $destFileNotSource.Name
                    DestinationFileName     = $destFile.FileName
                    DestinationFileSize     = [DbaSize]($destFileNotSource.Size * 1000) * -1
                    DifferenceSize          = [DbaSize]($destFileNotSource.Size * 1000) * -1
                    MountPoint              = Get-MountPointFromPath -Path $destFileNotSource.Filename -ComputerName $computerName -Credential $Credential
                    FileLocation            = 'Only on Destination'
                } | Select-DefaultView -ExcludeProperty SourceComputerName, SourceInstance, DestinationInstance, DestinationLogicalName
            }
        }
        $DestinationDatabase = $null
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUxxZ9wigtlxjhH3NpZKP131vJ
# bBSgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFFNIlgLONg5QBcjCiU2MISkyIYXTMA0GCSqGSIb3DQEBAQUABIIBAHr5NJjB
# WvJTEG59F7veFsC+engCQIEF98jPk7R//WspkD2rC0MoJz2P49RgHlOY3yiVsf2o
# +A656tMMiX15ZcEcDRsiIHRUkSO/9foPcO586D5o0MYYYTTXYfhX77HIFjrbDwwq
# mk0iKonJC1Ki42qJ0GUZB7McmgT5kf5izeEqc3UmE6VxhMF5Qe2uZYeMdLv7Cf1T
# f3cxgjmBn/vLurYHGpOlMl3eGkBoqDzw3aeoJAVySAhVYN0U6tw+DoWIJbRyrLg4
# iMqfsv2Lxx/estAKqOP7l5XCartOorUFHpYK6UVXJHBK8icA1njROWwSzIQlPUtt
# peyYmKcj4InIYc+hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk1MlowLwYJKoZIhvcNAQkEMSIEIOSuzOs3dRL+MVs8ELtGiRLOd00Z
# CiY0WUkX1UqrqyUyMA0GCSqGSIb3DQEBAQUABIIBAE1P/PQX3vnrBSnBt2Ub7c2U
# gqxRv9VUZT1sQkg/y2PZ806WJMAfJTthRcmfRaSVZ7owzQM4oE0qTpqXMyZ1Y5d2
# Vt9Ea3lr6tWHn9JIKgRkU4QykFoB7ahMiyiGna8OnjHVB5nwXNTj60QvlcY6Ubyf
# NgVuX76rXIxIo4ZIDCH1/UbQNrfupalRoAtsZWSpJQwR5xwHRvzoahEg3A0uilU/
# 5unXMMxCSfJhcWuucRwVi4s9WBJniDISUyjSJkdwOVSAa849lBDRRMAWvJtHgjLR
# 1VrFTcY0mRPA4ZHXrXQTb74u/HDwCemNL/vkV/NTPw4cRG4DMytNdHSlhk+lMzU=
# SIG # End signature block
