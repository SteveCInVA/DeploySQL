function Find-DbaSimilarTable {
    <#
    .SYNOPSIS
        Returns all tables/views that are similar in structure by comparing the column names of matching and matched tables/views

    .DESCRIPTION
        This function can either run against specific databases or all databases searching all/specific tables and views including in system databases.
        Typically one would use this to find for example archive version(s) of a table whose structures are similar.
        This can also be used to find tables/views that are very similar to a given table/view structure to see where a table/view might be used.

        More information can be found here: https://sqljana.wordpress.com/2017/03/31/sql-server-find-tables-with-similar-table-structure/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER SchemaName
        If you are looking in a specific schema whose table structures is to be used as reference structure, provide the name of the schema.
        If no schema is provided, looks at all schemas

    .PARAMETER TableName
        If you are looking in a specific table whose structure is to be used as reference structure, provide the name of the table.
        If no table is provided, looks at all tables
        If the table name exists in multiple schemas, all of them would qualify

    .PARAMETER ExcludeViews
        By default, views are included. You can exclude them by setting this switch to $false
        This excludes views in both matching and matched list

    .PARAMETER IncludeSystemDatabases
        By default system databases are ignored but you can include them within the search using this parameter

    .PARAMETER MatchPercentThreshold
        The minimum percentage of column names that should match between the matching and matched objects.
        Entries with no matches are eliminated

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Table
        Author: Jana Sattainathan (@SQLJana), http://sqljana.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaSimilarTable

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01

        Searches all user database tables and views for each, returns all tables or views with their matching tables/views and match percent

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01 -Database AdventureWorks

        Searches AdventureWorks database and lists tables/views and their corresponding matching tables/views with match percent

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01 -Database AdventureWorks -SchemaName HumanResource

        Searches AdventureWorks database and lists tables/views in the HumanResource schema with their corresponding matching tables/views with match percent

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01 -Database AdventureWorks -SchemaName HumanResource -Table Employee

        Searches AdventureWorks database and lists tables/views in the HumanResource schema and table Employee with its corresponding matching tables/views with match percent

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01 -Database AdventureWorks -MatchPercentThreshold 60

        Searches AdventureWorks database and lists all tables/views with its corresponding matching tables/views with match percent greater than or equal to 60

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [string]$SchemaName,
        [string]$TableName,
        [switch]$ExcludeViews,
        [switch]$IncludeSystemDatabases,
        [int]$MatchPercentThreshold,
        [switch]$EnableException
    )

    begin {
        $everyServerVwCount = 0

        $sqlSelect = "WITH ColCountsByTable
                AS
                (
                      SELECT
                            c.TABLE_CATALOG,
                            c.TABLE_SCHEMA,
                            c.TABLE_NAME,
                            COUNT(1) AS Column_Count
                      FROM INFORMATION_SCHEMA.COLUMNS c
                      GROUP BY
                            c.TABLE_CATALOG,
                            c.TABLE_SCHEMA,
                            c.TABLE_NAME
                )
                SELECT
                      100 * COUNT(c2.COLUMN_NAME) /*Matching_Column_Count*/ / MIN(ColCountsByTable.Column_Count) /*Column_Count*/ AS MatchPercent,
                      DENSE_RANK() OVER(ORDER BY c.TABLE_CATALOG, c.TABLE_SCHEMA, c.TABLE_NAME) TableNameRankInDB,
                      c.TABLE_CATALOG AS DatabaseName,
                      c.TABLE_SCHEMA AS SchemaName,
                      c.TABLE_NAME AS TableName,
                      t.TABLE_TYPE AS TableType,
                      MIN(ColCountsByTable.Column_Count) AS ColumnCount,
                      c2.TABLE_CATALOG AS MatchingDatabaseName,
                      c2.TABLE_SCHEMA AS MatchingSchemaName,
                      c2.TABLE_NAME AS MatchingTableName,
                      t2.TABLE_TYPE AS MatchingTableType,
                      COUNT(c2.COLUMN_NAME) AS MatchingColumnCount
                FROM INFORMATION_SCHEMA.TABLES t
                      INNER JOIN INFORMATION_SCHEMA.COLUMNS c
                            ON t.TABLE_CATALOG = c.TABLE_CATALOG
                                  AND t.TABLE_SCHEMA = c.TABLE_SCHEMA
                                  AND t.TABLE_NAME = c.TABLE_NAME
                      INNER JOIN ColCountsByTable
                            ON t.TABLE_CATALOG = ColCountsByTable.TABLE_CATALOG
                                  AND t.TABLE_SCHEMA = ColCountsByTable.TABLE_SCHEMA
                                  AND t.TABLE_NAME = ColCountsByTable.TABLE_NAME
                      LEFT OUTER JOIN INFORMATION_SCHEMA.COLUMNS c2
                            ON t.TABLE_NAME != c2.TABLE_NAME
                                  AND c.COLUMN_NAME = c2.COLUMN_NAME
                      LEFT JOIN INFORMATION_SCHEMA.TABLES t2
                            ON c2.TABLE_NAME = t2.TABLE_NAME"

        $sqlWhere = "
                WHERE "

        $sqlGroupBy = "
                GROUP BY
                      c.TABLE_CATALOG,
                      c.TABLE_SCHEMA,
                      c.TABLE_NAME,
                      t.TABLE_TYPE,
                      c2.TABLE_CATALOG,
                      c2.TABLE_SCHEMA,
                      c2.TABLE_NAME,
                      t2.TABLE_TYPE "

        $sqlHaving = "
                HAVING
                    /*Match_Percent should be greater than 0 at minimum!*/
                    "

        $sqlOrderBy = "
                ORDER BY
                      MatchPercent DESC"


        $sql = ''
        $wherearray = @()

        if ($ExcludeViews) {
            $wherearray += " (t.TABLE_TYPE <> 'VIEW' AND t2.TABLE_TYPE <> 'VIEW') "
        }

        if ($SchemaName) {
            $wherearray += (" (c.TABLE_SCHEMA = '{0}') " -f $SchemaName.Replace("'", "''")) #Replace single quotes with two single quotes!
        }

        if ($TableName) {
            $wherearray += (" (c.TABLE_NAME = '{0}') " -f $TableName.Replace("'", "''")) #Replace single quotes with two single quotes!

        }

        if ($wherearray.length -gt 0) {
            $sqlWhere = "$sqlWhere " + ($wherearray -join " AND ")
        } else {
            $sqlWhere = ""
        }


        $matchThreshold = 0
        if ($MatchPercentThreshold) {
            $matchThreshold = $MatchPercentThreshold
        } else {
            $matchThreshold = 0
        }

        $sqlHaving += (" (100 * COUNT(c2.COLUMN_NAME) / MIN(ColCountsByTable.Column_Count) >= {0}) " -f $matchThreshold)



        $sql = "$sqlSelect $sqlWhere $sqlGroupBy $sqlHaving $sqlOrderBy"

        Write-Message -Level Debug -Message $sql

    }

    process {
        foreach ($Instance in $SqlInstance) {

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }


            #Use IsAccessible instead of Status -eq 'normal' because databases that are on readable secondaries for AG or mirroring replicas will cause errors to be thrown
            if ($IncludeSystemDatabases) {
                $dbs = $server.Databases | Where-Object { $_.IsAccessible -eq $true }
            } else {
                $dbs = $server.Databases | Where-Object { $_.IsAccessible -eq $true -and $_.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $server.Databases | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }


            $totalCount = 0
            $dbCount = $dbs.count
            foreach ($db in $dbs) {

                Write-Message -Level Verbose -Message "Searching on database $db"
                $rows = $db.Query($sql)

                foreach ($row in $rows) {
                    [PSCustomObject]@{
                        ComputerName              = $server.ComputerName
                        InstanceName              = $server.ServiceName
                        SqlInstance               = $server.DomainInstanceName
                        Table                     = "$($row.DatabaseName).$($row.SchemaName).$($row.TableName)"
                        MatchingTable             = "$($row.MatchingDatabaseName).$($row.MatchingSchemaName).$($row.MatchingTableName)"
                        MatchPercent              = $row.MatchPercent
                        OriginalDatabaseName      = $row.DatabaseName
                        OriginalSchemaName        = $row.SchemaName
                        OriginalTableName         = $row.TableName
                        OriginalTableNameRankInDB = $row.TableNameRankInDB
                        OriginalTableType         = $row.TableType
                        OriginalColumnCount       = $row.ColumnCount
                        MatchingDatabaseName      = $row.MatchingDatabaseName
                        MatchingSchemaName        = $row.MatchingSchemaName
                        MatchingTableName         = $row.MatchingTableName
                        MatchingTableType         = $row.MatchingTableType
                        MatchingColumnCount       = $row.MatchingColumnCount
                    }
                }

                $vwCount = $vwCount + $rows.Count
                $totalCount = $totalCount + $rows.Count
                $everyServerVwCount = $everyServerVwCount + $rows.Count

                Write-Message -Level Verbose -Message "Found $vwCount tables/views in $db"
            }

            Write-Message -Level Verbose -Message "Found $totalCount total tables/views in $dbCount databases"
        }
    }
    end {
        Write-Message -Level Verbose -Message "Found $everyServerVwCount total tables/views"
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUPrMGA7+uP1DmLmjiE5Ouizhi
# vwagghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFIWkr8sF+bCmzQbqlbnTFz8BgBeUMA0GCSqGSIb3DQEBAQUABIIBAIp65hcH
# WF9rhpW2rJjmE85O5dqsva4BUQWqwr33Nmd/W6b8akpWYX0R/8OCp2PiQxYtuyMb
# QH0tdY247RUkMxW1mA1fNChMUSlPPLLy1UQl7YRzYcLXOFa5E52bZcc6+OOsjVzo
# Ive8UH1t/jhhm+MguMaAieJlqXXuEz+N1viHn1fN2KmTA5eT0E6IkwVpvvkqwObN
# cqgmp6cgTJYv43pFS8Q5lJhUU+r8xOyLcPGJsHe1QuUTxgcGqY5yAvLs1uwzGe0e
# WR0/kMpvMC6sVRXTwwJ4ZX+s6uErJXHq67Br/nxBWKvV1P5J4acNLbWJG2ZlSF2c
# wpFLpguMRr6oYuOhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUwNlowLwYJKoZIhvcNAQkEMSIEIOFt5pyLErY2+wh5idYJH93bnoEO
# bDv64FatogKoF4SDMA0GCSqGSIb3DQEBAQUABIIBAHnBqlOgQfaA0kBTL8MzomLp
# jDqaMHWv2GtUUjE2FL9yXznIRu9AAatdYzLRbntqNVEaqd0beFPy0NiA5ygZ5iJR
# W4J9z4c4o9LKeEWdapnlr6LvLEifBfhrWK9Kwp83jGqIlVUMDqiMrLwZZ3fqzs4a
# vTPPCJt1YC25mi4scSwLeMrbGgv07poz4oDjMTQqGcGylsDCDchKk9Jv77psixk3
# GKMc9lIi38NgemX0GsvH2I6vyAkqYK3DYYNt+3Gc52nns88KSSBgyiDK9Gz7pmCT
# TC9tPnylwcUYDsVX+rYGZtlNPVAn8ol5HxMxOZY5JYuhGsryJkbpAagUexMQhI0=
# SIG # End signature block
