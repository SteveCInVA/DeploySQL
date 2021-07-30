function Invoke-DbaDiagnosticQuery {
    <#
    .SYNOPSIS
        Invoke-DbaDiagnosticQuery runs the scripts provided by Glenn Berry's DMV scripts on specified servers

    .DESCRIPTION
        This is the main function of the Sql Server Diagnostic Queries related functions in dbatools.
        The diagnostic queries are developed and maintained by Glenn Berry and they can be found here along with a lot of documentation:
        https://glennsqlperformance.com/resources/

        The most recent version of the diagnostic queries are included in the dbatools module.
        But it is possible to download a newer set or a specific version to an alternative location and parse and run those scripts.
        It will run all or a selection of those scripts on one or multiple servers and return the result as a PowerShell Object

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Can be either a string or SMO server

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Alternate path for the diagnostic scripts

    .PARAMETER Database
        The database(s) to process. If unspecified, all databases will be processed

    .PARAMETER ExcludeDatabase
        The database(s) to exclude

    .PARAMETER ExcludeQuery
        The Queries to exclude

    .PARAMETER UseSelectionHelper
        Provides a grid view with all the queries to choose from and will run the selection made by the user on the Sql Server instance specified.

    .PARAMETER QueryName
        Only run specific query

    .PARAMETER InstanceOnly
        Run only instance level queries

    .PARAMETER DatabaseSpecific
        Run only database level queries

    .PARAMETER ExcludeQueryTextColumn
        Use this switch to exclude the [Complete Query Text] column from relevant queries

    .PARAMETER ExcludePlanColumn
        Use this switch to exclude the [Query Plan] column from relevant queries

    .PARAMETER NoColumnParsing
        Does not parse the [Complete Query Text] and [Query Plan] columns and disregards the ExcludeQueryTextColumn and NoColumnParsing switches

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .PARAMETER OutputPath
        Directory to parsed diagnostics queries to. This will split them based on server, database name, and query.

    .PARAMETER ExportQueries
        Use this switch to export the diagnostic queries to sql files. Instead of running the queries, the server will be evaluated to find the appropriate queries to run based on SQL Version.
        These sql files will then be created in the OutputDirectory

    .NOTES
        Tags: Community, GlennBerry
        Author: Andre Kamman (@AndreKamman), http://andrekamman.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDiagnosticQuery

    .EXAMPLE
        PS C:\>Invoke-DbaDiagnosticQuery -SqlInstance sql2016

        Run the selection made by the user on the Sql Server instance specified.

    .EXAMPLE
        PS C:\>Invoke-DbaDiagnosticQuery -SqlInstance sql2016 -UseSelectionHelper | Export-DbaDiagnosticQuery -Path C:\temp\gboutput

        Provides a grid view with all the queries to choose from and will run the selection made by the user on the SQL Server instance specified.
        Then it will export the results to Export-DbaDiagnosticQuery.

    .EXAMPLE
        PS C:\> Invoke-DbaDiagnosticQuery -SqlInstance localhost -ExportQueries -OutputPath "C:\temp\DiagnosticQueries"

        Export All Queries to Disk

    .EXAMPLE
        PS C:\> Invoke-DbaDiagnosticQuery -SqlInstance localhost -DatabaseSpecific -ExportQueries -OutputPath "C:\temp\DiagnosticQueries"

        Export Database Specific Queries for all User Dbs

    .EXAMPLE
        PS C:\> Invoke-DbaDiagnosticQuery -SqlInstance localhost -DatabaseSpecific -DatabaseName 'tempdb' -ExportQueries -OutputPath "C:\temp\DiagnosticQueries"

        Export Database Specific Queries For One Target Database

    .EXAMPLE
        PS C:\> Invoke-DbaDiagnosticQuery -SqlInstance localhost -DatabaseSpecific -DatabaseName 'tempdb' -ExportQueries -OutputPath "C:\temp\DiagnosticQueries" -QueryName 'Database-scoped Configurations'

        Export Database Specific Queries For One Target Database and One Specific Query

    .EXAMPLE
        PS C:\> Invoke-DbaDiagnosticQuery -SqlInstance localhost -UseSelectionHelper

        Choose Queries To Export

    .EXAMPLE
        PS C:\> [PSObject[]]$results = Invoke-DbaDiagnosticQuery -SqlInstance localhost -WhatIf

        Parse the appropriate diagnostic queries by connecting to server, and instead of running them, return as [PSCustomObject[]] to work with further

    .EXAMPLE
        PS C:\> $results = Invoke-DbaDiagnosticQuery -SqlInstance Sql2017 -DatabaseSpecific -QueryName 'Database-scoped Configurations' -DatabaseName TestStuff

        Run diagnostic queries targeted at specific database, and only run database level queries against this database.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject[]])]
    param (
        [parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias('DatabaseName')]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [object[]]$ExcludeQuery,
        [Alias('Credential')]
        [PSCredential]$SqlCredential,
        [System.IO.FileInfo]$Path,
        [string[]]$QueryName,
        [switch]$UseSelectionHelper,
        [switch]$InstanceOnly,
        [switch]$DatabaseSpecific,
        [Switch]$ExcludeQueryTextColumn,
        [Switch]$ExcludePlanColumn,
        [Switch]$NoColumnParsing,
        [string]$OutputPath,
        [switch]$ExportQueries,
        [switch]
        [switch]$EnableException
    )
    begin {
        $ProgressId = Get-Random

        function Invoke-DiagnosticQuerySelectionHelper {
            [CmdletBinding()]
            param (
                [parameter(Mandatory)]
                $ParsedScript
            )

            $ParsedScript | Select-Object QueryNr, QueryName, DBSpecific, Description | Out-GridView -Title "Diagnostic Query Overview" -OutputMode Multiple | Sort-Object QueryNr | Select-Object -ExpandProperty QueryName

        }

        Write-Message -Level Verbose -Message "Interpreting DMV Script Collections"

        if (!$Path) {
            $Path = Join-Path -Path "$script:PSModuleRoot" -ChildPath "bin\diagnosticquery"
        }

        $scriptversions = @()
        $scriptfiles = Get-ChildItem -Path "$Path\SQLServerDiagnosticQueries_*.sql"

        if (!$scriptfiles) {
            Write-Message -Level Warning -Message "Diagnostic scripts not found in $Path. Using the ones within the module."

            $Path = Join-Path -Path $base -ChildPath "\bin\diagnosticquery"

            $scriptfiles = Get-ChildItem "$base\bin\diagnosticquery\SQLServerDiagnosticQueries_*.sql"
            if (!$scriptfiles) {
                Stop-Function -Message "Unable to download scripts, do you have an internet connection? $_" -ErrorRecord $_
                return
            }
        }

        [int[]]$filesort = $null

        foreach ($file in $scriptfiles) {
            $filesort += $file.BaseName.Split("_")[2]
        }

        $currentdate = $filesort | Sort-Object -Descending | Select-Object -First 1

        foreach ($file in $scriptfiles) {
            if ($file.BaseName.Split("_")[2] -eq $currentdate) {
                $parsedscript = Invoke-DbaDiagnosticQueryScriptParser -filename $file.fullname -ExcludeQueryTextColumn:$ExcludeQueryTextColumn -ExcludePlanColumn:$ExcludePlanColumn -NoColumnParsing:$NoColumnParsing

                $newscript = [pscustomobject]@{
                    Version = $file.Basename.Split("_")[1]
                    Script  = $parsedscript
                }
                $scriptversions += $newscript
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            $counter = 0
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Collecting diagnostic query data from server: $instance"

            if ($server.VersionMinor -eq 50) {
                $version = "2008R2"
            } else {
                $version = switch ($server.VersionMajor) {
                    9 { "2005" }
                    10 { "2008" }
                    11 { "2012" }
                    12 { "2014" }
                    13 { "2016" }
                    14 { "2017" }
                    15 { "2019" }
                }
            }

            if ($version -eq "2016" -and $server.VersionMinor -gt 5026 ) {
                $version = "2016SP2"
            }

            if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                $version = "AzureSQLDatabase"
            }

            if (!$instanceOnly) {
                if (-not $Database) {
                    $databases = (Get-DbaDatabase -SqlInstance $server -ExcludeSystem -ExcludeDatabase $ExcludeDatabase).Name
                } else {
                    $databases = (Get-DbaDatabase -SqlInstance $server -ExcludeSystem -Database $Database -ExcludeDatabase $ExcludeDatabase).Name
                }
            }

            $parsedscript = $scriptversions | Where-Object -Property Version -eq $version | Select-Object -ExpandProperty Script

            if ($null -eq $first) { $first = $true }
            if ($UseSelectionHelper -and $first) {
                $QueryName = Invoke-DiagnosticQuerySelectionHelper $parsedscript
                $first = $false
                if ($QueryName.Count -eq 0) {
                    Write-Message -Level Output -Message "No query selected through SelectionHelper, halting script execution"
                    return
                }
            }

            if ($QueryName.Count -eq 0) {
                $QueryName = $parsedscript | Select-Object -ExpandProperty QueryName
            }

            if ($ExcludeQuery) {
                $QueryName = Compare-Object -ReferenceObject $QueryName -DifferenceObject $ExcludeQuery | Where-Object SideIndicator -eq "<=" | Select-Object -ExpandProperty InputObject
            }

            #since some database level queries can take longer (such as fragmentation) calculate progress with database specific queries * count of databases to run against into context
            $CountOfDatabases = ($databases).Count

            if ($QueryName.Count -ne 0) {
                #if running all queries, then calculate total to run by instance queries count + (db specific count * databases to run each against)
                $countDBSpecific = @($parsedscript | Where-Object { $_.QueryName -in $QueryName -and $_.DBSpecific -eq $true }).Count
                $countInstanceSpecific = @($parsedscript | Where-Object { $_.QueryName -in $QueryName -and $_.DBSpecific -eq $false }).Count
            } else {
                #if narrowing queries to database specific, calculate total to process based on instance queries count + (db specific count * databases to run each against)
                $countDBSpecific = @($parsedscript | Where-Object DBSpecific).Count
                $countInstanceSpecific = @($parsedscript | Where-Object DBSpecific -eq $false).Count

            }
            if (!$instanceonly -and !$DatabaseSpecific -and !$QueryName) {
                $scriptcount = $countInstanceSpecific + ($countDBSpecific * $CountOfDatabases )
            } elseif ($instanceOnly) {
                $scriptcount = $countInstanceSpecific
            } elseif ($DatabaseSpecific) {
                $scriptcount = $countDBSpecific * $CountOfDatabases
            } elseif ($QueryName.Count -ne 0) {
                $scriptcount = $countInstanceSpecific + ($countDBSpecific * $CountOfDatabases )


            }

            foreach ($scriptpart in $parsedscript) {
                # ensure results are null with each part, otherwise duplicated information may be returned
                $result = $null
                if (($QueryName.Count -ne 0) -and ($QueryName -notcontains $scriptpart.QueryName)) { continue }
                if (!$scriptpart.DBSpecific -and !$DatabaseSpecific) {
                    if ($ExportQueries) {
                        $null = New-Item -Path $OutputPath -ItemType Directory -Force
                        $FileName = Remove-InvalidFileNameChars ('{0}.sql' -f $Scriptpart.QueryName)
                        $FullName = Join-Path $OutputPath $FileName
                        Write-Message -Level Verbose -Message  "Creating file: $FullName"
                        $scriptPart.Text | Out-File -FilePath $FullName -Encoding UTF8 -force
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($instance, $scriptpart.QueryName)) {

                        if (-not $EnableException) {
                            $Counter++
                            Write-Progress -Id $ProgressId -ParentId 0 -Activity "Collecting diagnostic query data from $instance" -Status "Processing $counter of $scriptcount" -CurrentOperation $scriptpart.QueryName -PercentComplete (($counter / $scriptcount) * 100)
                        }

                        try {
                            $result = $server.Query($scriptpart.Text)
                            Write-Message -Level Verbose -Message "Processed $($scriptpart.QueryName) on $instance"
                            if (-not $result) {
                                [pscustomobject]@{
                                    ComputerName     = $server.ComputerName
                                    InstanceName     = $server.ServiceName
                                    SqlInstance      = $server.DomainInstanceName
                                    Number           = $scriptpart.QueryNr
                                    Name             = $scriptpart.QueryName
                                    Description      = $scriptpart.Description
                                    DatabaseSpecific = $scriptpart.DBSpecific
                                    Database         = $null
                                    Notes            = "Empty Result for this Query"
                                    Result           = $null
                                }
                                Write-Message -Level Verbose -Message ("Empty result for Query {0} - {1} - {2}" -f $scriptpart.QueryNr, $scriptpart.QueryName, $scriptpart.Description)
                            }
                        } catch {
                            Write-Message -Level Verbose -Message ('Some error has occurred on Server: {0} - Script: {1}, result unavailable' -f $instance, $scriptpart.QueryName) -Target $instance -ErrorRecord $_
                        }
                        if ($result) {
                            [pscustomobject]@{
                                ComputerName     = $server.ComputerName
                                InstanceName     = $server.ServiceName
                                SqlInstance      = $server.DomainInstanceName
                                Number           = $scriptpart.QueryNr
                                Name             = $scriptpart.QueryName
                                Description      = $scriptpart.Description
                                DatabaseSpecific = $scriptpart.DBSpecific
                                Database         = $null
                                Notes            = $null
                                #Result           = Select-DefaultView -InputObject $result -Property *
                                #Not using Select-DefaultView because excluding the fields below doesn't seem to work
                                Result           = $result | Select-Object * -ExcludeProperty 'Item', 'RowError', 'RowState', 'Table', 'ItemArray', 'HasErrors'
                            }

                        }
                    } else {
                        # if running WhatIf, then return the queries that would be run as an object, not just whatif output

                        [pscustomobject]@{
                            ComputerName     = $server.ComputerName
                            InstanceName     = $server.ServiceName
                            SqlInstance      = $server.DomainInstanceName
                            Number           = $scriptpart.QueryNr
                            Name             = $scriptpart.QueryName
                            Description      = $scriptpart.Description
                            DatabaseSpecific = $scriptpart.DBSpecific
                            Database         = $null
                            Notes            = "WhatIf - Bypassed Execution"
                            Result           = $null
                        }
                    }

                } elseif ($scriptpart.DBSpecific -and !$instanceOnly) {

                    foreach ($currentdb in $databases) {
                        if ($ExportQueries) {
                            $null = New-Item -Path $OutputPath -ItemType Directory -Force
                            $FileName = Remove-InvalidFileNameChars ('{0}-{1}-{2}.sql' -f $server.DomainInstanceName, $currentDb, $Scriptpart.QueryName)
                            $FullName = Join-Path $OutputPath $FileName
                            Write-Message -Level Verbose -Message  "Creating file: $FullName"
                            $scriptPart.Text | Out-File -FilePath $FullName -encoding UTF8 -force
                            continue
                        }


                        if ($PSCmdlet.ShouldProcess(('{0} ({1})' -f $instance, $currentDb), $scriptpart.QueryName)) {

                            if (-not $EnableException) {
                                $Counter++
                                Write-Progress -Id $ProgressId -ParentId 0 -Activity "Collecting diagnostic query data from $($currentDb) on $instance" -Status ('Processing {0} of {1}' -f $counter, $scriptcount) -CurrentOperation $scriptpart.QueryName -PercentComplete (($Counter / $scriptcount) * 100)
                            }

                            Write-Message -Level Verbose -Message "Collecting diagnostic query data from $($currentDb) for $($scriptpart.QueryName) on $instance"
                            try {
                                $result = $server.Query($scriptpart.Text, $currentDb)
                                if (-not $result) {
                                    [pscustomobject]@{
                                        ComputerName     = $server.ComputerName
                                        InstanceName     = $server.ServiceName
                                        SqlInstance      = $server.DomainInstanceName
                                        Number           = $scriptpart.QueryNr
                                        Name             = $scriptpart.QueryName
                                        Description      = $scriptpart.Description
                                        DatabaseSpecific = $scriptpart.DBSpecific
                                        Database         = $currentdb
                                        Notes            = "Empty Result for this Query"
                                        Result           = $null
                                    }
                                    Write-Message -Level Verbose -Message ("Empty result for Query {0} - {1} - {2}" -f $scriptpart.QueryNr, $scriptpart.QueryName, $scriptpart.Description) -Target $scriptpart -ErrorRecord $_
                                }
                            } catch {
                                Write-Message -Level Verbose -Message ('Some error has occurred on Server: {0} - Script: {1} - Database: {2}, result will not be saved' -f $instance, $scriptpart.QueryName, $currentDb) -Target $currentdb -ErrorRecord $_
                            }

                            if ($result) {
                                [pscustomobject]@{
                                    ComputerName     = $server.ComputerName
                                    InstanceName     = $server.ServiceName
                                    SqlInstance      = $server.DomainInstanceName
                                    Number           = $scriptpart.QueryNr
                                    Name             = $scriptpart.QueryName
                                    Description      = $scriptpart.Description
                                    DatabaseSpecific = $scriptpart.DBSpecific
                                    Database         = $currentDb
                                    Notes            = $null
                                    #Result           = Select-DefaultView -InputObject $result -Property *
                                    #Not using Select-DefaultView because excluding the fields below doesn't seem to work
                                    Result           = $result | Select-Object * -ExcludeProperty 'Item', 'RowError', 'RowState', 'Table', 'ItemArray', 'HasErrors'
                                }
                            }
                        } else {
                            # if running WhatIf, then return the queries that would be run as an object, not just whatif output

                            [pscustomobject]@{
                                ComputerName     = $server.ComputerName
                                InstanceName     = $server.ServiceName
                                SqlInstance      = $server.DomainInstanceName
                                Number           = $scriptpart.QueryNr
                                Name             = $scriptpart.QueryName
                                Description      = $scriptpart.Description
                                DatabaseSpecific = $scriptpart.DBSpecific
                                Database         = $null
                                Notes            = "WhatIf - Bypassed Execution"
                                Result           = $null
                            }
                        }
                    }
                }
            }
        }
    }
    end {
        Write-Progress -Id $ProgressId -Activity 'Invoke-DbaDiagnosticQuery' -Completed
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUPQQi1pD3dxYsVKffj/4GcvE9
# yF6gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFFVew/KbsS8nOhJxoW3P7rTx6thFMA0GCSqGSIb3DQEBAQUABIIBAH9E1mGF
# pnSV2pdzUj4gUqhC0sGBM06SogRimFlj4SGp/u6lWi/+xhuM78qSuXAKBz2bu/fU
# bWFeRd0QmdowDuaJCcfVsgArg0WIseVQEDXoiK/f8gicc2yrFT/tWDS3/T92AdjY
# 5Ew81Jvzoo+uzjLjxACkonJs+w5DyFG/x/IerseS9JHll4/cbuj6FtFTfnzXjocN
# PTqqd1+vbu8jUDY5mTEBMbMnzn7lDX2awsv12AgtCSnSGxfkZ7hvfaHESj3dZ1h/
# yplxuWzEOCl/uaTxd039jOnRbXRkpLCS2+d2RhXhe1PKYmON0QJAQZwEF8NmH70Z
# 2mGCmtdj0hd4CBChggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk1MVowLwYJKoZIhvcNAQkEMSIEIPYZgaIn7gzKUDSiPhqWahpau+1h
# 4gVDTYhxz7mBsqufMA0GCSqGSIb3DQEBAQUABIIBACk8zxFDjmNKZdZDfwalh1b/
# cd69clBX6YRkrJbbNOONOnykqkUlEM5+nqzk5ehFq0A+BIX5WlTAc2EqjFlQvR/c
# 4dcJxnWqZdIxt3wO+p9KQrVFeydYh4l6CiV4pEIDPKSn9rGblKUoDkwe95muQH02
# Nxfam3gSrdhs79AUR6+QEHDo9DQH0lJyE+k0+avOV/bxf60HtdilVe16pmJgogBF
# gGCAw9ypOS7L2zYBf6hx0hYOLkLxk03wW37hrCWPqpiHwpTAl+YJFhN6VUyKCbtH
# VDXi9CoyTjqLAybd4ofI0/eZA1wJZyAV1PRVcP0o9BhtkiL5l/c2wlR0YaD9zlc=
# SIG # End signature block
