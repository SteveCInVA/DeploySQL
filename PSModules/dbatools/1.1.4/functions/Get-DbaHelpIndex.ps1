function Get-DbaHelpIndex {
    <#
    .SYNOPSIS
        Returns size, row and configuration information for indexes in databases.

    .DESCRIPTION
        This function will return detailed information on indexes (and optionally statistics) for all indexes in a database, or a given index should one be passed along.
        As this uses SQL Server DMVs to access the data it will only work in 2005 and up (sorry folks still running SQL Server 2000).
        For performance reasons certain statistics information will not be returned from SQL Server 2005 if an ObjectName is not provided.

        The data includes:
        - ObjectName: the table containing the index
        - IndexType: clustered/non-clustered/columnstore and whether the index is unique/primary key
        - KeyColumns: the key columns of the index
        - IncludeColumns: any include columns in the index
        - FilterDefinition: any filter that may have been used in the index
        - DataCompression: row/page/none depending upon whether or not compression has been used
        - IndexReads: the number of reads of the index since last restart or index rebuild
        - IndexUpdates: the number of writes to the index since last restart or index rebuild
        - SizeKB: the size the index in KB
        - IndexRows: the number of the rows in the index (note filtered indexes will have fewer rows than exist in the table)
        - IndexLookups: the number of lookups that have been performed (only applicable for the heap or clustered index)
        - MostRecentlyUsed: when the index was most recently queried (default to 1900 for when never read)
        - StatsSampleRows: the number of rows queried when the statistics were built/rebuilt (not included in SQL Server 2005 unless ObjectName is specified)
        - StatsRowMods: the number of changes to the statistics since the last rebuild
        - HistogramSteps: the number of steps in the statistics histogram (not included in SQL Server 2005 unless ObjectName is specified)
        - StatsLastUpdated: when the statistics were last rebuilt (not included in SQL Server 2005 unless ObjectName is specified)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER ObjectName
        The name of a table for which you want to obtain the index information. If the two part naming convention for an object is not used it will use the default schema for the executing user. If not passed it will return data on all indexes in a given database.

    .PARAMETER IncludeStats
        If this switch is enabled, statistics as well as indexes will be returned in the output (statistics information such as the StatsRowMods will always be returned for indexes).

    .PARAMETER IncludeDataTypes
        If this switch is enabled, the output will include the data type of each column that makes up a part of the index definition (key and include columns).

    .PARAMETER IncludeFragmentation
        If this switch is enabled, the output will include fragmentation information.

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase

    .PARAMETER Raw
        If this switch is enabled, results may be less user-readable but more suitable for processing by other code.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Index
        Author: Nic Cain, https://sirsql.net/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaHelpIndex

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB

        Returns information on all indexes on the MyDB database on the localhost.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB,MyDB2

        Returns information on all indexes on the MyDB & MyDB2 databases.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -ObjectName dbo.Table1

        Returns index information on the object dbo.Table1 in the database MyDB.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -ObjectName dbo.Table1 -IncludeStats

        Returns information on the indexes and statistics for the table dbo.Table1 in the MyDB database.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -ObjectName dbo.Table1 -IncludeDataTypes

        Returns the index information for the table dbo.Table1 in the MyDB database, and includes the data types for the key and include columns.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -ObjectName dbo.Table1 -Raw

        Returns the index information for the table dbo.Table1 in the MyDB database, and returns the numerical data without localized separators.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -IncludeStats -Raw

        Returns the index information for all indexes in the MyDB database as well as their statistics, and formats the numerical data without localized separators.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -IncludeFragmentation

        Returns the index information for all indexes in the MyDB database as well as their fragmentation

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017 -Database MyDB | Get-DbaHelpIndex

        Returns the index information for all indexes in the MyDB database

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [string]$ObjectName,
        [switch]$IncludeStats,
        [switch]$IncludeDataTypes,
        [switch]$Raw,
        [switch]$IncludeFragmentation,
        [switch]$EnableException
    )

    begin {

        #Add the table predicate to the query
        if (!$ObjectName) {
            $TablePredicate = "DECLARE @TableName NVARCHAR(256);";
        } else {
            $TablePredicate = "DECLARE @TableName NVARCHAR(256); SET @TableName = '$ObjectName';";
        }

        #Add Fragmentation info if requested
        $FragSelectColumn = ", NULL as avg_fragmentation_in_percent"
        $FragJoin = ''
        $OutputProperties = 'Database,Object,Index,IndexType,KeyColumns,IncludeColumns,FilterDefinition,DataCompression,IndexReads,IndexUpdates,SizeKB,IndexRows,IndexLookups,MostRecentlyUsed,StatsSampleRows,StatsRowMods,HistogramSteps,StatsLastUpdated'
        if ($IncludeFragmentation) {
            $FragSelectColumn = ', pstat.avg_fragmentation_in_percent'
            $FragJoin = "LEFT JOIN sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL , 'DETAILED') pstat
             ON pstat.database_id = ustat.database_id
             AND pstat.object_id = ustat.object_id
             AND pstat.index_id = ustat.index_id"
            $OutputProperties = 'Database,Object,Index,IndexType,KeyColumns,IncludeColumns,FilterDefinition,DataCompression,IndexReads,IndexUpdates,SizeKB,IndexRows,IndexLookups,MostRecentlyUsed,StatsSampleRows,StatsRowMods,HistogramSteps,StatsLastUpdated,IndexFragInPercent'
        }
        $OutputProperties = $OutputProperties.Split(',')
        #Figure out if we are including stats in the results
        if ($IncludeStats) {
            $IncludeStatsPredicate = "";
        } else {
            $IncludeStatsPredicate = "WHERE StatisticsName IS NULL";
        }

        #Data types being returns with the results?
        if ($IncludeDataTypes) {
            $IncludeDataTypesPredicate = 'DECLARE @IncludeDataTypes BIT; SET @IncludeDataTypes = 1';
        } else {
            $IncludeDataTypesPredicate = 'DECLARE @IncludeDataTypes BIT; SET @IncludeDataTypes = 0';
        }

        #region SizesQuery
        $SizesQuery = "
            SET NOCOUNT ON;
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

            $TablePredicate
            $IncludeDataTypesPredicate
            ;

        DECLARE @IndexUsageStats TABLE
            (
            object_id INT ,
            index_id INT ,
            user_scans BIGINT ,
            user_seeks BIGINT ,
            user_updates BIGINT ,
            user_lookups BIGINT ,
            last_user_lookup DATETIME2(0) ,
            last_user_scan DATETIME2(0) ,
            last_user_seek DATETIME2(0) ,
            avg_fragmentation_in_percent FLOAT
            );

        DECLARE @StatsInfo TABLE
            (
            object_id INT ,
            stats_id INT ,
            stats_column_name NVARCHAR(128) ,
            stats_column_id INT ,
            stats_name NVARCHAR(128) ,
            stats_last_updated DATETIME2(0) ,
            stats_sampled_rows BIGINT ,
            rowmods BIGINT ,
            histogramsteps INT ,
            StatsRows BIGINT ,
            FullObjectName NVARCHAR(256)
            );

        INSERT  INTO @IndexUsageStats
                ( object_id ,
                index_id ,
                user_scans ,
                user_seeks ,
                user_updates ,
                user_lookups ,
                last_user_lookup ,
                last_user_scan ,
                last_user_seek ,
                avg_fragmentation_in_percent
                )
                SELECT  ustat.object_id ,
                        ustat.index_id ,
                        ustat.user_scans ,
                        ustat.user_seeks ,
                        ustat.user_updates ,
                        ustat.user_lookups ,
                        ustat.last_user_lookup ,
                        ustat.last_user_scan ,
                        ustat.last_user_seek
                        $FragSelectColumn
                FROM    sys.dm_db_index_usage_stats ustat
                $FragJoin
                WHERE   ustat.database_id = DB_ID();

        INSERT  INTO @StatsInfo
                ( object_id ,
                stats_id ,
                stats_column_name ,
                stats_column_id ,
                stats_name ,
                stats_last_updated ,
                stats_sampled_rows ,
                rowmods ,
                histogramsteps ,
                StatsRows ,
                FullObjectName
                )
                SELECT  s.object_id ,
                        s.stats_id ,
                        c.name ,
                        sc.stats_column_id ,
                        s.name ,
                        sp.last_updated ,
                        sp.rows_sampled ,
                        sp.modification_counter ,
                        sp.steps ,
                        sp.rows ,
                        QUOTENAME(sch.name) + '.' + QUOTENAME(t.name) AS FullObjectName
                FROM    [sys].[stats] AS [s]
                        INNER JOIN sys.stats_columns sc ON s.stats_id = sc.stats_id
                                                        AND s.object_id = sc.object_id
                        INNER JOIN sys.columns c ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                        INNER JOIN sys.tables t ON c.object_id = t.object_id
                        INNER JOIN sys.schemas sch ON sch.schema_id = t.schema_id
                        OUTER APPLY sys.dm_db_stats_properties([s].[object_id],
                                                            [s].[stats_id]) AS [sp]
                WHERE   s.object_id = CASE WHEN @TableName IS NULL THEN s.object_id
                                        else OBJECT_ID(@TableName)
                                    END;


        ;
        WITH    cteStatsInfo
                AS ( SELECT   object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                STUFF((SELECT   N', ' + stats_column_name
                                    FROM     @StatsInfo si2
                                    WHERE    si2.object_id = si.object_id
                                                AND si2.stats_id = si.stats_id
                                    ORDER BY si2.stats_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(1000)'), 1,
                                    2, N'') AS StatsColumns ,
                                MAX(si.stats_sampled_rows) AS SampleRows ,
                                MAX(si.rowmods) AS RowMods ,
                                MAX(si.histogramsteps) AS HistogramSteps ,
                                MAX(si.stats_last_updated) AS StatsLastUpdated ,
                                MAX(si.StatsRows) AS StatsRows,
                                FullObjectName
                    FROM     @StatsInfo si
                    GROUP BY si.object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                si.FullObjectName
                    ),
                cteIndexSizes
                AS ( SELECT   object_id ,
                                index_id ,
                                CASE WHEN index_id < 2
                                    THEN ( ( SUM(in_row_data_page_count
                                                + lob_used_page_count
                                                + row_overflow_used_page_count)
                                            * 8192 ) / 1024 )
                                    else ( ( SUM(used_page_count) * 8192 ) / 1024 )
                                END AS SizeKB
                    FROM     sys.dm_db_partition_stats
                    GROUP BY object_id ,
                                index_id
                    ),
                cteRows
                AS ( SELECT   object_id ,
                                index_id ,
                                SUM(rows) AS IndexRows
                    FROM     sys.partitions
                    GROUP BY object_id ,
                                index_id
                    ),
                cteIndex
                AS ( SELECT   OBJECT_NAME(c.object_id) AS ObjectName ,
                                c.object_id ,
                                c.index_id ,
                                i.name COLLATE SQL_Latin1_General_CP1_CI_AS AS name ,
                                c.index_column_id ,
                                c.column_id ,
                                c.is_included_column ,
                                CASE WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 1
                                    THEN sc.name + ' DESC'
                                    WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 0 THEN sc.name
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 1
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' DESC (' + t.name + ') '
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 0
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' (' + t.name + ')'
                                    else sc.name
                                END AS ColumnName ,
                                i.filter_definition ,
                                ISNULL(dd.user_scans, 0) AS user_scans ,
                                ISNULL(dd.user_seeks, 0) AS user_seeks ,
                                ISNULL(dd.user_updates, 0) AS user_updates ,
                                ISNULL(dd.user_lookups, 0) AS user_lookups ,
                                CONVERT(DATETIME2(0), ISNULL(dd.last_user_lookup,
                                                            '1901-01-01')) AS LastLookup ,
                                CONVERT(DATETIME2(0), ISNULL(dd.last_user_scan,
                                                            '1901-01-01')) AS LastScan ,
                                CONVERT(DATETIME2(0), ISNULL(dd.last_user_seek,
                                                            '1901-01-01')) AS LastSeek ,
                                i.fill_factor ,
                                c.is_descending_key ,
                                p.data_compression_desc ,
                                i.type_desc ,
                                i.is_unique ,
                                i.is_unique_constraint ,
                                i.is_primary_key ,
                                ci.SizeKB ,
                                cr.IndexRows ,
                                QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                ISNULL(dd.avg_fragmentation_in_percent, 0) as avg_fragmentation_in_percent
                    FROM     sys.indexes i
                                JOIN sys.index_columns c ON i.object_id = c.object_id
                                                            AND i.index_id = c.index_id
                                JOIN sys.columns sc ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                                INNER JOIN sys.tables tbl ON c.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                                LEFT JOIN sys.types t ON sc.user_type_id = t.user_type_id
                                LEFT JOIN @IndexUsageStats dd ON i.object_id = dd.object_id
                                                                AND i.index_id = dd.index_id --and dd.database_id = db_id()
                                JOIN sys.partitions p ON i.object_id = p.object_id
                                                        AND i.index_id = p.index_id
                                JOIN cteIndexSizes ci ON i.object_id = ci.object_id
                                                        AND i.index_id = ci.index_id
                                JOIN cteRows cr ON i.object_id = cr.object_id
                                                AND i.index_id = cr.index_id
                    WHERE    i.object_id = CASE WHEN @TableName IS NULL
                                                THEN i.object_id
                                                else OBJECT_ID(@TableName)
                                            END
                    ),
                cteResults
                AS ( SELECT   ci.FullObjectName ,
                                ci.object_id ,
                                MAX(index_id) AS Index_Id ,
                                ci.type_desc
                                + CASE WHEN ci.is_primary_key = 1
                                    THEN ' (PRIMARY KEY)'
                                    WHEN ci.is_unique_constraint = 1
                                    THEN ' (UNIQUE CONSTRAINT)'
                                    WHEN ci.is_unique = 1 THEN ' (UNIQUE)'
                                    else ''
                                END AS IndexType ,
                                name AS IndexName ,
                                STUFF((SELECT   N', ' + ColumnName
                                    FROM     cteIndex ci2
                                    WHERE    ci2.name = ci.name
                                                AND ci2.is_included_column = 0
                                    GROUP BY ci2.index_column_id ,
                                                ci2.ColumnName
                                    ORDER BY ci2.index_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(1000)'), 1,
                                    2, N'') AS KeyColumns ,
                                ISNULL(STUFF((SELECT    N',  ' + ColumnName
                                            FROM      cteIndex ci3
                                            WHERE     ci3.name = ci.name
                                                        AND ci3.is_included_column = 1
                                            GROUP BY  ci3.index_column_id ,
                                                        ci3.ColumnName
                                            ORDER BY  ci3.index_column_id
                                    FOR   XML PATH(N'') ,
                                                TYPE).value(N'.[1]',
                                                            N'nvarchar(1000)'), 1, 2,
                                            N''), '') AS IncludeColumns ,
                                ISNULL(filter_definition, '') AS FilterDefinition ,
                                ci.fill_factor ,
                                CASE WHEN ci.data_compression_desc = 'NONE' THEN ''
                                    else ci.data_compression_desc
                                END AS DataCompression ,
                                MAX(ci.user_seeks) + MAX(ci.user_scans)
                                + MAX(ci.user_lookups) AS IndexReads ,
                                MAX(ci.user_lookups) AS IndexLookups ,
                                ci.user_updates AS IndexUpdates ,
                                ci.SizeKB AS SizeKB ,
                                ci.IndexRows AS IndexRows ,
                                CASE WHEN LastScan > LastSeek
                                        AND LastScan > LastLookup THEN LastScan
                                    WHEN LastSeek > LastScan
                                        AND LastSeek > LastLookup THEN LastSeek
                                    WHEN LastLookup > LastScan
                                        AND LastLookup > LastSeek THEN LastLookup
                                    else ''
                                END AS MostRecentlyUsed ,
                                AVG(ci.avg_fragmentation_in_percent) as avg_fragmentation_in_percent
                    FROM     cteIndex ci
                    GROUP BY ci.ObjectName ,
                                ci.name ,
                                ci.filter_definition ,
                                ci.object_id ,
                                ci.LastLookup ,
                                ci.LastSeek ,
                                ci.LastScan ,
                                ci.user_updates ,
                                ci.fill_factor ,
                                ci.data_compression_desc ,
                                ci.type_desc ,
                                ci.is_primary_key ,
                                ci.is_unique ,
                                ci.is_unique_constraint ,
                                ci.SizeKB ,
                                ci.IndexRows ,
                                ci.FullObjectName
                    ),
                AllResults
                AS ( SELECT   c.FullObjectName ,
                                IndexType ,
                                ISNULL(IndexName, si.stats_name) AS IndexName ,
                                NULL as StatisticsName ,
                                ISNULL(KeyColumns, si.StatsColumns) AS KeyColumns ,
                                ISNULL(IncludeColumns, '') AS IncludeColumns ,
                                FilterDefinition ,
                                fill_factor AS [FillFactor] ,
                                DataCompression ,
                                IndexReads ,
                                IndexUpdates ,
                                SizeKB ,
                                IndexRows ,
                                IndexLookups ,
                                MostRecentlyUsed ,
                                SampleRows AS StatsSampleRows ,
                                RowMods AS StatsRowMods ,
                                si.HistogramSteps ,
                                si.StatsLastUpdated ,
                                avg_fragmentation_in_percent AS IndexFragInPercent,
                                1 AS Ordering
                    FROM     cteResults c
                                INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                            AND si.stats_id = c.Index_Id
                    UNION
                    SELECT   QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                '' ,
                                '' ,
                                stats_name ,
                                StatsColumns ,
                                '' ,
                                '' AS FilterDefinition ,
                                '' AS Fill_Factor ,
                                '' AS DataCompression ,
                                '' AS IndexReads ,
                                '' AS IndexUpdates ,
                                '' AS SizeKB ,
                                StatsRows AS IndexRows ,
                                '' AS IndexLookups ,
                                '' AS MostRecentlyUsed ,
                                SampleRows AS StatsSampleRows ,
                                RowMods AS StatsRowMods ,
                                csi.HistogramSteps ,
                                csi.StatsLastUpdated ,
                                '' AS IndexFragInPercent ,
                                2
                    FROM     cteStatsInfo csi
                    INNER JOIN sys.tables tbl ON csi.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                    WHERE    stats_id NOT IN (
                                SELECT  stats_id
                                FROM    cteResults c
                                        INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                                    AND si.stats_id = c.Index_Id )
                    )
            SELECT  FullObjectName ,
                    IndexType ,
                    IndexName ,
                    StatisticsName ,
                    KeyColumns ,
                    ISNULL(IncludeColumns, '') AS IncludeColumns ,
                    FilterDefinition ,
                    [FillFactor] AS [FillFactor] ,
                    DataCompression ,
                    IndexReads ,
                    IndexUpdates ,
                    SizeKB ,
                    IndexRows ,
                    IndexLookups ,
                    MostRecentlyUsed ,
                    StatsSampleRows ,
                    StatsRowMods ,
                    HistogramSteps ,
                    StatsLastUpdated ,
                    IndexFragInPercent
            FROM    AllResults
                    $IncludeStatsPredicate
        OPTION  ( RECOMPILE );
        "
        #endRegion SizesQuery


        #region sizesQuery2005
        $SizesQuery2005 = "
        SET NOCOUNT ON;
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

        $TablePredicate
        $IncludeDataTypesPredicate
        ;

        DECLARE @AllResults TABLE
            (
                RowNum INT ,
                FullObjectName	NVARCHAR(300) ,
                IndexType	NVARCHAR(256) ,
                IndexName	NVARCHAR(256) ,
                KeyColumns	NVARCHAR(2000) ,
                IncludeColumns	NVARCHAR(2000) ,
                FilterDefinition	NVARCHAR(100) ,
                [FillFactor]	TINYINT ,
                DataCompression	CHAR(4) ,
                IndexReads	BIGINT ,
                IndexUpdates	BIGINT ,
                SizeKB	BIGINT ,
                IndexRows	BIGINT ,
                IndexLookups	BIGINT ,
                MostRecentlyUsed	DATETIME ,
                StatsSampleRows	BIGINT ,
                StatsRowMods	BIGINT ,
                HistogramSteps	INT	,
                StatsLastUpdated	DATETIME ,
                object_id BIGINT ,
                index_id BIGINT
            );

        DECLARE @IndexUsageStats TABLE
            (
            object_id INT ,
            index_id INT ,
            user_scans BIGINT ,
            user_seeks BIGINT ,
            user_updates BIGINT ,
            user_lookups BIGINT ,
            last_user_lookup DATETIME ,
            last_user_scan DATETIME ,
            last_user_seek DATETIME ,
            avg_fragmentation_in_percent FLOAT
            );

        DECLARE @StatsInfo TABLE
            (
            object_id INT ,
            stats_id INT ,
            stats_column_name NVARCHAR(128) ,
            stats_column_id INT ,
            stats_name NVARCHAR(128) ,
            stats_last_updated DATETIME ,
            stats_sampled_rows BIGINT ,
            rowmods BIGINT ,
            histogramsteps INT ,
            StatsRows BIGINT ,
            FullObjectName NVARCHAR(256)
            );

        INSERT  INTO @IndexUsageStats
                ( object_id ,
                index_id ,
                user_scans ,
                user_seeks ,
                user_updates ,
                user_lookups ,
                last_user_lookup ,
                last_user_scan ,
                last_user_seek ,
                avg_fragmentation_in_percent
                )
                SELECT  ustat.object_id ,
                        ustat.index_id ,
                        ustat.user_scans ,
                        ustat.user_seeks ,
                        ustat.user_updates ,
                        ustat.user_lookups ,
                        ustat.last_user_lookup ,
                        ustat.last_user_scan ,
                        ustat.last_user_seek
                        $FragSelectColumn
                FROM    sys.dm_db_index_usage_stats ustat
                $FragJoin
                WHERE   database_id = DB_ID();


        INSERT  INTO @StatsInfo
                ( object_id ,
                stats_id ,
                stats_column_name ,
                stats_column_id ,
                stats_name ,
                stats_last_updated ,
                stats_sampled_rows ,
                rowmods ,
                histogramsteps ,
                StatsRows ,
                FullObjectName
                )
                SELECT  s.object_id ,
                        s.stats_id ,
                        c.name ,
                        sc.stats_column_id ,
                        s.name ,
                        NULL AS last_updated ,
                        NULL AS rows_sampled ,
                        NULL AS modification_counter ,
                        NULL AS steps ,
                        NULL AS rows ,
                        QUOTENAME(sch.name) + '.' + QUOTENAME(t.name) AS FullObjectName
                FROM    [sys].[stats] AS [s]
                        INNER JOIN sys.stats_columns sc ON s.stats_id = sc.stats_id
                                                        AND s.object_id = sc.object_id
                        INNER JOIN sys.columns c ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                        INNER JOIN sys.tables t ON c.object_id = t.object_id
                        INNER JOIN sys.schemas sch ON sch.schema_id = t.schema_id
                    --   OUTER APPLY sys.dm_db_stats_properties([s].[object_id],
                    --                                        [s].[stats_id]) AS [sp]
                WHERE   s.object_id = CASE WHEN @TableName IS NULL THEN s.object_id
                                        else OBJECT_ID(@TableName)
                                    END;


        ;
        WITH    cteStatsInfo
                AS ( SELECT   object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                STUFF((SELECT   N', ' + stats_column_name
                                    FROM     @StatsInfo si2
                                    WHERE    si2.object_id = si.object_id
                                                AND si2.stats_id = si.stats_id
                                    ORDER BY si2.stats_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(1000)'), 1,
                                    2, N'') AS StatsColumns ,
                                MAX(si.stats_sampled_rows) AS SampleRows ,
                                MAX(si.rowmods) AS RowMods ,
                                MAX(si.histogramsteps) AS HistogramSteps ,
                                MAX(si.stats_last_updated) AS StatsLastUpdated ,
                                MAX(si.StatsRows) AS StatsRows,
                                FullObjectName
                    FROM     @StatsInfo si
                    GROUP BY si.object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                si.FullObjectName
                    ),
                cteIndexSizes
                AS ( SELECT   object_id ,
                                index_id ,
                                CASE WHEN index_id < 2
                                    THEN ( ( SUM(in_row_data_page_count
                                                + lob_used_page_count
                                                + row_overflow_used_page_count)
                                            * 8192 ) / 1024 )
                                    else ( ( SUM(used_page_count) * 8192 ) / 1024 )
                                END AS SizeKB
                    FROM     sys.dm_db_partition_stats
                    GROUP BY object_id ,
                                index_id
                    ),
                cteRows
                AS ( SELECT   object_id ,
                                index_id ,
                                SUM(rows) AS IndexRows
                    FROM     sys.partitions
                    GROUP BY object_id ,
                                index_id
                    ),
                cteIndex
                AS ( SELECT   OBJECT_NAME(c.object_id) AS ObjectName ,
                                c.object_id ,
                                c.index_id ,
                                i.name COLLATE SQL_Latin1_General_CP1_CI_AS AS name ,
                                c.index_column_id ,
                                c.column_id ,
                                c.is_included_column ,
                                CASE WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 1
                                    THEN sc.name + ' DESC'
                                    WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 0 THEN sc.name
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 1
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' DESC (' + t.name + ') '
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 0
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' (' + t.name + ')'
                                    else sc.name
                                END AS ColumnName ,
                                '' AS filter_definition ,
                                ISNULL(dd.user_scans, 0) AS user_scans ,
                                ISNULL(dd.user_seeks, 0) AS user_seeks ,
                                ISNULL(dd.user_updates, 0) AS user_updates ,
                                ISNULL(dd.user_lookups, 0) AS user_lookups ,
                                CONVERT(DATETIME, ISNULL(dd.last_user_lookup,
                                                            '1901-01-01')) AS LastLookup ,
                                CONVERT(DATETIME, ISNULL(dd.last_user_scan,
                                                            '1901-01-01')) AS LastScan ,
                                CONVERT(DATETIME, ISNULL(dd.last_user_seek,
                                                            '1901-01-01')) AS LastSeek ,
                                i.fill_factor ,
                                c.is_descending_key ,
                                'NONE' as data_compression_desc ,
                                i.type_desc ,
                                i.is_unique ,
                                i.is_unique_constraint ,
                                i.is_primary_key ,
                                ci.SizeKB ,
                                cr.IndexRows ,
                                QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                ISNULL(dd.avg_fragmentation_in_percent, 0) as avg_fragmentation_in_percent
                    FROM     sys.indexes i
                                JOIN sys.index_columns c ON i.object_id = c.object_id
                                                            AND i.index_id = c.index_id
                                JOIN sys.columns sc ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                                INNER JOIN sys.tables tbl ON c.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                                LEFT JOIN sys.types t ON sc.user_type_id = t.user_type_id
                                LEFT JOIN @IndexUsageStats dd ON i.object_id = dd.object_id
                                                                AND i.index_id = dd.index_id --and dd.database_id = db_id()
                                JOIN sys.partitions p ON i.object_id = p.object_id
                                                        AND i.index_id = p.index_id
                                JOIN cteIndexSizes ci ON i.object_id = ci.object_id
                                                        AND i.index_id = ci.index_id
                                JOIN cteRows cr ON i.object_id = cr.object_id
                                                AND i.index_id = cr.index_id
                    WHERE    i.object_id = CASE WHEN @TableName IS NULL
                                                THEN i.object_id
                                                else OBJECT_ID(@TableName)
                                            END
                    ),
                cteResults
                AS ( SELECT   ci.FullObjectName ,
                                ci.object_id ,
                                MAX(index_id) AS Index_Id ,
                                ci.type_desc
                                + CASE WHEN ci.is_primary_key = 1
                                    THEN ' (PRIMARY KEY)'
                                    WHEN ci.is_unique_constraint = 1
                                    THEN ' (UNIQUE CONSTRAINT)'
                                    WHEN ci.is_unique = 1 THEN ' (UNIQUE)'
                                    else ''
                                END AS IndexType ,
                                name AS IndexName ,
                                STUFF((SELECT   N', ' + ColumnName
                                    FROM     cteIndex ci2
                                    WHERE    ci2.name = ci.name
                                                AND ci2.is_included_column = 0
                                    GROUP BY ci2.index_column_id ,
                                                ci2.ColumnName
                                    ORDER BY ci2.index_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(1000)'), 1,
                                    2, N'') AS KeyColumns ,
                                ISNULL(STUFF((SELECT    N',  ' + ColumnName
                                            FROM      cteIndex ci3
                                            WHERE     ci3.name = ci.name
                                                        AND ci3.is_included_column = 1
                                            GROUP BY  ci3.index_column_id ,
                                                        ci3.ColumnName
                                            ORDER BY  ci3.index_column_id
                                    FOR   XML PATH(N'') ,
                                                TYPE).value(N'.[1]',
                                                            N'nvarchar(1000)'), 1, 2,
                                            N''), '') AS IncludeColumns ,
                                ISNULL(filter_definition, '') AS FilterDefinition ,
                                ci.fill_factor ,
                                CASE WHEN ci.data_compression_desc = 'NONE' THEN ''
                                    else ci.data_compression_desc
                                END AS DataCompression ,
                                MAX(ci.user_seeks) + MAX(ci.user_scans)
                                + MAX(ci.user_lookups) AS IndexReads ,
                                MAX(ci.user_lookups) AS IndexLookups ,
                                ci.user_updates AS IndexUpdates ,
                                ci.SizeKB AS SizeKB ,
                                ci.IndexRows AS IndexRows ,
                                CASE WHEN LastScan > LastSeek
                                        AND LastScan > LastLookup THEN LastScan
                                    WHEN LastSeek > LastScan
                                        AND LastSeek > LastLookup THEN LastSeek
                                    WHEN LastLookup > LastScan
                                        AND LastLookup > LastSeek THEN LastLookup
                                    else ''
                                END AS MostRecentlyUsed ,
                                AVG(ci.avg_fragmentation_in_percent) as avg_fragmentation_in_percent
                    FROM     cteIndex ci
                    GROUP BY ci.ObjectName ,
                                ci.name ,
                                ci.filter_definition ,
                                ci.object_id ,
                                ci.LastLookup ,
                                ci.LastSeek ,
                                ci.LastScan ,
                                ci.user_updates ,
                                ci.fill_factor ,
                                ci.data_compression_desc ,
                                ci.type_desc ,
                                ci.is_primary_key ,
                                ci.is_unique ,
                                ci.is_unique_constraint ,
                                ci.SizeKB ,
                                ci.IndexRows ,
                                ci.FullObjectName
                    ), AllResults AS
                        (		 SELECT   c.FullObjectName ,
                                ISNULL(IndexType, 'STATISTICS') AS IndexType ,
                                ISNULL(IndexName, '') AS IndexName ,
                                ISNULL(KeyColumns, '') AS KeyColumns ,
                                ISNULL(IncludeColumns, '') AS IncludeColumns ,
                                FilterDefinition ,
                                fill_factor AS [FillFactor] ,
                                DataCompression ,
                                IndexReads ,
                                IndexUpdates ,
                                SizeKB ,
                                IndexRows ,
                                IndexLookups ,
                                MostRecentlyUsed ,
                                NULL AS StatsSampleRows ,
                                NULL AS StatsRowMods ,
                                NULL AS HistogramSteps ,
                                NULL AS StatsLastUpdated ,
                                avg_fragmentation_in_percent as IndexFragInPercent,
                                1 AS Ordering ,
                                c.object_id ,
                                c.Index_Id
                    FROM     cteResults c
                                INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                            AND si.stats_id = c.Index_Id
                        UNION
                    SELECT   QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                'STATISTICS' ,
                                stats_name ,
                                StatsColumns ,
                                '' ,
                                '' AS FilterDefinition ,
                                '' AS Fill_Factor ,
                                '' AS DataCompression ,
                                '' AS IndexReads ,
                                '' AS IndexUpdates ,
                                '' AS SizeKB ,
                                StatsRows AS IndexRows ,
                                '' AS IndexLookups ,
                                '' AS MostRecentlyUsed ,
                                SampleRows AS StatsSampleRows ,
                                RowMods AS StatsRowMods ,
                                csi.HistogramSteps ,
                                csi.StatsLastUpdated ,
                                '' as IndexFragInPercent,
                                2 ,
                                csi.object_id ,
                                csi.stats_id
                    FROM     cteStatsInfo csi
                    INNER JOIN sys.tables tbl ON csi.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                                LEFT JOIN (SELECT si.object_id, si.stats_id
                                            FROM    cteResults c
                                            INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                                    AND si.stats_id = c.Index_Id ) AS x on csi.object_id = x.object_id and csi.stats_id = x.stats_id
                        WHERE x.object_id is null
                    )
            INSERT INTO @AllResults
            SELECT  row_number() OVER (ORDER BY FullObjectName) AS RowNum ,
                    FullObjectName ,
                    ISNULL(IndexType, 'STATISTICS') AS IndexType ,
                    IndexName ,
                    KeyColumns ,
                    ISNULL(IncludeColumns, '') AS IncludeColumns ,
                    FilterDefinition ,
                    [FillFactor] AS [FillFactor] ,
                    DataCompression ,
                    IndexReads ,
                    IndexUpdates ,
                    SizeKB ,
                    IndexRows ,
                    IndexLookups ,
                    MostRecentlyUsed ,
                    StatsSampleRows ,
                    StatsRowMods ,
                    HistogramSteps ,
                    StatsLastUpdated ,
                    IndexFragInPercent ,
                    object_id ,
                    index_id
            FROM    AllResults
                    $IncludeStatsPredicate
        OPTION  ( RECOMPILE );

        /* Only update the stats data on 2005 for a single table, otherwise the run time for this is a potential problem for large table/index volumes */
        if @TableName IS NOT NULL
        BEGIN

            DECLARE @StatsInfo2005 TABLE (Name nvarchar(128), Updated DATETIME, Rows BIGINT, RowsSampled BIGINT, Steps INT, Density INT, AverageKeyLength INT, StringIndex NVARCHAR(20))

            DECLARE @SqlCall NVARCHAR(2000), @RowNum INT;
            SELECT @RowNum = min(RowNum) FROM @AllResults;
            WHILE @RowNum IS NOT NULL
            BEGIN
                SELECT @SqlCall = 'dbcc show_statistics('+FullObjectName+', '+IndexName+') with stat_header' FROM @AllResults WHERE RowNum = @RowNum;
                INSERT INTO @StatsInfo2005 exec (@SqlCall);
                UPDATE @AllResults
                    SET StatsSampleRows = RowsSampled,
                    HistogramSteps = Steps,
                    StatsLastUpdated = Updated
                    FROM @StatsInfo2005
                    WHERE RowNum = @RowNum;
                DELETE FROM @StatsInfo2005
                SELECT @RowNum = min(RowNum) FROM @AllResults WHERE RowNum > @RowNum;
            END;

        END;

        UPDATE a
        SET a.StatsRowMods = i.rowmodctr
        FROM @AllResults a
            JOIN sys.sysindexes i ON a.object_id = i.id AND a.index_id = i.indid;

        SELECT	FullObjectName ,
                IndexType ,
                IndexName ,
                KeyColumns ,
                IncludeColumns ,
                FilterDefinition ,
                [FillFactor] ,
                DataCompression ,
                IndexReads ,
                IndexUpdates ,
                SizeKB ,
                IndexRows ,
                IndexLookups ,
                MostRecentlyUsed ,
                StatsSampleRows ,
                StatsRowMods ,
                HistogramSteps ,
                StatsLastUpdated ,
                IndexFragInPercent
        FROM @AllResults;"

        #endregion sizesQuery2005
    }
    process {
        Write-Message -Level Debug -Message $SizesQuery
        Write-Message -Level Debug -Message $SizesQuery2005

        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $InputObject += Get-DbaDatabase -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            #Need to check the version of SQL
            if ($server.versionMajor -ge 10) {
                $indexesQuery = $SizesQuery
            } else {
                $indexesQuery = $SizesQuery2005
            }

            if (!$db.IsAccessible) {
                Stop-Function -Message "$db is not accessible. Skipping." -Continue
            }

            Write-Message -Level Debug -Message "$indexesQuery"
            try {
                $IndexDetails = $db.Query($indexesQuery)

                if (!$Raw) {
                    foreach ($detail in $IndexDetails) {
                        $recentlyused = [datetime]$detail.MostRecentlyUsed

                        if ($recentlyused.year -eq 1900) {
                            $recentlyused = $null
                        }

                        [pscustomobject]@{
                            ComputerName       = $server.ComputerName
                            InstanceName       = $server.ServiceName
                            SqlInstance        = $server.DomainInstanceName
                            Database           = $db.Name
                            Object             = $detail.FullObjectName
                            Index              = $detail.IndexName
                            IndexType          = $detail.IndexType
                            Statistics         = $detail.StatisticsName
                            KeyColumns         = $detail.KeyColumns
                            IncludeColumns     = $detail.IncludeColumns
                            FilterDefinition   = $detail.FilterDefinition
                            DataCompression    = $detail.DataCompression
                            IndexReads         = "{0:N0}" -f $detail.IndexReads
                            IndexUpdates       = "{0:N0}" -f $detail.IndexUpdates
                            Size               = "{0:N0}" -f $detail.SizeKB
                            IndexRows          = "{0:N0}" -f $detail.IndexRows
                            IndexLookups       = "{0:N0}" -f $detail.IndexLookups
                            MostRecentlyUsed   = $recentlyused
                            StatsSampleRows    = "{0:N0}" -f $detail.StatsSampleRows
                            StatsRowMods       = "{0:N0}" -f $detail.StatsRowMods
                            HistogramSteps     = $detail.HistogramSteps
                            StatsLastUpdated   = $detail.StatsLastUpdated
                            IndexFragInPercent = "{0:F2}" -f $detail.IndexFragInPercent
                        }
                    }
                }

                else {
                    foreach ($detail in $IndexDetails) {
                        $recentlyused = [datetime]$detail.MostRecentlyUsed

                        if ($recentlyused.year -eq 1900) {
                            $recentlyused = $null
                        }

                        [pscustomobject]@{
                            ComputerName       = $server.ComputerName
                            InstanceName       = $server.ServiceName
                            SqlInstance        = $server.DomainInstanceName
                            Database           = $db.Name
                            Object             = $detail.FullObjectName
                            Index              = $detail.IndexName
                            IndexType          = $detail.IndexType
                            Statistics         = $detail.StatisticsName
                            KeyColumns         = $detail.KeyColumns
                            IncludeColumns     = $detail.IncludeColumns
                            FilterDefinition   = $detail.FilterDefinition
                            DataCompression    = $detail.DataCompression
                            IndexReads         = $detail.IndexReads
                            IndexUpdates       = $detail.IndexUpdates
                            Size               = [dbasize]($detail.SizeKB * 1024)
                            IndexRows          = $detail.IndexRows
                            IndexLookups       = $detail.IndexLookups
                            MostRecentlyUsed   = $recentlyused
                            StatsSampleRows    = $detail.StatsSampleRows
                            StatsRowMods       = $detail.StatsRowMods
                            HistogramSteps     = $detail.HistogramSteps
                            StatsLastUpdated   = $detail.StatsLastUpdated
                            IndexFragInPercent = $detail.IndexFragInPercent
                        }
                    }
                }
            } catch {
                Stop-Function -Continue -ErrorRecord $_ -Message "Cannot process $db on $server"
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUOIW+JwGSGq7tY4FjqCBM0v2B
# WGigghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFOdflCrpbk1XZTvtyBrgxGx7D4mIMA0GCSqGSIb3DQEBAQUABIIBAAeICNxH
# YzGvAtGG9hIzJFLXK7JAmE+FhnmCRX6ERCF497vaa80rzoZnP6QL7Of/tUQgkjkG
# Ht9FmoSxhZ23aFanCdPRhL/MWRkUWvc/FfZKGXF4icYiu6MQRzdv+m7W3RuY17d4
# oAmMYEqu6qoucrrXbk/dOgB6vLnAZFoJshg+zsRpiq0RD5/lRd/N8EhsVj/aELpl
# FEO3w9iYjgRjqwIH49j/5IjP6m3EpaM1QfLv8P3mYyh6zcdH5O8gGNAHEY3q3/HT
# DOMEZ3JbIwyWjhgMWdtmwS40Q/1uG6L0jowyj3mGJnzkjy8ELHvSBIL8yEBdZID9
# k5P+GOEfLjaGyBahggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkzNlowLwYJKoZIhvcNAQkEMSIEIPheRZ+R63HuXvKBe8vQvmP91zJR
# fW5gZJwlnD5ZE3qrMA0GCSqGSIb3DQEBAQUABIIBAG5qbW+VAk4Ka+tydRcv/3bf
# fJMh5QkHBgx1MYBoVkl+1RXwXgyjJcwnDMz5lmi6imzpe2w52PhyXvQTeHdGiqJZ
# k4w26iYjH61CkMcVjSua09l3FGzQaf29Hxl0YcLFS7dmNu+proOdyY2zEU4UzTqE
# ZARAX64Qpb97UmfE//Yhs3fyBVeUqL1P8eFPbPyBbtJc0sfMHnI67gB3l1gZYjJk
# 34gfGbO51pMoLg7Bk7kSUlkiQlo7bYozzeV+IHBXRNmWN3ysggwv5aqBav0et3Jm
# Hp8ywM8fzxRqKxeyu6+rLaYCSIKslWlT6QWsGXZb5pLV7fIOLRSPTKhLxvwP88Q=
# SIG # End signature block
