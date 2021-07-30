function Set-DbaDbCompression {
    <#
    .SYNOPSIS
        Sets tables and indexes with preferred compression setting.

    .DESCRIPTION
        This function sets the appropriate compression recommendation, determined either by using the Tiger Team's query or set to the CompressionType parameter.

        Remember Uptime is critical for the Tiger Team query, the longer uptime, the more accurate the analysis is.
        You would probably be best if you utilized Get-DbaUptime first, before running this command.

        Set-DbaDbCompression script derived from GitHub and the tigertoolbox
        (https://github.com/Microsoft/tigertoolbox/tree/master/Evaluate-Compression-Gains)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto populated from the server.

    .PARAMETER Table
        The table(s) to process. If unspecified, all tables will be processed.

    .PARAMETER CompressionType
        Control the compression type applied. Default is 'Recommended' which uses the Tiger Team query to use the most appropriate setting per object. Other option is to compress all objects to either Row or Page.

    .PARAMETER MaxRunTime
        Will continue to alter tables and indexes for the given amount of minutes.

    .PARAMETER PercentCompression
        Will only work on the tables/indexes that have the calculated savings at and higher for the given number provided.

    .PARAMETER InputObject
        Takes the output of Test-DbaDbCompression as an object and applied compression based on those recommendations.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Compression, Table, Database
        Author: Jason Squires (@js_0505), jstexasdba@gmail.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbCompression

    .EXAMPLE
        PS C:\> Set-DbaDbCompression -SqlInstance localhost -MaxRunTime 60 -PercentCompression 25

        Set the compression run time to 60 minutes and will start the compression of tables/indexes that have a difference of 25% or higher between current and recommended.

    .EXAMPLE
        PS C:\> Set-DbaDbCompression -SqlInstance ServerA -Database DBName -CompressionType Page -Table table1, table2

        Utilizes Page compression for tables table1 and table2 in DBName on ServerA with no time limit.

    .EXAMPLE
        PS C:\> Set-DbaDbCompression -SqlInstance ServerA -Database DBName -PercentCompression 25 | Out-GridView

        Will compress tables/indexes within the specified database that would show any % improvement with compression and with no time limit. The results will be piped into a nicely formatted GridView.

    .EXAMPLE
        PS C:\> $testCompression = Test-DbaDbCompression -SqlInstance ServerA -Database DBName
        PS C:\> Set-DbaDbCompression -SqlInstance ServerA -Database DBName -InputObject $testCompression

        Gets the compression suggestions from Test-DbaDbCompression into a variable, this can then be reviewed and passed into Set-DbaDbCompression.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Set-DbaDbCompression -SqlInstance ServerA -ExcludeDatabase Database -SqlCredential $cred -MaxRunTime 60 -PercentCompression 25

        Set the compression run time to 60 minutes and will start the compression of tables/indexes for all databases except the specified excluded database. Only objects that have a difference of 25% or higher between current and recommended will be compressed.

    .EXAMPLE
        PS C:\> $servers = 'Server1','Server2'
        PS C:\> foreach ($svr in $servers) {
        >> Set-DbaDbCompression -SqlInstance $svr -MaxRunTime 60 -PercentCompression 25 | Export-Csv -Path C:\temp\CompressionAnalysisPAC.csv -Append
        >> }

        Set the compression run time to 60 minutes and will start the compression of tables/indexes across all listed servers that have a difference of 25% or higher between current and recommended. Output of command is exported to a csv.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Table,
        [ValidateSet("Recommended", "Page", "Row", "None")]
        [string]$CompressionType = "Recommended",
        [int]$MaxRunTime = 0,
        [int]$PercentCompression = 0,
        $InputObject,
        [switch]$EnableException
    )

    process {
        $starttime = Get-Date
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failed to process Instance $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            $Server.ConnectionContext.StatementTimeout = 0

            #The reason why we do this is because of SQL 2016 and they now allow for compression on standard edition.
            if ($server.EngineEdition -notmatch 'Enterprise' -and $server.VersionMajor -lt '13') {
                Stop-Function -Message "Only SQL Server Enterprise Edition supports compression on $server" -Target $server -Continue
            }
            try {
                $dbs = $server.Databases | Where-Object { $_.IsAccessible -and $_.IsSystemObject -eq 0 }
                if ($Database) {
                    $dbs = $dbs | Where-Object { $_.Name -in $Database }
                }
                if ($ExcludeDatabase) {
                    $dbs = $dbs | Where-Object { $_.Name -NotIn $ExcludeDatabase }
                }
            } catch {
                Stop-Function -Message "Unable to gather list of databases for $instance" -Target $instance -ErrorRecord $_ -Continue
            }

            foreach ($db in $dbs) {
                try {
                    Write-Message -Level Verbose -Message "Querying $instance - $db"
                    if ($db.status -ne 'Normal' -or $db.IsAccessible -eq $false) {
                        Write-Message -Level Warning -Message "$db is not accessible" -Target $db
                        continue
                    }
                    if ($db.CompatibilityLevel -lt 'Version100') {
                        Stop-Function -Message "$db has a compatibility level lower than Version100 and will be skipped." -Target $db -Continue
                    }
                    if ($CompressionType -eq "Recommended") {
                        if (Test-Bound "InputObject") {
                            Write-Message -Level Verbose -Message "Using passed in compression suggestions"
                            $compressionSuggestion = $InputObject | Where-Object { $_.Database -eq $db.name }
                        } else {
                            Write-Message -Level Verbose -Message "Testing database for compression suggestions for $instance.$db"
                            $compressionSuggestion = Test-DbaDbCompression -SqlInstance $server -Database $db.Name -Table $Table
                        }
                    }
                } catch {
                    Stop-Function -Message "Unable to query $instance - $db" -Target $db -ErrorRecord $_ -Continue
                }

                try {
                    if ($CompressionType -eq "Recommended") {
                        if ($Pscmdlet.ShouldProcess($db, "Applying suggested compression using results from Test-DbaDbCompression")) {
                            Write-Message -Level Verbose -Message "Applying suggested compression settings using Test-DbaDbCompression"
                            $results += $compressionSuggestion | Select-Object *, @{l = 'AlreadyProcessed'; e = { "False" } }
                            foreach ($obj in ($results | Where-Object { $_.CompressionTypeRecommendation -notin @('NO_GAIN', '?') -and $_.PercentCompression -ge $PercentCompression } | Sort-Object PercentCompression -Descending)) {
                                if ($MaxRunTime -ne 0 -and ($(Get-Date) - $starttime).TotalMinutes -ge $MaxRunTime) {
                                    Write-Message -Level Verbose -Message "Reached max run time of $MaxRunTime"
                                    break
                                }
                                if ($obj.indexId -le 1) {
                                    ##heaps and clustered indexes
                                    Write-Message -Level Verbose -Message "Applying $($obj.CompressionTypeRecommendation) compression to $($obj.Database).$($obj.Schema).$($obj.TableName)"
                                    $($server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $obj.Partition }).DataCompression = $($obj.CompressionTypeRecommendation)
                                    $server.Databases[$obj.Database].Tables[$obj.TableName, $($obj.Schema)].Rebuild()
                                    $obj.AlreadyProcessed = "True"
                                } else {
                                    ##nonclustered indexes
                                    Write-Message -Level Verbose -Message "Applying $($obj.CompressionTypeRecommendation) compression to $($obj.Database).$($obj.Schema).$($obj.TableName).$($obj.IndexName)"
                                    $($server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].Indexes[$obj.IndexName].PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $obj.Partition }).DataCompression = $($obj.CompressionTypeRecommendation)
                                    $server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].Indexes[$obj.IndexName].Rebuild()
                                    $obj.AlreadyProcessed = "True"
                                }
                                $obj
                            }
                        }
                    } else {
                        if ($Pscmdlet.ShouldProcess($db, "Applying $CompressionType compression")) {
                            Write-Message -Level Verbose -Message "Applying $CompressionType compression to objects in $($db.name)"
                            $tables = $server.Databases[$($db.name)].Tables

                            if ($Table) {
                                $tables = $tables | Where-Object Name -in $Table
                            }

                            foreach ($obj in $tables | Where-Object { !$_.IsMemoryOptimized -and !$_.HasSparseColumn }) {
                                if ($MaxRunTime -ne 0 -and ($(Get-Date) - $starttime).TotalMinutes -ge $MaxRunTime) {
                                    Write-Message -Level Verbose -Message "Reached max run time of $MaxRunTime"
                                    break
                                }
                                foreach ($p in $($obj.PhysicalPartitions | Where-Object { $_.DataCompression -notin ($CompressionType, 'ColumnStore', 'ColumnStoreArchive') })) {
                                    Write-Message -Level Verbose -Message "Compressing table $($obj.Schema).$($obj.Name)"
                                    $($obj.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $P.PartitionNumber }).DataCompression = $CompressionType
                                    $obj.Rebuild()
                                    [pscustomobject]@{
                                        ComputerName                  = $server.ComputerName
                                        InstanceName                  = $server.ServiceName
                                        SqlInstance                   = $server.DomainInstanceName
                                        Database                      = $db.Name
                                        Schema                        = $obj.Schema
                                        TableName                     = $obj.Name
                                        IndexName                     = $null
                                        Partition                     = $p.PartitionNumber
                                        IndexID                       = 0
                                        IndexType                     = Switch ($obj.HasHeapIndex) { $false { "ClusteredIndex" } $true { "Heap" } }
                                        PercentScan                   = $null
                                        PercentUpdate                 = $null
                                        RowEstimatePercentOriginal    = $null
                                        PageEstimatePercentOriginal   = $null
                                        CompressionTypeRecommendation = $CompressionType.ToUpper()
                                        SizeCurrent                   = $null
                                        SizeRequested                 = $null
                                        PercentCompression            = $null
                                        AlreadyProcessed              = "True"
                                    }
                                }

                                foreach ($index in $($obj.Indexes | Where-Object { !$_.IsMemoryOptimized -and $_.IndexType -notmatch 'Columnstore' })) {
                                    if ($MaxRunTime -ne 0 -and ($(Get-Date) - $starttime).TotalMinutes -ge $MaxRunTime) {
                                        Write-Message -Level Verbose -Message "Reached max run time of $MaxRunTime"
                                        break
                                    }
                                    foreach ($p in $($index.PhysicalPartitions | Where-Object { $_.DataCompression -ne $CompressionType })) {
                                        Write-Message -Level Verbose -Message "Compressing $($Index.IndexType) $($Index.Name) Partition $($p.PartitionNumber)"

                                        ## There is a bug in SMO where setting compression to None at the index level doesn't work
                                        ## Once this UserVoice item is fixed the workaround can be removed
                                        ## https://feedback.azure.com/forums/908035-sql-server/suggestions/34080112-data-compression-smo-bug
                                        if ($CompressionType -eq "None") {
                                            $query = "ALTER INDEX [$($index.Name)] ON $($index.Parent) REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = $CompressionType)"
                                            $Server.Query($query, $db.Name)
                                        } else {
                                            $($Index.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $P.PartitionNumber }).DataCompression = $CompressionType
                                            $index.Rebuild()
                                        }

                                        [pscustomobject]@{
                                            ComputerName                  = $server.ComputerName
                                            InstanceName                  = $server.ServiceName
                                            SqlInstance                   = $server.DomainInstanceName
                                            Database                      = $db.Name
                                            Schema                        = $obj.Schema
                                            TableName                     = $obj.Name
                                            IndexName                     = $index.Name
                                            Partition                     = $p.PartitionNumber
                                            IndexID                       = $index.Id
                                            IndexType                     = $index.IndexType
                                            PercentScan                   = $null
                                            PercentUpdate                 = $null
                                            RowEstimatePercentOriginal    = $null
                                            PageEstimatePercentOriginal   = $null
                                            CompressionTypeRecommendation = $CompressionType.ToUpper()
                                            SizeCurrent                   = $null
                                            SizeRequested                 = $null
                                            PercentCompression            = $null
                                            AlreadyProcessed              = "True"
                                        }
                                    }
                                }
                            }
                            foreach ($index in $($server.Databases[$($db.name)].Views | Where-Object { $_.Indexes }).Indexes) {
                                foreach ($p in $($index.PhysicalPartitions | Where-Object { $_.DataCompression -ne $CompressionType })) {
                                    Write-Message -Level Verbose -Message "Compressing $($index.IndexType) $($index.Name) Partition $($p.PartitionNumber)"

                                    ## There is a bug in SMO where setting compression to None at the index level doesn't work
                                    ## Once this UserVoice item is fixed the workaround can be removed
                                    ## https://feedback.azure.com/forums/908035-sql-server/suggestions/34080112-data-compression-smo-bug
                                    if ($CompressionType -eq "None") {
                                        $query = "ALTER INDEX [$($index.Name)] ON $($index.Parent) REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = $CompressionType)"
                                        $query
                                        $Server.Query($query, $db.Name)
                                    } else {
                                        $($index.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $P.PartitionNumber }).DataCompression = $CompressionType
                                        $index.Rebuild()
                                    }

                                    [pscustomobject]@{
                                        ComputerName                  = $server.ComputerName
                                        InstanceName                  = $server.ServiceName
                                        SqlInstance                   = $server.DomainInstanceName
                                        Database                      = $db.Name
                                        Schema                        = $obj.Schema
                                        TableName                     = $obj.Name
                                        IndexName                     = $index.Name
                                        Partition                     = $p.PartitionNumber
                                        IndexID                       = $index.Id
                                        IndexType                     = $index.IndexType
                                        PercentScan                   = $null
                                        PercentUpdate                 = $null
                                        RowEstimatePercentOriginal    = $null
                                        PageEstimatePercentOriginal   = $null
                                        CompressionTypeRecommendation = $CompressionType.ToUpper()
                                        SizeCurrent                   = $null
                                        SizeRequested                 = $null
                                        PercentCompression            = $null
                                        AlreadyProcessed              = "True"
                                    }
                                }
                            }
                        }
                    }
                } catch {
                    Stop-Function -Message "Compression failed for $instance - $db" -Target $db -ErrorRecord $_ -Continue
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUXzdMeRhvlQ+1xmuCoX2MhFoc
# kd+gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFN6VciFFJtUUi00TCcs6G/yzVqV1MA0GCSqGSIb3DQEBAQUABIIBAC53JmbG
# etsW7hIUFBCwrT8PxJ7i70ql76v74xIzMbyclwtpmZLfoETYAPb47k0aJeL8t0Yn
# kb7rTRVxd0R3LCV6PrcULV6w5rS66+UqUozR9VTN77fR7Mnuk+u4+dQAVdaXFjTy
# dD9U0DdWC4vYXhcbbNMPC04F9glT1HydxDUSxFpEe4KC8ZHd2cy8i+dKDOWkeKYr
# c3rr786XpSTdAG+RikKT998imZY64SIWTOBhs0jBXP8vuDbQiKUCCRCRax1TJpvw
# fSZzlY9DHMTJMv9J2TRd/FogjH1STV7SDdrYOJcRNJtCVGcpYNaEKxorGXGQjhNV
# rfH7j+q3VhlpOxShggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAwN1owLwYJKoZIhvcNAQkEMSIEIADsZ2p3actAAiDxZjjJIfewzFXn
# G3p9Wznn0GdeON5yMA0GCSqGSIb3DQEBAQUABIIBAEqFJwVr6DVzpvlgz3VQc1IN
# OPIWJR4PsDUlVeZBmNGuin1MBYTn73N14QFv2TuJqS2ClvXUNfvFB+G06a9AgyE3
# lCxpPDyj304eGccMhcsiXdfgzMIKonsT3uvnn5c3Y2SKrtiQyxhIRKoRbRt9RQHa
# 1AM0WVq/xecGqeLTVV3A3H2HwX1wvZsWmEt4tjD9sJnrYAfyYx+I24ZtTY6h2p77
# xWUV7E243K+Hj1lpRTnM+ySbYTdAkkuFMJjEJD1eIyi1d/JX+zPEmTuBSgO1fn7H
# ryo+VHMGKgwdArZu+2Kxqe3IuHJve3drOXM9jDaTsw6HkfSFdnOy/HUKcHw2jwM=
# SIG # End signature block
