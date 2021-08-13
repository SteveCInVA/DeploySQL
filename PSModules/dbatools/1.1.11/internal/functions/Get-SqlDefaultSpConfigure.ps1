function Get-SqlDefaultSpConfigure {
    <#
        .SYNOPSIS
        Internal function. Returns the default sp_configure options for a given version of SQL Server.

        .NOTES
        Server Configuration Options BOL (links subject to change):
        SQL Server 2019 - https://technet.microsoft.com/en-us/library/ms189631(v=sql.150).aspx
        SQL Server 2017 - https://technet.microsoft.com/en-us/library/ms189631(v=sql.140).aspx
        SQL Server 2016 - https://technet.microsoft.com/en-us/library/ms189631(v=sql.130).aspx
        SQL Server 2014 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.120).aspx
        SQL Server 2012 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.110).aspx
        SQL Server 2008 R2 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.105).aspx
        SQL Server 2008 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.100).aspx
        SQL Server 2005 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.90).aspx
        SQL Server 2000 - http://technet.microsoft.com/en-us/library/aa196706(v=sql.80).aspx (requires PDF download)

        .EXAMPLE
        Get-SqlDefaultSpConfigure -SqlVersion 11
        Returns a list of sp_configure (sys.configurations) items for SQL 2012.

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias("Version")]
        [object]$SqlVersion
    )

    switch ($SqlVersion) {

        #region SQL2000
        8 {
            [pscustomobject]@{
                "affinity mask"                  = 0
                "allow updates"                  = 0
                "awe enabled"                    = 0
                "c2 audit mode"                  = 0
                "cost threshold for parallelism" = 5
                "Cross DB Ownership Chaining"    = 0
                "cursor threshold"               = -1
                "default full-text language"     = 1033
                "default language"               = 0
                "fill factor (%)"                = 0
                "index create memory (KB)"       = 0
                "lightweight pooling"            = 0
                "locks"                          = 0
                "max degree of parallelism"      = 0
                "max server memory (MB)"         = 2147483647
                "max text repl size (B)"         = 65536
                "max worker threads"             = 255
                "media retention"                = 0
                "min memory per query (KB)"      = 1024
                "min server memory (MB)"         = 0
                "nested triggers"                = 1
                "network packet size (B)"        = 4096
                "open objects"                   = 0
                "priority boost"                 = 0
                "query governor cost limit"      = 0
                "query wait (s)"                 = -1
                "recovery interval (min)"        = 0
                "remote access"                  = 1
                "remote login timeout (s)"       = 20
                "remote proc trans"              = 0
                "remote query timeout (s)"       = 600
                "scan for startup procs"         = 0
                "set working set size"           = 0
                "show advanced options"          = 0
                "two digit year cutoff"          = 2049
                "user connections"               = 0
                "user options"                   = 0
            }
        }
        #endregion SQL2000

        #region SQL2005
        9 {
            [pscustomobject]@{
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow updates"                      = 0
                "awe enabled"                        = 0
                "blocked process threshold"          = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 8
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "PH timeout (s)"                     = 60
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote login timeout (s)"           = 20
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "SQL Mail XPs"                       = 0
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "Web Assistant Procedures"           = 0
                "xp_cmdshell"                        = 0
            }
        }

        #endregion SQL2005

        #region SQL2008&2008R2
        10 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow updates"                      = 0
                "awe enabled"                        = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote login timeout (s)"           = 20
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "SQL Mail XPs"                       = 0
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2008&2008R2

        #region SQL2012
        11 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow updates"                      = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2012

        #region SQL2014
        12 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow updates"                      = 0
                "backup checksum default"            = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2014

        #region SQL2016
        13 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow polybase export"              = 0
                "allow updates"                      = 0
                "automatic soft-NUMA disabled"       = 0
                "backup checksum default"            = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "external scripts enabled"           = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "hadoop connectivity"                = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "polybase network encryption"        = 1
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote data archive"                = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2016

        #region SQL2017
        14 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity mask"                      = 0
                "affinity64 I/O mask"                = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow polybase export"              = 0
                "allow updates"                      = 0
                "automatic soft-NUMA disabled"       = 0
                "backup checksum default"            = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "clr strict security"                = 1
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "external scripts enabled"           = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "hadoop connectivity"                = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "polybase network encryption"        = 1
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote data archive"                = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0

            }
        }
        #endregion SQL2017

        #region SQL2019
        15 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "ADR cleaner retry timeout (min)"    = 0
                "ADR Preallocation Factor"           = 0
                "affinity I/O mask"                  = 0
                "affinity mask"                      = 0
                "affinity64 I/O mask"                = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow filesystem enumeration"       = 1
                "allow polybase export"              = 0
                "allow updates"                      = 0
                "automatic soft-NUMA disabled"       = 0
                "backup checksum default"            = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "clr strict security"                = 0
                "column encryption enclave type"     = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = 0
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 0
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "external scripts enabled"           = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "hadoop connectivity"                = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "polybase enabled"                   = 0
                "polybase network encryption"        = 1
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote data archive"                = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "tempdb metadata memory-optimized"   = 0
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2019
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUR5hOuxk3ZvMN/Su68CjF+vj3
# nRCgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFHOfIlDscc3J90y73ZrFC+6XY8mRMA0GCSqGSIb3DQEBAQUABIIBAEgwSDnt
# ieP8sWvFMEbW9RqTr4MFXvK37q/3ulxDzkjx2WTFeR31vhrL/5J9C7swflvdnaVY
# F83Wg3KXYWo0ahWmiiZFLUlD96UoX3UkxmCNkPNojDjexipPgy20GldJxX3Jh3g5
# WSjL3PzX0XYEj2z6O3HGpecLsroDne1Exn6XVSj4MOxCQOs6p/eD5O90i/MvQocT
# qxJfURF95I2KMKef8/UX32qtdU+Nw5Jmr9vZpsak/skA6wen9h3rRbpBVNil/xP8
# ElGUoV4vGQLM90i2zezaMvJCigkyljMob7ZWcVfMj8NRcuykTEYl2iqtlfUm3T7P
# 9hdEHElNQixK5W6hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjYyMVowLwYJKoZIhvcNAQkEMSIEIMIWZ5rwnF6rSSBSIEuZYvb8ITnI
# 7oXLVKkkRmv+ihwLMA0GCSqGSIb3DQEBAQUABIIBAAvMhkeEt6XGYnHnUPv/NawZ
# NgmKFD28uV1Z9anTnfvpRRsUacJIac1g3A9WR0jJUA0RLWglMDqJ2jtyi754Q0Iu
# Hy+4x369dh0WzSLvvKoCR/Uz6NRXFcxsDAD6xoE7LTHx2+2h9/KweXJK2io9WVSw
# iI/PstYKwjiSrFxXWrCKaYTcDLQ+OaAwalOD/YqIXAm0SYv/NqBVedkGAjbv5M0z
# nmqbcGEzvbEjAnmtOS1uyrmGlVCugxjIiK1KWyUsF6oUF82A/8DnJZnt6O2lWdOk
# mSu/g4NZ+dzzYmDDDYcq7pjhBvFAxqSVp+PKBlX1OcN9Ob1V3xkUiY9YK2RLeBk=
# SIG # End signature block
