function Get-DbaSpConfigure {
    <#
    .SYNOPSIS
        Returns all server level system configuration (sys.configuration/sp_configure) information

    .DESCRIPTION
        This function returns server level system configuration (sys.configuration/sp_configure) information. The information is gathered through SMO Configuration.Properties.
        The data includes the default value for each configuration, for quick identification of values that may have been changed.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Return only specific configurations. Name can be either values from (sys.configuration/sp_configure) or from SMO object

    .PARAMETER ExcludeName
        Exclude specific configurations. Name can be either values from (sys.configuration/sp_configure) or from SMO object

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SpConfig, Configure, Configuration
        Author: Nic Cain, https://sirsql.net/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaSpConfigure

    .INPUTS
        A DbaInstanceParameter representing an array of SQL Server instances.

    .OUTPUTS
        Returns PSCustomObject with properties ServerName, ComputerName, InstanceName, SqlInstance, Name, DisplayName, Description, IsAdvanced, IsDynamic, MinValue, MaxValue, ConfiguredValue, RunningValue, DefaultValue, IsRunningDefaultValue

    .EXAMPLE
        PS C:\> Get-DbaSpConfigure -SqlInstance localhost

        Returns all system configuration information on the localhost.

    .EXAMPLE
        PS C:\> 'localhost','localhost\namedinstance' | Get-DbaSpConfigure

        Returns system configuration information on multiple instances piped into the function

    .EXAMPLE
        PS C:\> Get-DbaSpConfigure -SqlInstance sql2012 -Name 'max server memory (MB)'

        Returns only the system configuration for MaxServerMemory on sql2012.

    .EXAMPLE
        PS C:\> Get-DbaSpConfigure -SqlInstance sql2012 -ExcludeName 'max server memory (MB)', RemoteAccess | Out-GridView

        Returns system configuration information on sql2012 but excludes for max server memory (MB) and remote access. Values returned in grid view

    .EXAMPLE
        PS C:\> $cred = Get-Credential SqlCredential
        PS C:\> 'sql2012' | Get-DbaSpConfigure -SqlCredential $cred -Name RemoteAccess, 'max server memory (MB)' -ExcludeName 'remote access' | Out-GridView

        Returns system configuration information on sql2012 using SQL Server Authentication. Only MaxServerMemory is returned as RemoteAccess was also excluded.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Config", "ConfigName")]
        [string[]]$Name,
        [string[]]$ExcludeName,
        [switch]$EnableException
    )
    begin {
        $smoName = [pscustomobject]@{
            "access check cache bucket count"    = "AccessCheckCacheBucketCount"
            "access check cache quota"           = "AccessCheckCacheQuota"
            "Ad Hoc Distributed Queries"         = "AdHocDistributedQueriesEnabled"
            "ADR cleaner retry timeout (min)"    = "AdrCleanerRetryTimeout"
            "ADR Preallocation Factor"           = "AdrPreallcationFactor"
            "affinity I/O mask"                  = "AffinityIOMask"
            "affinity mask"                      = "AffinityMask"
            "affinity64 I/O mask"                = "Affinity64IOMask"
            "affinity64 mask"                    = "Affinity64Mask"
            "Agent XPs"                          = "AgentXPsEnabled"
            "allow filesystem enumeration"       = "AllowFilesystemEnumeration"
            "allow polybase export"              = "AllowPolybaseExport"
            "allow updates"                      = "AllowUpdates"
            "automatic soft-NUMA disabled"       = "AutomaticSoftnumaDisabled"
            "awe enabled"                        = "AweEnabled"
            "backup checksum default"            = "BackupChecksumDefault"
            "backup compression default"         = "DefaultBackupCompression"
            "blocked process threshold (s)"      = "BlockedProcessThreshold"
            "blocked process threshold"          = "BlockedProcessThreshold"
            "c2 audit mode"                      = "C2AuditMode"
            "clr enabled"                        = "IsSqlClrEnabled"
            "clr strict security"                = "ClrStrictSecurity"
            "column encryption enclave type"     = "ColumnEncryptionEnclaveType"
            "common criteria compliance enabled" = "CommonCriteriaComplianceEnabled"
            "contained database authentication"  = "ContainmentEnabled"
            "cost threshold for parallelism"     = "CostThresholdForParallelism"
            "cross db ownership chaining"        = "CrossDBOwnershipChaining"
            "cursor threshold"                   = "CursorThreshold"
            "Database Mail XPs"                  = "DatabaseMailEnabled"
            "default full-text language"         = "DefaultFullTextLanguage"
            "default language"                   = "DefaultLanguage"
            "default trace enabled"              = "DefaultTraceEnabled"
            "disallow results from triggers"     = "DisallowResultsFromTriggers"
            "EKM provider enabled"               = "ExtensibleKeyManagementEnabled"
            "external scripts enabled"           = "ExternalScriptsEnabled"
            "filestream access level"            = "FilestreamAccessLevel"
            "fill factor (%)"                    = "FillFactor"
            "ft crawl bandwidth (max)"           = "FullTextCrawlBandwidthMax"
            "ft crawl bandwidth (min)"           = "FullTextCrawlBandwidthMin"
            "ft notify bandwidth (max)"          = "FullTextNotifyBandwidthMax"
            "ft notify bandwidth (min)"          = "FullTextNotifyBandwidthMin"
            "hadoop connectivity"                = "HadoopConnectivity"
            "index create memory (KB)"           = "IndexCreateMemory"
            "in-doubt xact resolution"           = "InDoubtTransactionResolution"
            "lightweight pooling"                = "LightweightPooling"
            "locks"                              = "Locks"
            "max degree of parallelism"          = "MaxDegreeOfParallelism"
            "max full-text crawl range"          = "FullTextCrawlRangeMax"
            "max server memory (MB)"             = "MaxServerMemory"
            "max text repl size (B)"             = "ReplicationMaxTextSize"
            "max worker threads"                 = "MaxWorkerThreads"
            "media retention"                    = "MediaRetention"
            "min memory per query (KB)"          = "MinMemoryPerQuery"
            "min server memory (MB)"             = "MinServerMemory"
            "nested triggers"                    = "NestedTriggers"
            "network packet size (B)"            = "NetworkPacketSize"
            "Ole Automation Procedures"          = "OleAutomationProceduresEnabled"
            "open objects"                       = "OpenObjects"
            "optimize for ad hoc workloads"      = "OptimizeAdhocWorkloads"
            "PH timeout (s)"                     = "ProtocolHandlerTimeout"
            "polybase enabled"                   = "PolybaseEnabled"
            "polybase network encryption"        = "PolybaseNetworkEncryption"
            "precompute rank"                    = "PrecomputeRank"
            "priority boost"                     = "PriorityBoost"
            "query governor cost limit"          = "QueryGovernorCostLimit"
            "query wait (s)"                     = "QueryWait"
            "recovery interval (min)"            = "RecoveryInterval"
            "remote access"                      = "RemoteAccess"
            "remote admin connections"           = "RemoteDacConnectionsEnabled"
            "remote data archive"                = "RemoteDataArchiveEnabled"
            "remote login timeout (s)"           = "RemoteLoginTimeout"
            "remote proc trans"                  = "RemoteProcTrans"
            "remote query timeout (s)"           = "RemoteQueryTimeout"
            "Replication XPs"                    = "ReplicationXPsEnabled"
            "scan for startup procs"             = "ScanForStartupProcedures"
            "server trigger recursion"           = "ServerTriggerRecursionEnabled"
            "set working set size"               = "SetWorkingSetSize"
            "show advanced options"              = "ShowAdvancedOptions"
            "SMO and DMO XPs"                    = "SmoAndDmoXPsEnabled"
            "SQL Mail XPs"                       = "SqlMailXPsEnabled"
            "tempdb metadata memory-optimized"   = "TempdbMetadataMemoryOptimized"
            "transform noise words"              = "TransformNoiseWords"
            "two digit year cutoff"              = "TwoDigitYearCutoff"
            "user connections"                   = "UserConnections"
            "User Instance Timeout"              = "UserInstanceTimeout"
            "user instances enabled"             = "UserInstancesEnabled"
            "user options"                       = "UserOptions"
            "Web Assistant Procedures"           = "WebXPsEnabled"
            "xp_cmdshell"                        = "XPCmdShellEnabled"
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            #Get a list of the configuration Properties. This collection matches entries in sys.configurations
            try {
                $proplist = $server.Configuration.Properties
            } catch {
                Stop-Function -Message "Unable to gather configuration properties $instance" -Target $instance -ErrorRecord $_ -Continue
            }

            if ($Name) {
                $proplist = $proplist | Where-Object { ($_.DisplayName -in $Name -or ($smoName).$($_.DisplayName) -in $Name) }
            }

            if (Test-Bound "ExcludeName") {
                $proplist = $proplist | Where-Object { ($_.DisplayName -NotIn $ExcludeName -and ($smoName).$($_.DisplayName) -NotIn $ExcludeName) }
            }

            #Grab the default sp_configure property values from the external function
            $defaultConfigs = (Get-SqlDefaultSpConfigure -SqlVersion $server.VersionMajor).psobject.properties;

            #Iterate through the properties to get the configuration settings
            foreach ($prop in $proplist) {
                $defaultConfig = $defaultConfigs | Where-Object { $_.Name -eq $prop.DisplayName };

                if ($defaultConfig.Value -eq $prop.RunValue) { $isDefault = $true }
                else { $isDefault = $false }

                #Ignores properties that are not valid on this version of SQL
                if (!([string]::IsNullOrEmpty($prop.RunValue))) {

                    $DisplayName = $prop.DisplayName
                    [pscustomobject]@{
                        ServerName            = $server.Name
                        ComputerName          = $server.ComputerName
                        InstanceName          = $server.ServiceName
                        SqlInstance           = $server.DomainInstanceName
                        Name                  = ($smoName).$DisplayName
                        DisplayName           = $DisplayName
                        Description           = $prop.Description
                        IsAdvanced            = $prop.IsAdvanced
                        IsDynamic             = $prop.IsDynamic
                        MinValue              = $prop.Minimum
                        MaxValue              = $prop.Maximum
                        ConfiguredValue       = $prop.ConfigValue
                        RunningValue          = $prop.RunValue
                        DefaultValue          = $defaultConfig.Value
                        IsRunningDefaultValue = $isDefault
                        Parent                = $server
                        ConfigName            = ($smoName).$DisplayName
                        Property              = $prop
                    } | Select-DefaultView -ExcludeProperty ServerName, Parent, ConfigName, Property
                }
            }
        }
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU9PjjpfON9oUladyTp35FfSh7
# JqegghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFFTH36k7N+0suBAky6GTgBq/YNGZMA0GCSqGSIb3DQEBAQUABIIBAKuT9hJ+
# 6qailWJhKIp0dFugHfJWQuoHiR5Igjtp5IcRyK7ICxzxXDYfKZ3vCXrKvwdR5kDb
# pJWFIEXpX7R/yGE8eKmermBRhuVBoxc2/mhnj0ygNpCFBq+ZgHPKNwPOhVWJtX+a
# uG9vHTMggtYaNS8sM+h0c1BRD7D11h9NLnXrpEgHhHpGUXMYez7RdaROjXale8en
# MqMHlgeroj6MRoao9dx5KtwogdiGNaBpUNwja/ZmX9z9NvHQPI1S4suce/0bq7NM
# OZFSb/F8zqW7u7WLtz+ADX9wctq8SY3/B/AhjABPAoI1BzOCa1tA3FRILAzv97rV
# 0xS/7StS7SMiXM6hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUyOFowLwYJKoZIhvcNAQkEMSIEIC/pocw/MixHgg6thSPvw9FVykj+
# UDCQKwDvuLR34v/vMA0GCSqGSIb3DQEBAQUABIIBAHtXgH4pbUgBjfu2PzH5MXsA
# rAkFF35q4KhS63dRx8zPFm8mkmOz68tBfafUfCnsFRe9kXOWUxEEc4rG0dHdGIyg
# pHWGPlLf64RaqYnDzNwtPc/xJDk5VXu+Q8ivTDRPyNi2qNZor9s1zzxygqNx5+jp
# Ao6IIcVaOCp+CjBLMf9ViONhjLpCv/XEQUP8H7+P0G6zn/t6EJMiE8t4HACO7A9j
# YT1/6M/hTVJRoUHNaTLniWA6YElFOoFkv3UvwNusVjYQEVHiLTP/7TtOFj/w1kMC
# nJc76X36IqwKC3d1l4N//VBGAFfDAe1IrOHZxO2Mg2dMeT82IDGv0AnrU2yzsmk=
# SIG # End signature block
