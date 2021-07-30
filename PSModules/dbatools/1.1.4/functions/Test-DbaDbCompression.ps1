function Test-DbaDbCompression {
    <#
    .SYNOPSIS
        Returns tables and indexes with preferred compression setting.
    .DESCRIPTION
        This function returns the results of a full table/index compression analysis and the estimated, best option to date for either NONE, Page, or Row Compression.

        Remember Uptime is critical, the longer uptime, the more accurate the analysis is, and it would be best if you utilized Get-DbaUptime first, before running this command.

        Test-DbaDbCompression script derived from GitHub and the Tiger Team's repository: (https://github.com/Microsoft/tigertoolbox/tree/master/Evaluate-Compression-Gains)
        In the output, you will find the following information:
        - Column Percent_Update shows the percentage of update operations on a specific table, index, or partition, relative to total operations on that object. The lower the percentage of Updates (that is, the table, index, or partition is infrequently updated), the better candidate it is for page compression.
        - Column Percent_Scan shows the percentage of scan operations on a table, index, or partition, relative to total operations on that object. The higher the value of Scan (that is, the table, index, or partition is mostly scanned), the better candidate it is for page compression.
        - Column Compression_Type_Recommendation can have four possible outputs indicating where there is most gain, if any: 'PAGE', 'ROW', 'NO_GAIN' or '?'. When the output is '?' this approach could not give a recommendation, so as a rule of thumb I would lean to ROW if the object suffers mainly UPDATES, or PAGE if mainly INSERTS, but this is where knowing your workload is essential. When the output is 'NO_GAIN' well, that means that according to sp_estimate_data_compression_savings no space gains will be attained when compressing, as in the above output example, where compressing would grow the affected object.

        This script will execute on the context of the current database.
        Also be aware that this may take a while to execute on large objects, because if the IS locks taken by the
        sp_estimate_data_compression_savings cannot be honored, the SP will be blocked.
        It only considers Row or Page Compression (not column compression)
        It only evaluates User Tables

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER Schema
        Filter to only get specific schemas If unspecified, all schemas will be processed.

    .PARAMETER Table
        Filter to only get specific tables If unspecified, all User tables will be processed.

    .PARAMETER ResultSize
        Allows you to limit the number of results returned, as some systems can have very large number of tables.  Default value is no restriction.

    .PARAMETER Rank
        Allows you to specify the field used for ranking when determining the ResultSize
        Can be either TotalPages, UsedPages or TotalRows with default of TotalPages. Only applies when ResultSize is used.

    .PARAMETER FilterBy
        Allows you to specify level of filtering when determining the ResultSize
        Can be at either Table, Index or Partition level with default of Partition. Only applies when ResultSize is used.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .INPUTS
        Accepts a DbaInstanceParameter. Any collection of SQL Server Instance names or SMO objects can be piped to command.

    .OUTPUTS
        Returns a PsCustomObject with following fields: ComputerName, InstanceName, SqlInstance, Database, IndexName, Partition, IndexID, PercentScan, PercentUpdate, RowEstimatePercentOriginal, PageEstimatePercentOriginal, CompressionTypeRecommendation, SizeCurrent, SizeRequested, PercentCompression

    .NOTES
        Tags: Compression, Table, Database
        Author: Jason Squires (@js_0505), jstexasdba@gmail.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaDbCompression

    .EXAMPLE
        PS C:\> Test-DbaDbCompression -SqlInstance localhost

        Returns results of all potential compression options for all databases for the default instance on the local host. Returns a recommendation of either Page, Row or NO_GAIN

    .EXAMPLE
        PS C:\> Test-DbaDbCompression -SqlInstance ServerA

        Returns results of all potential compression options for all databases on the instance ServerA

    .EXAMPLE
        PS C:\> Test-DbaDbCompression -SqlInstance ServerA -Database DBName | Out-GridView

        Returns results of all potential compression options for a single database DBName with the recommendation of either Page or Row or NO_GAIN in a nicely formatted GridView

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Test-DbaDbCompression -SqlInstance ServerA -ExcludeDatabase MyDatabase -SqlCredential $cred

        Returns results of all potential compression options for all databases except MyDatabase on instance ServerA using SQL credentials to authentication to ServerA.
        Returns the recommendation of either Page, Row or NO_GAIN

    .EXAMPLE
        PS C:\> Test-DbaDbCompression -SqlInstance ServerA -Schema Test -Table MyTable

        Returns results of all potential compression options for the Table Test.MyTable in instance ServerA on ServerA and ServerB.
        Returns the recommendation of either Page, Row or NO_GAIN.
        Returns a result for each partition of any Heap, Clustered or NonClustered index.

    .EXAMPLE
        PS C:\> Test-DbaDbCompression -SqlInstance ServerA, ServerB -ResultSize 10

        Returns results of all potential compression options for all databases on ServerA and ServerB.
        Returns the recommendation of either Page, Row or NO_GAIN.
        Returns results for the top 10 partitions by TotalPages used per database.

    .EXAMPLE
        PS C:\> ServerA | Test-DbaDbCompression -Schema Test -ResultSize 10 -Rank UsedPages -FilterBy Table

        Returns results of all potential compression options for all databases on ServerA containing a schema Test
        Returns results for the top 10 Tables by Used Pages per database.
        Results are split by Table, Index and Partition so more than 10 results may be returned.

    .EXAMPLE
        PS C:\> $servers = 'Server1','Server2'
        PS C:\> $servers | Test-DbaDbCompression -Database DBName | Out-GridView

        Returns results of all potential compression options for a single database DBName on Server1 or Server2
        Returns the recommendation of either Page, Row or NO_GAIN in a nicely formatted GridView

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Test-DbaDbCompression -SqlInstance ServerA -Database MyDB -SqlCredential $cred -Schema Test -Table Test1, Test2

        Returns results of all potential compression options for objects in Database MyDb on instance ServerA using SQL credentials to authentication to ServerA.
        Returns the recommendation of either Page, Row or NO_GAIN for tables with Schema Test and name in Test1 or Test2

    .EXAMPLE
        PS C:\> $servers = 'Server1','Server2'
        PS C:\> foreach ($svr in $servers) {
        >> Test-DbaDbCompression -SqlInstance $svr | Export-Csv -Path C:\temp\CompressionAnalysisPAC.csv -Append
        >> }

        This produces a full analysis of all your servers listed and is pushed to a csv for you to analyze.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Schema,
        [string[]]$Table,
        [int]$ResultSize,
        [ValidateSet('TotalPages', 'UsedPages', 'TotalRows')]
        [string]$Rank = 'TotalPages',
        [ValidateSet('Partition', 'Index', 'Table')]
        [string]$FilterBy = 'Partition',
        [switch]$EnableException
    )

    begin {
        Write-Message -Level System -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        if ($Schema) {
            $sqlSchemaWhere = "AND s.name IN ('$($Schema -join "','")')"
        }

        if ($Table) {
            $sqlTableWhere = "AND t.name IN ('$($Table -join "','")')"
        }

        if ($ResultSize) {
            $sqlOrderBy = switch ($Rank) {
                UsedPages { 'UsedSpaceKB' }
                TotalRows { 'RowCounts' }
                default { 'TotalSpaceKB' }
            }

            if ($FilterBy -eq 'Table') {
                $sqlJoinFiltered = 'AND t.TableName = tdc.TableName COLLATE DATABASE_DEFAULT'
                $indexSQL = '0 as [IndexID]'
                $partitionSQL = '0 AS [Partition]'
                $groupBySQL = 's.Name, t.Name'
            } elseif ($FilterBy -eq 'Index') {
                $sqlJoinFiltered = 'AND t.TableName = tdc.TableName COLLATE DATABASE_DEFAULT AND t.IndexID = tdc.IndexID'
                $indexSQL = 'i.index_id as [IndexID]'
                $partitionSQL = '0 AS [Partition]'
                $groupBySQL = 's.Name, t.Name, i.index_id'
            } else {
                $sqlJoinFiltered = 'AND t.TableName = tdc.TableName COLLATE DATABASE_DEFAULT AND t.IndexID = tdc.IndexID AND t.[Partition] = tdc.[Partition]'
                $indexSQL = 'i.index_id as [IndexID]'
                $partitionSQL = 'p.partition_number AS [Partition]'
                $groupBySQL = 's.Name, t.Name, i.index_id, p.partition_number'
            }

            $sqlRestrict = "-- remove tables not in Top N
                With TopN(SchemaName, TableName, IndexID, [Partition], RowCounts, TotalSpaceKB, UsedSpaceKB) as
                (
                    SELECT TOP $ResultSize
                        s.Name AS SchemaName,
                        t.NAME as TableName,
                        $indexSQL,
                        $partitionSQL,
                        SUM(p.rows) AS RowCounts,
                        SUM(a.total_pages) * 8 AS TotalSpaceKB,
                        SUM(a.used_pages) * 8 AS UsedSpaceKB
                    FROM
                        sys.tables t
                    INNER JOIN
                        sys.indexes i ON t.OBJECT_ID = i.object_id
                    INNER JOIN
                        sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
                    INNER JOIN
                        sys.allocation_units a ON p.partition_id = a.container_id
                    LEFT OUTER JOIN
                        sys.schemas s ON t.schema_id = s.schema_id
                    WHERE objectproperty(t.object_id, 'IsUserTable') = 1
                        AND p.data_compression_desc = 'NONE'
                        AND p.rows > 0
                        $sqlSchemaWhere
                        $sqlTableWhere
                    GROUP BY
                        $groupBySQL
                    ORDER BY
                        $sqlOrderBy Desc
                )
                DELETE tdc
                FROM ##TestDbaCompression tdc
                LEFT JOIN TopN t
                    ON t.SchemaName = tdc.[Schema] COLLATE DATABASE_DEFAULT
                    $sqlJoinFiltered
                WHERE t.IndexID IS NULL;"
        }
    }

    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failed to process Instance $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            $Server.ConnectionContext.StatementTimeout = 0
            $sqlVersion = $(Get-DbaBuild -SqlInstance $server).Build.Major

            $sqlVersionRestrictions = @()

            if ($sqlVersion -ge 12) {
                $sqlVersionRestrictions += "
            BEGIN
                -- remove memory optimized tables
                DELETE tdc
                FROM ##TestDbaCompression tdc
                INNER JOIN sys.tables t
                    ON SCHEMA_NAME(t.schema_id) = tdc.[Schema] COLLATE DATABASE_DEFAULT
                    AND t.name = tdc.TableName COLLATE DATABASE_DEFAULT
                WHERE t.is_memory_optimized = 1
            END"
            }
            if ($sqlVersion -ge 13) {
                $sqlVersionRestrictions += "
            BEGIN
                -- remove tables with encrypted columns
                DELETE tdc
                FROM ##TestDbaCompression tdc
                INNER JOIN sys.tables t
                    ON SCHEMA_NAME(t.schema_id) = tdc.[Schema] COLLATE DATABASE_DEFAULT
                    AND t.name = tdc.TableName COLLATE DATABASE_DEFAULT
                INNER JOIN sys.columns c
                    ON t.object_id = c.object_id
                WHERE encryption_type IS NOT NULL
            END"
            }
            if ($sqlVersion -ge 14) {
                $sqlVersionRestrictions += "
            BEGIN
                -- remove graph (node/edge) tables
                DELETE tdc
                FROM ##TestDbaCompression tdc
                INNER JOIN sys.tables t
                    ON tdc.[Schema] = SCHEMA_NAME(t.schema_id) COLLATE DATABASE_DEFAULT
                    AND tdc.TableName = t.name COLLATE DATABASE_DEFAULT
                WHERE (is_node = 1 OR is_edge = 1)
            END"
            }
            $sql = "SET NOCOUNT ON;

IF OBJECT_ID('tempdb..##TestDbaCompression', 'U') IS NOT NULL
    DROP TABLE ##TestDbaCompression

IF OBJECT_ID('tempdb..##tmpEstimateRow', 'U') IS NOT NULL
    DROP TABLE ##tmpEstimateRow

IF OBJECT_ID('tempdb..##tmpEstimatePage', 'U') IS NOT NULL
    DROP TABLE ##tmpEstimatePage

CREATE TABLE ##TestDbaCompression (
    [Schema] SYSNAME
    ,[TableName] SYSNAME
    ,[ObjectId] INT
    ,[IndexName] SYSNAME NULL
    ,[Partition] INT
    ,[IndexID] INT
    ,[IndexType] VARCHAR(25)
    ,[PercentScan] SMALLINT
    ,[PercentUpdate] SMALLINT
    ,[RowEstimatePercentOriginal] BIGINT
    ,[PageEstimatePercentOriginal] BIGINT
    ,[CompressionTypeRecommendation] VARCHAR(7)
    ,SizeCurrent BIGINT
    ,SizeRequested BIGINT
    ,PercentCompression NUMERIC(10, 2)
    );

CREATE TABLE ##tmpEstimateRow (
    objname SYSNAME
    ,schname SYSNAME
    ,indid INT
    ,partnr INT
    ,SizeCurrent BIGINT
    ,SizeRequested BIGINT
    ,SampleCurrent BIGINT
    ,SampleRequested BIGINT
    );

CREATE TABLE ##tmpEstimatePage (
    objname SYSNAME
    ,schname SYSNAME
    ,indid INT
    ,partnr INT
    ,SizeCurrent BIGINT
    ,SizeRequested BIGINT
    ,SampleCurrent BIGINT
    ,SampleRequested BIGINT
    );

INSERT INTO ##TestDbaCompression (
    [Schema]
    ,[TableName]
    ,[ObjectId]
    ,[IndexName]
    ,[Partition]
    ,[IndexID]
    ,[IndexType]
    ,[PercentScan]
    ,[PercentUpdate]
    )
    SELECT s.NAME AS [Schema]
    ,t.NAME AS [TableName]
    ,t.OBJECT_ID AS [OBJECTID]
    ,x.NAME AS [IndexName]
    ,p.partition_number AS [Partition]
    ,x.Index_ID AS [IndexID]
    ,x.type_desc AS [IndexType]
    ,NULL AS [PercentScan]
    ,NULL AS [PercentUpdate]
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.indexes x ON x.object_id = t.object_id
INNER JOIN sys.partitions p ON x.object_id = p.object_id
    AND x.Index_ID = p.Index_ID
WHERE OBJECTPROPERTY(t.object_id, 'IsUserTable') = 1
    AND p.data_compression_desc = 'NONE'
    AND p.rows > 0
    $sqlSchemaWhere
    $sqlTableWhere
ORDER BY [TableName] ASC;

$sqlRestrict

BEGIN
    -- remove any tables with sparse columns
    DELETE tdc
    FROM ##TestDbaCompression tdc
    INNER JOIN sys.columns c
        on tdc.ObjectId = c.object_id
    WHERE c. is_sparse = 1
END

$sqlVersionRestrictions

DECLARE @schema SYSNAME
    ,@tbname SYSNAME
    ,@ixid INT

DECLARE cur CURSOR FAST_FORWARD
FOR
SELECT [Schema]
    ,[TableName]
    ,[IndexID]
FROM ##TestDbaCompression

OPEN cur

FETCH NEXT
FROM cur
INTO @schema
    ,@tbname
    ,@ixid

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @sqlcmd NVARCHAR(500)

    SET @sqlcmd = 'EXEC sp_estimate_data_compression_savings ''' + @schema + ''', ''' + @tbname + ''', ''' + cast(@ixid AS VARCHAR) + ''', NULL, ''ROW''';

    INSERT INTO ##tmpEstimateRow (
        objname
        ,schname
        ,indid
        ,partnr
        ,SizeCurrent
        ,SizeRequested
        ,SampleCurrent
        ,SampleRequested
        )
    EXECUTE sp_executesql @sqlcmd

    SET @sqlcmd = 'EXEC sp_estimate_data_compression_savings ''' + @schema + ''', ''' + @tbname + ''', ''' + cast(@ixid AS VARCHAR) + ''', NULL, ''PAGE''';

    INSERT INTO ##tmpEstimatePage (
        objname
        ,schname
        ,indid
        ,partnr
        ,SizeCurrent
        ,SizeRequested
        ,SampleCurrent
        ,SampleRequested
        )
    EXECUTE sp_executesql @sqlcmd

    FETCH NEXT
    FROM cur
    INTO @schema
        ,@tbname
        ,@ixid
END

CLOSE cur

DEALLOCATE cur;

--Update usage and partition_number - If database was restore the sys.dm_db_index_operational_stats will be empty until tables have accesses. Executing the sp_estimate_data_compression_savings first will make those entries appear
UPDATE ##TestDbaCompression
SET
 [PercentScan] =
     case when (i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count) = 0 THEN 0
     ELSE i.range_scan_count * 100.0 / NULLIF((i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count), 0)
     END
 ,[PercentUpdate] =
    case when (i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count) = 0 THEN 0
    ELSE i.leaf_update_count * 100.0 / NULLIF((i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count), 0)
    END
FROM sys.dm_db_index_operational_stats(db_id(), NULL, NULL, NULL) i
INNER JOIN ##TestDbaCompression tmp
    ON tmp.ObjectId = i.object_id
    AND tmp.IndexID = i.index_id;


WITH tmp_cte (
    objname
    ,schname
    ,indid
    ,partnr
    ,pct_of_orig_row
    ,pct_of_orig_page
    ,SizeCurrent
    ,SizeRequested
    )
AS (
    SELECT tr.objname
        ,tr.schname
        ,tr.indid
        ,tr.partnr
        ,(tr.SampleRequested * 100) / CASE
            WHEN tr.SampleCurrent = 0
                THEN 1
            ELSE tr.SampleCurrent
            END AS pct_of_orig_row
        ,(tp.SampleRequested * 100) / CASE
            WHEN tp.SampleCurrent = 0
                THEN 1
            ELSE tp.SampleCurrent
            END AS pct_of_orig_page
        ,tr.SizeCurrent
        ,tr.SizeRequested
    FROM ##tmpEstimateRow tr
    INNER JOIN ##tmpEstimatePage tp ON tr.objname = tp.objname
        AND tr.schname = tp.schname
        AND tr.indid = tp.indid
        AND tr.partnr = tp.partnr
    )
UPDATE ##TestDbaCompression
SET [RowEstimatePercentOriginal] = tcte.pct_of_orig_row
    ,[PageEstimatePercentOriginal] = tcte.pct_of_orig_page
    ,SizeCurrent = tcte.SizeCurrent
    ,SizeRequested = tcte.SizeRequested
    ,PercentCompression = 100 - (cast(tcte.[SizeRequested] AS NUMERIC(21, 2)) * 100 / (tcte.[SizeCurrent] - ABS(SIGN(tcte.[SizeCurrent])) + 1))
FROM tmp_cte tcte
    ,##TestDbaCompression tcomp
WHERE tcte.objname = tcomp.TableName
    AND tcte.schname = tcomp.[Schema]
    AND tcte.indid = tcomp.IndexID
    AND tcte.partnr = tcomp.Partition;

WITH tmp_cte2 (
    TableName
    ,[Schema]
    ,IndexID
    ,[CompressionTypeRecommendation]
    )
AS (
    SELECT TableName
        ,[Schema]
        ,IndexID
        ,CASE
            WHEN [RowEstimatePercentOriginal] >= 100
                AND [PageEstimatePercentOriginal] >= 100
                THEN 'NO_GAIN'
            WHEN [PercentUpdate] >= 10
                THEN 'ROW'
            WHEN [PercentScan] <= 1
                AND [PercentUpdate] <= 1
                AND [RowEstimatePercentOriginal] < [PageEstimatePercentOriginal]
                THEN 'ROW'
            WHEN [PercentScan] <= 1
                AND [PercentUpdate] <= 1
                AND [RowEstimatePercentOriginal] > [PageEstimatePercentOriginal]
                THEN 'PAGE'
            WHEN [PercentScan] >= 60
                AND [PercentUpdate] <= 5
                THEN 'PAGE'
            WHEN [PercentScan] <= 35
                AND [PercentUpdate] <= 5
                THEN '?'
            ELSE 'ROW'
            END
    FROM ##TestDbaCompression
    )
UPDATE ##TestDbaCompression
SET [CompressionTypeRecommendation] = tcte2.[CompressionTypeRecommendation]
FROM tmp_cte2 tcte2
    ,##TestDbaCompression tcomp2
WHERE tcte2.TableName = tcomp2.TableName
    AND tcte2.[Schema] = tcomp2.[Schema]
    AND tcte2.IndexID = tcomp2.IndexID;

SET NOCOUNT ON;

SELECT DBName = DB_Name()
    ,[Schema]
    ,[TableName]
    ,[IndexName]
    ,[Partition]
    ,[IndexID]
    ,[IndexType]
    ,[PercentScan]
    ,[PercentUpdate]
    ,[RowEstimatePercentOriginal]
    ,[PageEstimatePercentOriginal]
    ,[CompressionTypeRecommendation]
    ,SizeCurrentKB = [SizeCurrent]
    ,SizeRequestedKB = [SizeRequested]
    ,PercentCompression
FROM ##TestDbaCompression;

IF OBJECT_ID('tempdb..##TestDbaCompression', 'U') IS NOT NULL
    DROP TABLE ##TestDbaCompression

IF OBJECT_ID('tempdb..##tmpEstimateRow', 'U') IS NOT NULL
    DROP TABLE ##tmpEstimateRow

IF OBJECT_ID('tempdb..##tmpEstimatePage', 'U') IS NOT NULL
    DROP TABLE ##tmpEstimatePage;

"
            Write-Message -Level Debug -Message "SQL Statement: $sql"
            [long]$instanceVersionNumber = $($server.VersionString).Replace(".", "")


            #If SQL Server 2016 SP1 (13.0.4001.0) or higher every version supports compression.
            if ($server.EngineEdition -ne "EnterpriseOrDeveloper" -and $instanceVersionNumber -lt 13040010) {
                Stop-Function -Message "Compression before SQLServer 2016 SP1 (13.0.4001.0) is only supported by enterprise, developer or evaluation edition. $server has version $($server.VersionString) and edition is $($server.EngineEdition)." -Target $db -Continue
            }
            #Filter Database list
            try {
                $dbs = $server.Databases | Where-Object IsAccessible

                if ($Database) {
                    $dbs = $dbs | Where-Object { $Database -contains $_.Name -and $_.IsSystemObject -eq 0 }
                }

                else {
                    $dbs = $dbs | Where-Object { $_.IsSystemObject -eq 0 }
                }

                if (Test-Bound "ExcludeDatabase") {
                    $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
                }
            } catch {
                Stop-Function -Message "Unable to gather list of databases for $instance" -Target $instance -ErrorRecord $_ -Continue
            }

            foreach ($db in $dbs) {
                try {
                    $dbCompatibilityLevel = [int]($db.CompatibilityLevel.ToString().Replace('Version', ''))

                    Write-Message -Level Verbose -Message "Querying $instance - $db"
                    if ($db.status -ne 'Normal' -or $db.IsAccessible -eq $false) {
                        Write-Message -Level Warning -Message "$db is not accessible." -Target $db
                        Continue
                    }

                    if ($dbCompatibilityLevel -lt 100) {
                        Stop-Function -Message "$db has a compatibility level lower than Version100 and will be skipped." -Target $db -Continue
                        Continue
                    }
                    #Execute query against individual database and add to output
                    foreach ($row in ($server.Query($sql, $db.Name))) {
                        [PSCustomObject]@{
                            ComputerName                  = $server.ComputerName
                            InstanceName                  = $server.ServiceName
                            SqlInstance                   = $server.DomainInstanceName
                            Database                      = $row.DBName
                            Schema                        = $row.Schema
                            TableName                     = $row.TableName
                            IndexName                     = $row.IndexName
                            Partition                     = $row.Partition
                            IndexID                       = $row.IndexID
                            IndexType                     = $row.IndexType
                            PercentScan                   = $row.PercentScan
                            PercentUpdate                 = $row.PercentUpdate
                            RowEstimatePercentOriginal    = $row.RowEstimatePercentOriginal
                            PageEstimatePercentOriginal   = $row.PageEstimatePercentOriginal
                            CompressionTypeRecommendation = $row.CompressionTypeRecommendation
                            SizeCurrent                   = [DbaSize]($row.SizeCurrentKB * 1024)
                            SizeRequested                 = [DbaSize]($row.SizeRequestedKB * 1024)
                            PercentCompression            = $row.PercentCompression
                        }
                    }
                } catch {
                    Stop-Function -Message "Unable to query $instance - $db" -Target $db -ErrorRecord $_ -Continue
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU78Ecd/bN2LLS874Z0RQnssEp
# qoCgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFBvbygoLLO7wO/FlKssgQMUhNVvKMA0GCSqGSIb3DQEBAQUABIIBAGkl46KL
# Um2mOl+9cYEYg82C3Y5sLnY47lzfiO2uSxeuz3lrS92no2icoCAncSaYct2st2s2
# gXxPc+6ecX6iflExSDqEkPAB3tLEB+Nrnm9nY2FaWH+nwYhrUbeqfRyARx0qHGUy
# 0/BPgzeE31/hRaQYmcgIcnkB9vXutgu/OR/WUyUKgryuTWm849gM+GTnOC4gkDqf
# u2c8uQ8cfD0fx8km1uJSR5tXjeJLmZyqe6pC9m7x/DElJgzqnyMNrVOsSK1LNH4a
# ROyhUrrhQMXH4/mM9kpSs+kV+w0DX/WNVJz+QSL0VyHWbFyY+64yEjYyVDhr9T4m
# rShw+XcMNQPlVJahggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAxNFowLwYJKoZIhvcNAQkEMSIEINiS96mtzPMnI7HsEknR1b44UoKy
# yDANyhXZvh0c/7dAMA0GCSqGSIb3DQEBAQUABIIBAFYEXpfq0T/sY4ZFhKIKAiX9
# tOkSC8H9Z7jT42oMkWqLDvx4ls6opMudocMHoJlTzf2LinMmzg6BxcxPXpVk7AON
# GPpUF4O2RUVrvgqb1UogZI8FCZ6qiKW+onmEXjzdzhAKmH5At4noE5XBJboMUoNI
# JM+SA7NqV6hE537Ykx/U1SvSWj9aQ6HvMrO5xUQDbmHbLOkvmTZnP+I33/v2/NLL
# W7CtetoPgbO9IKRx0QYtoL4zMXe4Iu10wq2Li6PImXwB+z4f+1tT6lm3LVPR3/en
# 9EvIkutaRqyUd/NVRCBntCFlcySn1Lka0bUgi0LFodeuw/P8C4Df6uKE2rQZrV8=
# SIG # End signature block
