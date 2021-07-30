function Find-DbaDbDuplicateIndex {
    <#
    .SYNOPSIS
        Find duplicate and overlapping indexes.

    .DESCRIPTION
        This command will help you to find duplicate and overlapping indexes on a database or a list of databases.

        On SQL Server 2008 and higher, the IsFiltered property will also be checked

        Only supports CLUSTERED and NONCLUSTERED indexes.

        Output:
        TableName
        IndexName
        KeyColumns
        IncludedColumns
        IndexSizeMB
        IndexType
        CompressionDescription (When 2008+)
        [RowCount]
        IsDisabled
        IsFiltered (When 2008+)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER IncludeOverlapping
        If this switch is enabled, indexes which are partially duplicated will be returned.

        Example: If the first key column is the same between two indexes, but one has included columns and the other not, this will be shown.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Index
        Author: Claudio Silva (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaDbDuplicateIndex

    .EXAMPLE
        PS C:\> Find-DbaDbDuplicateIndex -SqlInstance sql2005

        Returns duplicate indexes found on sql2005

    .EXAMPLE
        PS C:\> Find-DbaDbDuplicateIndex -SqlInstance sql2017 -SqlCredential sqladmin

        Finds exact duplicate indexes on all user databases present on sql2017, using SQL authentication.

    .EXAMPLE
        PS C:\> Find-DbaDbDuplicateIndex -SqlInstance sql2017 -Database db1, db2

        Finds exact duplicate indexes on the db1 and db2 databases.

    .EXAMPLE
        PS C:\> Find-DbaDbDuplicateIndex -SqlInstance sql2017 -IncludeOverlapping

        Finds both duplicate and overlapping indexes on all user databases.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [switch]$IncludeOverlapping,
        [switch]$EnableException
    )

    begin {
        $exactDuplicateQuery2005 = "
            WITH CTE_IndexCols
            AS (
                SELECT i.[object_id]
                    ,i.index_id
                    ,OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName
                    ,OBJECT_NAME(i.[object_id]) AS TableName
                    ,NAME AS IndexName
                    ,ISNULL(STUFF((
                                SELECT ', ' + col.NAME + ' ' + CASE
                                        WHEN idxCol.is_descending_key = 1
                                            THEN 'DESC'
                                        ELSE 'ASC'
                                        END -- Include column order (ASC / DESC)
                                FROM sys.index_columns idxCol
                                INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
                                    AND idxCol.column_id = col.column_id
                                WHERE i.[object_id] = idxCol.[object_id]
                                    AND i.index_id = idxCol.index_id
                                    AND idxCol.is_included_column = 0
                                ORDER BY idxCol.key_ordinal
                                FOR XML PATH('')
                                ), 1, 2, ''), '') AS KeyColumns
                    ,ISNULL(STUFF((
                                SELECT ', ' + col.NAME + ' ' + CASE
                                        WHEN idxCol.is_descending_key = 1
                                            THEN 'DESC'
                                        ELSE 'ASC'
                                        END -- Include column order (ASC / DESC)
                                FROM sys.index_columns idxCol
                                INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
                                    AND idxCol.column_id = col.column_id
                                WHERE i.[object_id] = idxCol.[object_id]
                                    AND i.index_id = idxCol.index_id
                                    AND idxCol.is_included_column = 1
                                ORDER BY idxCol.key_ordinal
                                FOR XML PATH('')
                                ), 1, 2, ''), '') AS IncludedColumns
                    ,i.[type_desc] AS IndexType
                    ,i.is_disabled AS IsDisabled
                FROM sys.indexes AS i
                WHERE i.index_id > 0 -- Exclude HEAPS
                    AND i.[type_desc] IN (
                        'CLUSTERED'
                        ,'NONCLUSTERED'
                        )
                    AND OBJECT_SCHEMA_NAME(i.[object_id]) <> 'sys'
                )
                ,CTE_IndexSpace
            AS (
                SELECT s.[object_id]
                    ,s.index_id
                    ,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
                    ,SUM(p.[rows]) AS [RowCount]
                FROM sys.dm_db_partition_stats AS s
                INNER JOIN sys.partitions p WITH (NOLOCK) ON s.[partition_id] = p.[partition_id]
                    AND s.[object_id] = p.[object_id]
                    AND s.index_id = p.index_id
                WHERE s.index_id > 0 -- Exclude HEAPS
                    AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
                GROUP BY s.[object_id]
                    ,s.index_id
                )
            SELECT DB_NAME() AS DatabaseName
                ,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
                ,CI1.IndexName
                ,CI1.KeyColumns
                ,CI1.IncludedColumns
                ,CI1.IndexType
                ,COALESCE(CSPC.IndexSizeMB,0) AS 'IndexSizeMB'
                ,COALESCE(CSPC.[RowCount],0) AS 'RowCount'
                ,CI1.IsDisabled
            FROM CTE_IndexCols AS CI1
            LEFT JOIN CTE_IndexSpace AS CSPC ON CI1.[object_id] = CSPC.[object_id]
                AND CI1.index_id = CSPC.index_id
            WHERE EXISTS (
                    SELECT 1
                    FROM CTE_IndexCols CI2
                    WHERE CI1.SchemaName = CI2.SchemaName
                        AND CI1.TableName = CI2.TableName
                        AND CI1.KeyColumns = CI2.KeyColumns
                        AND CI1.IncludedColumns = CI2.IncludedColumns
                        AND CI1.IndexName <> CI2.IndexName
                    )"

        $overlappingQuery2005 = "
            WITH CTE_IndexCols
            AS (
                SELECT i.[object_id]
                    ,i.index_id
                    ,OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName
                    ,OBJECT_NAME(i.[object_id]) AS TableName
                    ,NAME AS IndexName
                    ,ISNULL(STUFF((
                                SELECT ', ' + col.NAME + ' ' + CASE
                                        WHEN idxCol.is_descending_key = 1
                                            THEN 'DESC'
                                        ELSE 'ASC'
                                        END -- Include column order (ASC / DESC)
                                FROM sys.index_columns idxCol
                                INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
                                    AND idxCol.column_id = col.column_id
                                WHERE i.[object_id] = idxCol.[object_id]
                                    AND i.index_id = idxCol.index_id
                                    AND idxCol.is_included_column = 0
                                ORDER BY idxCol.key_ordinal
                                FOR XML PATH('')
                                ), 1, 2, ''), '') AS KeyColumns
                    ,ISNULL(STUFF((
                                SELECT ', ' + col.NAME + ' ' + CASE
                                        WHEN idxCol.is_descending_key = 1
                                            THEN 'DESC'
                                        ELSE 'ASC'
                                        END -- Include column order (ASC / DESC)
                                FROM sys.index_columns idxCol
                                INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
                                    AND idxCol.column_id = col.column_id
                                WHERE i.[object_id] = idxCol.[object_id]
                                    AND i.index_id = idxCol.index_id
                                    AND idxCol.is_included_column = 1
                                ORDER BY idxCol.key_ordinal
                                FOR XML PATH('')
                                ), 1, 2, ''), '') AS IncludedColumns
                    ,i.[type_desc] AS IndexType
                    ,i.is_disabled AS IsDisabled
                FROM sys.indexes AS i
                WHERE i.index_id > 0 -- Exclude HEAPS
                    AND i.[type_desc] IN (
                        'CLUSTERED'
                        ,'NONCLUSTERED'
                        )
                    AND OBJECT_SCHEMA_NAME(i.[object_id]) <> 'sys'
                )
                ,CTE_IndexSpace
            AS (
                SELECT s.[object_id]
                    ,s.index_id
                    ,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
                    ,SUM(p.[rows]) AS [RowCount]
                FROM sys.dm_db_partition_stats AS s
                INNER JOIN sys.partitions p WITH (NOLOCK) ON s.[partition_id] = p.[partition_id]
                    AND s.[object_id] = p.[object_id]
                    AND s.index_id = p.index_id
                WHERE s.index_id > 0 -- Exclude HEAPS
                    AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
                GROUP BY s.[object_id]
                    ,s.index_id
                )
            SELECT DB_NAME() AS DatabaseName
                ,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
                ,CI1.IndexName
                ,CI1.KeyColumns
                ,CI1.IncludedColumns
                ,CI1.IndexType
                ,COALESCE(CSPC.IndexSizeMB,0) AS 'IndexSizeMB'
                ,COALESCE(CSPC.[RowCount],0) AS 'RowCount'
                ,CI1.IsDisabled
            FROM CTE_IndexCols AS CI1
            LEFT JOIN CTE_IndexSpace AS CSPC ON CI1.[object_id] = CSPC.[object_id]
                AND CI1.index_id = CSPC.index_id
            WHERE EXISTS (
                    SELECT 1
                    FROM CTE_IndexCols CI2
                    WHERE CI1.SchemaName = CI2.SchemaName
                        AND CI1.TableName = CI2.TableName
                        AND (
                            (
                                CI1.KeyColumns LIKE CI2.KeyColumns + '%'
                                AND SUBSTRING(CI1.KeyColumns, LEN(CI2.KeyColumns) + 1, 1) = ' '
                                )
                            OR (
                                CI2.KeyColumns LIKE CI1.KeyColumns + '%'
                                AND SUBSTRING(CI2.KeyColumns, LEN(CI1.KeyColumns) + 1, 1) = ' '
                                )
                            )
                        AND CI1.IndexName <> CI2.IndexName
                    )"

        # Support Compression 2008+
        $exactDuplicateQuery = "
            WITH CTE_IndexCols
            AS (
                SELECT i.[object_id]
                    ,i.index_id
                    ,OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName
                    ,OBJECT_NAME(i.[object_id]) AS TableName
                    ,NAME AS IndexName
                    ,ISNULL(STUFF((
                                SELECT ', ' + col.NAME + ' ' + CASE
                                        WHEN idxCol.is_descending_key = 1
                                            THEN 'DESC'
                                        ELSE 'ASC'
                                        END -- Include column order (ASC / DESC)
                                FROM sys.index_columns idxCol
                                INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
                                    AND idxCol.column_id = col.column_id
                                WHERE i.[object_id] = idxCol.[object_id]
                                    AND i.index_id = idxCol.index_id
                                    AND idxCol.is_included_column = 0
                                ORDER BY idxCol.key_ordinal
                                FOR XML PATH('')
                                ), 1, 2, ''), '') AS KeyColumns
                    ,ISNULL(STUFF((
                                SELECT ', ' + col.NAME + ' ' + CASE
                                        WHEN idxCol.is_descending_key = 1
                                            THEN 'DESC'
                                        ELSE 'ASC'
                                        END -- Include column order (ASC / DESC)
                                FROM sys.index_columns idxCol
                                INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
                                    AND idxCol.column_id = col.column_id
                                WHERE i.[object_id] = idxCol.[object_id]
                                    AND i.index_id = idxCol.index_id
                                    AND idxCol.is_included_column = 1
                                ORDER BY idxCol.key_ordinal
                                FOR XML PATH('')
                                ), 1, 2, ''), '') AS IncludedColumns
                    ,i.[type_desc] AS IndexType
                    ,i.is_disabled AS IsDisabled
                    ,i.has_filter AS IsFiltered
                FROM sys.indexes AS i
                WHERE i.index_id > 0 -- Exclude HEAPS
                    AND i.[type_desc] IN (
                        'CLUSTERED'
                        ,'NONCLUSTERED'
                        )
                    AND OBJECT_SCHEMA_NAME(i.[object_id]) <> 'sys'
                )
                ,CTE_IndexSpace
            AS (
                SELECT s.[object_id]
                    ,s.index_id
                    ,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
                    ,SUM(p.[rows]) AS [RowCount]
                    ,p.data_compression_desc AS CompressionDescription
                FROM sys.dm_db_partition_stats AS s
                INNER JOIN sys.partitions p WITH (NOLOCK) ON s.[partition_id] = p.[partition_id]
                    AND s.[object_id] = p.[object_id]
                    AND s.index_id = p.index_id
                WHERE s.index_id > 0 -- Exclude HEAPS
                    AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
                GROUP BY s.[object_id]
                    ,s.index_id
                    ,p.data_compression_desc
                )
            SELECT DB_NAME() AS DatabaseName
                ,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
                ,CI1.IndexName
                ,CI1.KeyColumns
                ,CI1.IncludedColumns
                ,CI1.IndexType
                ,COALESCE(CSPC.IndexSizeMB,0) AS 'IndexSizeMB'
                ,COALESCE(CSPC.CompressionDescription, 'NONE') AS 'CompressionDescription'
                ,COALESCE(CSPC.[RowCount],0) AS 'RowCount'
                ,CI1.IsDisabled
                ,CI1.IsFiltered
            FROM CTE_IndexCols AS CI1
            LEFT JOIN CTE_IndexSpace AS CSPC ON CI1.[object_id] = CSPC.[object_id]
                AND CI1.index_id = CSPC.index_id
            WHERE EXISTS (
                    SELECT 1
                    FROM CTE_IndexCols CI2
                    WHERE CI1.SchemaName = CI2.SchemaName
                        AND CI1.TableName = CI2.TableName
                        AND CI1.KeyColumns = CI2.KeyColumns
                        AND CI1.IncludedColumns = CI2.IncludedColumns
                        AND CI1.IsFiltered = CI2.IsFiltered
                        AND CI1.IndexName <> CI2.IndexName
                    )"

        $overlappingQuery = "
            WITH CTE_IndexCols AS
            (
                SELECT
                        i.[object_id]
                        ,i.index_id
                        ,OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName
                        ,OBJECT_NAME(i.[object_id]) AS TableName
                        ,Name AS IndexName
                        ,ISNULL(STUFF((SELECT ', ' + col.NAME + ' ' + CASE
                                                                    WHEN idxCol.is_descending_key = 1 THEN 'DESC'
                                                                    ELSE 'ASC'
                                                                END -- Include column order (ASC / DESC)
                                FROM sys.index_columns idxCol
                                    INNER JOIN sys.columns col
                                    ON idxCol.[object_id] = col.[object_id]
                                    AND idxCol.column_id = col.column_id
                                WHERE i.[object_id] = idxCol.[object_id]
                                AND i.index_id = idxCol.index_id
                                AND idxCol.is_included_column = 0
                                ORDER BY idxCol.key_ordinal
                        FOR XML PATH('')), 1, 2, ''), '') AS KeyColumns
                        ,ISNULL(STUFF((SELECT ', ' + col.NAME + ' ' + CASE
                                                                    WHEN idxCol.is_descending_key = 1 THEN 'DESC'
                                                                    ELSE 'ASC'
                                                                END -- Include column order (ASC / DESC)
                                FROM sys.index_columns idxCol
                                    INNER JOIN sys.columns col
                                    ON idxCol.[object_id] = col.[object_id]
                                    AND idxCol.column_id = col.column_id
                                WHERE i.[object_id] = idxCol.[object_id]
                                AND i.index_id = idxCol.index_id
                                AND idxCol.is_included_column = 1
                                ORDER BY idxCol.key_ordinal
                        FOR XML PATH('')), 1, 2, ''), '') AS IncludedColumns
                        ,i.[type_desc] AS IndexType
                        ,i.is_disabled AS IsDisabled
                        ,i.has_filter AS IsFiltered
                FROM sys.indexes AS i
                WHERE i.index_id > 0 -- Exclude HEAPS
                AND i.[type_desc] IN ('CLUSTERED', 'NONCLUSTERED')
                AND OBJECT_SCHEMA_NAME(i.[object_id]) <> 'sys'
            ),
            CTE_IndexSpace AS
            (
            SELECT
                        s.[object_id]
                        ,s.index_id
                        ,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
                        ,SUM(p.[rows]) AS [RowCount]
                        ,p.data_compression_desc AS CompressionDescription
                FROM sys.dm_db_partition_stats AS s
                    INNER JOIN sys.partitions p WITH (NOLOCK)
                    ON s.[partition_id] = p.[partition_id]
                    AND s.[object_id] = p.[object_id]
                    AND s.index_id = p.index_id
                WHERE s.index_id > 0 -- Exclude HEAPS
                    AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
                GROUP BY s.[object_id], s.index_id, p.data_compression_desc
            )
            SELECT
                    DB_NAME() AS DatabaseName
                    ,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
                    ,CI1.IndexName
                    ,CI1.KeyColumns
                    ,CI1.IncludedColumns
                    ,CI1.IndexType
                    ,COALESCE(CSPC.IndexSizeMB,0) AS 'IndexSizeMB'
                    ,COALESCE(CSPC.CompressionDescription, 'NONE') AS 'CompressionDescription'
                    ,COALESCE(CSPC.[RowCount],0) AS 'RowCount'
                    ,CI1.IsDisabled
                    ,CI1.IsFiltered
            FROM CTE_IndexCols AS CI1
                LEFT JOIN CTE_IndexSpace AS CSPC
                ON CI1.[object_id] = CSPC.[object_id]
                AND CI1.index_id = CSPC.index_id
            WHERE EXISTS (SELECT 1
                            FROM CTE_IndexCols CI2
                        WHERE CI1.SchemaName = CI2.SchemaName
                            AND CI1.TableName = CI2.TableName
                            AND (
                                        (CI1.KeyColumns like CI2.KeyColumns + '%' and SUBSTRING(CI1.KeyColumns,LEN(CI2.KeyColumns)+1,1) = ' ')
                                    OR (CI2.KeyColumns like CI1.KeyColumns + '%' and SUBSTRING(CI2.KeyColumns,LEN(CI1.KeyColumns)+1,1) = ' ')
                                )
                            AND CI1.IsFiltered = CI2.IsFiltered
                            AND CI1.IndexName <> CI2.IndexName
                        )"
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($database) {
                $databases = $server.Databases | Where-Object Name -in $database
            } else {
                $databases = $server.Databases | Where-Object IsAccessible -eq $true
            }

            foreach ($db in $databases) {
                try {
                    Write-Message -Level Verbose -Message "Getting indexes from database '$db'."

                    $query = if ($server.versionMajor -eq 9) {
                        if ($IncludeOverlapping) { $overlappingQuery2005 }
                        else { $exactDuplicateQuery2005 }
                    } else {
                        if ($IncludeOverlapping) { $overlappingQuery }
                        else { $exactDuplicateQuery }
                    }

                    $db.Query($query)

                } catch {
                    Stop-Function -Message "Query failure" -Target $db
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUlXFcUBED1eiPICaL7tTL2pQT
# kjigghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFHuAwhebYWygOFwpVVUyFGv88SblMA0GCSqGSIb3DQEBAQUABIIBAEVG/3kS
# Ta48tk/TIsOf+tmod9EuUc+gUdnx7ZR9kI+r4vPjIbQtiy8Nmac4QRowFp7y/fRh
# utxA//7tD5avf6rnx5ed/41/wCcPxrFArYIOrp2avltBp4LLfY3KZvGZgZtCa6I1
# IWDFHomDE/uL9bD/zXG9fMt26rNc6fWTYHkpZFfakE9dQwFVtJPBnZvBn/azlYtX
# kgmIpGTbc959kxK4518jjyK2Od5xwSd5/kA/IeBAO2WqzdsbhKUtqfwGqWE6NTan
# c7VhKd3cZ5Vrkg/xiR+5JnBOiTaQtF2PTWM+o7PGZJ2xLmWSh1Oq0UWZtV+vmwvT
# a26/HXSqyvLOSEOhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkyM1owLwYJKoZIhvcNAQkEMSIEIBpeDZeErHv1pAQ0ozzo3FimLmg5
# 1JkhjhOaNY00gySXMA0GCSqGSIb3DQEBAQUABIIBACbELMCaKlOCrzpuqk3lkxOu
# yudke2EX18N6pM5KV0jTRLOxei/omn6259qM06HwZpbZt09IPBuUB2S0V4QhlLrC
# XDmkbsteTxXA89pILvFjC09oGGPdr9/jYx9y9sLqGzo6ditRMv8wr+pyyrMrhU3K
# HmYZ1wu6hXfWrRYriN4YxShXM3dNqjSirJHIGKuTP5Mxtk8KjMbAr267Ds3MpSa7
# yZSMOut3ktQh/LG6TANs0gQW5FnAtn1N0UeO67SNRRhmjnqs0SMvCeg+49Omqw8M
# c/2DeR1p+oeHhUdjbeoIrWyFD9D1+xjBteJtpAmtsuUvozN7Vqi9tF1xIj+0AEM=
# SIG # End signature block
