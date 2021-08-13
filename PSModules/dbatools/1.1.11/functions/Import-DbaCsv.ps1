function Import-DbaCsv {
    <#
    .SYNOPSIS
        Efficiently imports very large (and small) CSV files into SQL Server.

    .DESCRIPTION
        Import-DbaCsv takes advantage of .NET's super fast SqlBulkCopy class to import CSV files into SQL Server.

        The entire import is performed within a transaction, so if a failure occurs or the script is aborted, no changes will persist.

        If the table or view specified does not exist and -AutoCreateTable, it will be automatically created using slow and inefficient but accommodating data types.

        This importer supports fields spanning multiple lines. The only restriction is that they must be quoted, otherwise it would not be possible to distinguish between malformed data and multi-line values.

    .PARAMETER Path
        Specifies path to the CSV file(s) to be imported. Multiple files may be imported at once.

    .PARAMETER NoHeaderRow
        By default, the first row is used to determine column names for the data being imported.

        Use this switch if the first row contains data and not column names.

    .PARAMETER Delimiter
        Specifies the delimiter used in the imported file(s). If no delimiter is specified, comma is assumed.

        Valid delimiters are '`t`, '|', ';',' ' and ',' (tab, pipe, semicolon, space, and comma).

    .PARAMETER SingleColumn
        Specifies that the file contains a single column of data. Otherwise, the delimiter check bombs.

    .PARAMETER SqlInstance
        The SQL Server Instance to import data into.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the name of the database the CSV will be imported into. Options for this this parameter are  auto-populated from the server.

    .PARAMETER Schema
        Specifies the schema in which the SQL table or view where CSV will be imported into resides. Default is dbo.

        If a schema does not currently exist, it will be created, after a prompt to confirm this. Authorization will be set to dbo by default.

        This parameter overrides -UseFileNameForSchema.

    .PARAMETER Table
        Specifies the SQL table or view where CSV will be imported into.

        If a table name is not specified, the table name will be automatically determined from the filename.

        If the table specified does not exist and -AutoCreateTable, it will be automatically created using slow and inefficient but accommodating data types.

        If the automatically generated table datatypes do not work for you, please create the table prior to import.

        If you want to import specific columns from a CSV, create a view with corresponding columns.

    .PARAMETER Column
        Import only specific columns. To remap column names, use the ColumnMap.

    .PARAMETER ColumnMap
        By default, the bulk copy tries to automap columns. When it doesn't work as desired, this parameter will help. Check out the examples for more information.

    .PARAMETER KeepOrdinalOrder
        By default, the importer will attempt to map exact-match columns names from the source document to the target table. Using this parameter will keep the ordinal order instead.

    .PARAMETER AutoCreateTable
        Creates a table if it does not already exist. The table will be created with sub-optimal data types such as nvarchar(max)

    .PARAMETER Truncate
        If this switch is enabled, the destination table will be truncated prior to import.

    .PARAMETER NotifyAfter
        Specifies the import row count interval for reporting progress. A notification will be shown after each group of this many rows has been imported.

    .PARAMETER BatchSize
        Specifies the batch size for the import. Defaults to 50000.

    .PARAMETER UseFileNameForSchema
        If this switch is enabled, the script will try to find the schema name in the input file by looking for a period (.) in the file name.

        If used with the -Table parameter you may still specify the target table name. If -Table is not used the file name after the first period will
        be used for the table name.

        For example test.data.csv will import the csv contents to a table in the test schema.

        If it finds one it will use the file name up to the first period as the schema. If there is no period in the filename it will default to dbo.

        If a schema does not currently exist, it will be created, after a prompt to confirm this. Authorization will be set to dbo by default.

        This behaviour will be overridden if the -Schema parameter is specified.

    .PARAMETER TableLock
        If this switch is enabled, the SqlBulkCopy option to acquire a table lock will be used.

        Per Microsoft "Obtain a bulk update lock for the duration of the bulk copy operation. When not
        specified, row locks are used."

    .PARAMETER CheckConstraints
        If this switch is enabled, the SqlBulkCopy option to check constraints will be used.

        Per Microsoft "Check constraints while data is being inserted. By default, constraints are not checked."

    .PARAMETER FireTriggers
        If this switch is enabled, the SqlBulkCopy option to allow insert triggers to be executed will be used.

        Per Microsoft "When specified, cause the server to fire the insert triggers for the rows being inserted into the database."

    .PARAMETER KeepIdentity
        If this switch is enabled, the SqlBulkCopy option to keep identity values from the source will be used.

        Per Microsoft "Preserve source identity values. When not specified, identity values are assigned by the destination."

    .PARAMETER KeepNulls
        If this switch is enabled, the SqlBulkCopy option to keep NULL values in the table will be used.

        Per Microsoft "Preserve null values in the destination table regardless of the settings for default values. When not specified, null values are replaced by default values where applicable."

    .PARAMETER NoProgress
        The progress bar is pretty but can slow down imports. Use this parameter to quietly import.

    .PARAMETER Quote
        Defines the default quote character wrapping every field.
        Default: double-quotes

    .PARAMETER Escape
        Defines the default escape character letting insert quotation characters inside a quoted field.

        The escape character can be the same as the quote character.
        Default: double-quotes

    .PARAMETER Comment
        Defines the default comment character indicating that a line is commented out.
        Default: hashtag

    .PARAMETER TrimmingOption
        Determines which values should be trimmed. Default is "None". Options are All, None, UnquotedOnly and QuotedOnly.

    .PARAMETER BufferSize
        Defines the default buffer size. The default BufferSize is 4096.

    .PARAMETER ParseErrorAction
        By default, the parse error action throws an exception and ends the import.

        You can also choose AdvanceToNextLine which basically ignores parse errors.

    .PARAMETER Encoding
        By default, set to UTF-8.

        The encoding of the file.

    .PARAMETER NullValue
        The value which denotes a DbNull-value.

    .PARAMETER MaxQuotedFieldLength
        The maxmimum length (in bytes) for any quoted field.

    .PARAMETER SkipEmptyLine
        Skip empty lines.

    .PARAMETER SupportsMultiline
        Indicates if the importer should support multiline fields.

    .PARAMETER UseColumnDefault
        Use the column default values if the field is not in the record.

    .PARAMETER NoTransaction
        Do not use a transaction when performing the import.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Import
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Import-DbaCsv

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\housing.csv -SqlInstance sql001 -Database markets

        Imports the entire comma-delimited housing.csv to the SQL "markets" database on a SQL Server named sql001, using the first row as column names.

        Since a table name was not specified, the table name is automatically determined from filename as "housing".

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path .\housing.csv -SqlInstance sql001 -Database markets -Table housing -Delimiter "`t" -NoHeaderRow

        Imports the entire tab-delimited housing.csv, including the first row which is not used for colum names, to the SQL markets database, into the housing table, on a SQL Server named sql001.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\huge.txt -SqlInstance sqlcluster -Database locations -Table latitudes -Delimiter "|"

        Imports the entire pipe-delimited huge.txt to the locations database, into the latitudes table on a SQL Server named sqlcluster.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path c:\temp\SingleColumn.csv -SqlInstance sql001 -Database markets -Table TempTable -SingleColumn

        Imports the single column CSV into TempTable

    .EXAMPLE
        PS C:\> Get-ChildItem -Path \\FileServer\csvs | Import-DbaCsv -SqlInstance sql001, sql002 -Database tempdb -AutoCreateTable

        Imports every CSV in the \\FileServer\csvs path into both sql001 and sql002's tempdb database. Each CSV will be imported into an automatically determined table name.

    .EXAMPLE
        PS C:\> Get-ChildItem -Path \\FileServer\csvs | Import-DbaCsv -SqlInstance sql001, sql002 -Database tempdb -AutoCreateTable -WhatIf

        Shows what would happen if the command were to be executed

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path c:\temp\dataset.csv -SqlInstance sql2016 -Database tempdb -Column Name, Address, Mobile

        Import only Name, Address and Mobile even if other columns exist. All other columns are ignored and therefore null or default values.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\schema.data.csv -SqlInstance sql2016 -database tempdb -UseFileNameForSchema

        Will import the contents of C:\temp\schema.data.csv to table 'data' in schema 'schema'.

    .EXAMPLE
        PS C:\> Import-DbaCsv -Path C:\temp\schema.data.csv -SqlInstance sql2016 -database tempdb -UseFileNameForSchema -Table testtable

        Will import the contents of C:\temp\schema.data.csv to table 'testtable' in schema 'schema'.

    .EXAMPLE
        PS C:\> $columns = @{
        >> Text = 'FirstName'
        >> Number = 'PhoneNumber'
        >> }
        PS C:\> Import-DbaCsv -Path c:\temp\supersmall.csv -SqlInstance sql2016 -Database tempdb -ColumnMap $columns

        The CSV column 'Text' is inserted into SQL column 'FirstName' and CSV column Number is inserted into the SQL Column 'PhoneNumber'. All other columns are ignored and therefore null or default values.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [Alias("Csv", "FullPath")]
        [object[]]$Path,
        [Parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [pscredential]$SqlCredential,
        [Parameter(Mandatory)]
        [string]$Database,
        [string]$Table,
        [string]$Schema,
        [switch]$Truncate,
        [char]$Delimiter = ",",
        [switch]$SingleColumn,
        [int]$BatchSize = 50000,
        [int]$NotifyAfter = 50000,
        [switch]$TableLock,
        [switch]$CheckConstraints,
        [switch]$FireTriggers,
        [switch]$KeepIdentity,
        [switch]$KeepNulls,
        [string[]]$Column,
        [hashtable]$ColumnMap,
        [switch]$KeepOrdinalOrder,
        [switch]$AutoCreateTable,
        [switch]$NoProgress,
        [switch]$NoHeaderRow,
        [switch]$UseFileNameForSchema,
        [char]$Quote = '"',
        [char]$Escape = '"',
        [char]$Comment = '#',
        [ValidateSet('All', 'None', 'UnquotedOnly', 'QuotedOnly')]
        [string]$TrimmingOption = "None",
        [int]$BufferSize = 4096,
        [ValidateSet('AdvanceToNextLine', 'ThrowException')]
        [string]$ParseErrorAction = 'ThrowException',
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [string]$NullValue,
        [int]$MaxQuotedFieldLength,
        [switch]$SkipEmptyLine,
        [switch]$SupportsMultiline,
        [switch]$UseColumnDefault,
        [switch]$NoTransaction,
        [switch]$EnableException
    )
    begin {
        $FirstRowHeader = $NoHeaderRow -eq $false
        $scriptelapsed = [System.Diagnostics.Stopwatch]::StartNew()

        if ($PSBoundParameters.UseFileNameForSchema -and $PSBoundParameters.Schema) {
            Write-Message -Level Warning -Message "Schema and UseFileNameForSchema parameters both specified. UseSchemaInFileName will be ignored."
        }

        try {
            # SilentContinue isn't enough
            Add-Type -Path "$script:PSModuleRoot\bin\csv\LumenWorks.Framework.IO.dll" -ErrorAction Stop
        } catch {
            $null = 1
        }

        function New-SqlTable {
            <#
                .SYNOPSIS
                    Creates new Table using existing SqlCommand.

                    SQL datatypes based on best guess of column data within the -ColumnText parameter.
                    Columns parameter determine column names.

                .EXAMPLE
                    New-SqlTable -Path $Path -Delimiter $Delimiter -Columns $columns -ColumnText $columntext -SqlConn $sqlconn -Transaction $transaction

                .OUTPUTS
                    Creates new table
            #>
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            param (
                [Parameter(Mandatory)]
                [string]$Path,
                [Parameter(Mandatory)]
                [string]$Delimiter,
                [Parameter(Mandatory)]
                [bool]$FirstRowHeader,
                [Microsoft.Data.SqlClient.SqlConnection]$sqlconn,
                [Microsoft.Data.SqlClient.SqlTransaction]$transaction
            )
            $reader = New-Object LumenWorks.Framework.IO.Csv.CsvReader(
                (New-Object System.IO.StreamReader($Path, [System.Text.Encoding]::$Encoding)),
                $FirstRowHeader,
                $Delimiter,
                $Quote,
                $Escape,
                $Comment,
                [LumenWorks.Framework.IO.Csv.ValueTrimmingOptions]::$TrimmingOption,
                $BufferSize,
                $NullValue
            )
            $columns = $reader.GetFieldHeaders()
            $reader.Close()
            $reader.Dispose()

            # Get SQL datatypes by best guess on first data row
            $sqldatatypes = @();

            foreach ($column in $Columns) {
                $sqldatatypes += "[$column] varchar(MAX)"
            }

            $sql = "BEGIN CREATE TABLE [$schema].[$table] ($($sqldatatypes -join ' NULL,')) END"
            $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)

            try {
                $null = $sqlcmd.ExecuteNonQuery()
            } catch {
                $errormessage = $_.Exception.Message.ToString()
                Stop-Function -Continue -Message "Failed to execute $sql. `nDid you specify the proper delimiter? `n$errormessage"
            }

            Write-Message -Level Verbose -Message "Successfully created table $schema.$table with the following column definitions:`n $($sqldatatypes -join "`n ")"
            # Write-Message -Level Warning -Message "All columns are created using a best guess, and use their maximum datatype."
            Write-Message -Level Verbose -Message "This is inefficient but allows the script to import without issues."
            Write-Message -Level Verbose -Message "Consider creating the table first using best practices if the data will be used in production."
        }

        Write-Message -Level Verbose -Message "Started at $(Get-Date)"
    }
    process {
        foreach ($filename in $Path) {

            if ($filename.FullName) {
                $filename = $filename.FullName
            }

            if (-not (Test-Path -Path $filename)) {
                Stop-Function -Continue -Message "$filename cannot be found"
            }

            $file = (Resolve-Path -Path $filename).ProviderPath

            # Does the second line contain the specified delimiter?
            try {
                $firstlines = Get-Content -Path $file -TotalCount 2 -ErrorAction Stop
            } catch {
                Stop-Function -Continue -Message "Failure reading $file" -ErrorRecord $_
            }
            if (-not $SingleColumn) {
                if ($firstlines -notmatch $Delimiter) {
                    Stop-Function -Message "Delimiter ($Delimiter) not found in first few rows of $file. If this is a single column import, please specify -SingleColumn"
                    return
                }
            }

            # Automatically generate Table name if not specified
            if (-not $PSBoundParameters.Table) {
                $filename = [IO.Path]::GetFileNameWithoutExtension($file)

                if ($filename.IndexOf('.') -ne -1) { $periodFound = $true }

                if ($UseFileNameForSchema -and $periodFound -and -not $PSBoundParameters.Schema) {
                    $table = $filename.Remove(0, $filename.IndexOf('.') + 1)
                    Write-Message -Level Verbose -Message "Table name not specified, using $table from file name"
                } else {
                    $table = [IO.Path]::GetFileNameWithoutExtension($file)
                    Write-Message -Level Verbose -Message "Table name not specified, using $table"
                }
            }

            # Use dbo as schema name if not specified in parms, or as first string before a period in filename
            if (-not ($PSBoundParameters.Schema)) {
                if ($UseFileNameForSchema) {
                    $filename = [IO.Path]::GetFileNameWithoutExtension($file)
                    if ($filename.IndexOf('.') -eq -1) {
                        $schema = "dbo"
                        Write-Message -Level Verbose -Message "Schema not specified, and not found in file name, using dbo"
                    } else {
                        $schema = $filename.SubString(0, $filename.IndexOf('.'))
                        Write-Message -Level Verbose -Message "Schema detected in filename, using $schema"
                    }
                } else {
                    $schema = 'dbo'
                    Write-Message -Level Verbose -Message "Schema not specified, using dbo"
                }
            }

            foreach ($instance in $SqlInstance) {
                $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
                # Open Connection to SQL Server
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -StatementTimeout 0 -MinimumVersion 9

                    # boundary case: ensure the correct db is referenced in the $server object
                    if ($Database -ne $server.ConnectionContext.CurrentDatabase) {
                        Stop-Function -Message "The SqlInstance object for $instance is currently connected to the database `"$($server.ConnectionContext.CurrentDatabase)`" and does not match the parameter `"-Database $Database`". If a pre-connected SqlInstance object is passed in it must be connected to the database specified by the -Database parameter."
                        return
                    }

                    $sqlconn = $server.ConnectionContext.SqlConnectionObject
                    if ($sqlconn.State -ne 'Open') {
                        $sqlconn.Open()
                    }
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                if (-not $NoTransaction) {
                    if ($PSCmdlet.ShouldProcess($instance, "Starting transaction in $Database")) {
                        # Everything will be contained within 1 transaction, even creating a new table if required
                        # and truncating the table, if specified.
                        $transaction = $sqlconn.BeginTransaction()
                    }
                }

                # Ensure Schema exists
                $sql = "select count(*) from [$Database].sys.schemas where name='$schema'"
                $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)

                # If Schema doesn't exist create it
                # Defaulting to dbo.
                if (($sqlcmd.ExecuteScalar()) -eq 0) {
                    if (-not $AutoCreateTable) {
                        Stop-Function -Continue -Message "Schema $Schema does not exist and AutoCreateTable was not specified"
                    }
                    $sql = "CREATE SCHEMA [$schema] AUTHORIZATION dbo"
                    if ($PSCmdlet.ShouldProcess($instance, "Creating schema $schema")) {
                        $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)
                        try {
                            $null = $sqlcmd.ExecuteNonQuery()
                        } catch {
                            Stop-Function -Continue -Message "Could not create $schema" -ErrorRecord $_
                        }
                    }
                }

                # Ensure table or view exists
                $sql = "select count(*) from [$Database].sys.tables where name = '$table' and schema_id=schema_id('$schema')"
                $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)

                $sql2 = "select count(*) from [$Database].sys.views where name = '$table' and schema_id=schema_id('$schema')"
                $sqlcmd2 = New-Object Microsoft.Data.SqlClient.SqlCommand($sql2, $sqlconn, $transaction)

                # Create the table if required. Remember, this will occur within a transaction, so if the script fails, the
                # new table will no longer exist.
                if (($sqlcmd.ExecuteScalar()) -eq 0 -and ($sqlcmd2.ExecuteScalar()) -eq 0) {
                    if (-not $AutoCreateTable) {
                        Stop-Function -Continue -Message "Table or view $table does not exist and AutoCreateTable was not specified"
                    }
                    Write-Message -Level Verbose -Message "Table does not exist"
                    if ($PSCmdlet.ShouldProcess($instance, "Creating table $table")) {
                        try {
                            New-SqlTable -Path $file -Delimiter $Delimiter -FirstRowHeader $FirstRowHeader -SqlConn $sqlconn -Transaction $transaction
                        } catch {
                            Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                        }
                    }
                } else {
                    Write-Message -Level Verbose -Message "Table exists"
                }

                # Truncate if specified. Remember, this will occur within a transaction, so if the script fails, the
                # truncate will not be committed.
                if ($Truncate) {
                    $sql = "TRUNCATE TABLE [$schema].[$table]"
                    if ($PSCmdlet.ShouldProcess($instance, "Performing TRUNCATE TABLE [$schema].[$table] on $Database")) {
                        $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($sql, $sqlconn, $transaction)
                        try {
                            $null = $sqlcmd.ExecuteNonQuery()
                        } catch {
                            Stop-Function -Continue -Message "Could not truncate $schema.$table" -ErrorRecord $_
                        }
                    }
                }

                # Setup bulk copy
                Write-Message -Level Verbose -Message "Starting bulk copy for $(Split-Path $file -Leaf)"

                # Setup bulk copy options
                [int]$bulkCopyOptions = ([Microsoft.Data.SqlClient.SqlBulkCopyOptions]::Default)
                $options = "TableLock", "CheckConstraints", "FireTriggers", "KeepIdentity", "KeepNulls"
                foreach ($option in $options) {
                    $optionValue = Get-Variable $option -ValueOnly -ErrorAction SilentlyContinue
                    if ($optionValue -eq $true) {
                        $bulkCopyOptions += $([Microsoft.Data.SqlClient.SqlBulkCopyOptions]::$option).value__
                    }
                }

                if ($PSCmdlet.ShouldProcess($instance, "Performing import from $file")) {
                    try {
                        # Create SqlBulkCopy using default options, or options specified in command line.
                        if ($bulkCopyOptions) {
                            $bulkcopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy($sqlconn, $bulkCopyOptions, $transaction)
                        } else {
                            $bulkcopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy($sqlconn, ([Microsoft.Data.SqlClient.SqlBulkCopyOptions]::Default), $transaction)
                        }

                        $bulkcopy.DestinationTableName = "[$schema].[$table]"
                        $bulkcopy.BulkCopyTimeout = 0
                        $bulkCopy.BatchSize = $BatchSize
                        $bulkCopy.NotifyAfter = $NotifyAfter
                        $bulkCopy.EnableStreaming = $true

                        # If the first column has quotes, then we have to setup a column map
                        $quotematch = (Get-Content -Path $file -TotalCount 1 -ErrorAction Stop).ToString()

                        if ((-not $KeepOrdinalOrder -and -not $AutoCreateTable) -or ($quotematch -match "'" -or $quotematch -match '"')) {
                            if ($ColumnMap) {
                                Write-Message -Level Verbose -Message "ColumnMap was supplied. Additional auto-mapping will not be attempted."
                            } else {
                                try {
                                    $ColumnMap = @{ }
                                    $firstline = Get-Content -Path $file -TotalCount 1 -ErrorAction Stop
                                    $firstline -split $Delimiter | ForEach-Object {
                                        $trimmed = $PSItem.Trim('"')
                                        Write-Message -Level Verbose -Message "Adding $trimmed to ColumnMap"
                                        $ColumnMap.Add($trimmed, $trimmed)
                                    }
                                } catch {
                                    # oh well, we tried
                                    Write-Message -Level Verbose -Message "Couldn't auto create ColumnMap :("
                                    $ColumnMap = $null
                                }
                            }
                        }

                        if ($ColumnMap) {
                            foreach ($columnname in $ColumnMap) {
                                foreach ($key in $columnname.Keys) {
                                    $null = $bulkcopy.ColumnMappings.Add($key, $columnname[$key])
                                }
                            }
                        }

                        if ($Column) {
                            foreach ($columnname in $Column) {
                                $null = $bulkcopy.ColumnMappings.Add($columnname, $columnname)
                            }
                        }
                    } catch {
                        Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                    }

                    # Write to server :D
                    try {
                        $reader = New-Object LumenWorks.Framework.IO.Csv.CsvReader(
                            (New-Object System.IO.StreamReader($file, [System.Text.Encoding]::$Encoding)),
                            $FirstRowHeader,
                            $Delimiter,
                            $Quote,
                            $Escape,
                            $Comment,
                            [LumenWorks.Framework.IO.Csv.ValueTrimmingOptions]::$TrimmingOption,
                            $BufferSize,
                            $NullValue
                        )

                        if ($PSBoundParameters.MaxQuotedFieldLength) {
                            $reader.MaxQuotedFieldLength = $MaxQuotedFieldLength
                        }
                        if ($PSBoundParameters.SkipEmptyLine) {
                            $reader.SkipEmptyLines = $SkipEmptyLine
                        }
                        if ($PSBoundParameters.SupportsMultiline) {
                            $reader.SupportsMultiline = $SupportsMultiline
                        }
                        if ($PSBoundParameters.UseColumnDefault) {
                            $reader.UseColumnDefaults = $UseColumnDefault
                        }
                        if ($PSBoundParameters.ParseErrorAction) {
                            $reader.DefaultParseErrorAction = $ParseErrorAction
                        }

                        # The legacy bulk copy library uses a 4 byte integer to track the RowsCopied, so the only option is to use
                        # integer wrap so that copy operations of row counts greater than [int32]::MaxValue will report accurate numbers.
                        # See https://github.com/sqlcollaborative/dbatools/issues/6927 for more details
                        $script:prevRowsCopied = [int64]0
                        $script:totalRowsCopied = [int64]0

                        # Add rowcount output
                        $bulkCopy.Add_SqlRowsCopied( {
                                $script:totalRowsCopied += (Get-AdjustedTotalRowsCopied -ReportedRowsCopied $args[1].RowsCopied -PreviousRowsCopied $script:prevRowsCopied).NewRowCountAdded

                                $tstamp = $(Get-Date -format 'yyyyMMddHHmmss')
                                Write-Message -Level Verbose -Message "[$tstamp] The bulk copy library reported RowsCopied = $($args[1].RowsCopied). The previous RowsCopied = $($script:prevRowsCopied). The adjusted total rows copied = $($script:totalRowsCopied)"

                                if (-not $NoProgress) {
                                    $timetaken = [math]::Round($elapsed.Elapsed.TotalSeconds, 2)
                                    Write-ProgressHelper -StepNumber 1 -TotalSteps 2 -Activity "Importing from $file" -Message ([System.String]::Format("Progress: {0} rows in {2} seconds", $script:totalRowsCopied, $percent, $timetaken)) -ExcludePercent
                                }

                                # save the previous count of rows copied to be used on the next event notification
                                $script:prevRowsCopied = $args[1].RowsCopied
                            })

                        $bulkCopy.WriteToServer($reader)

                        $completed = $true
                    } catch {
                        $completed = $false

                        Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                    } finally {
                        try {
                            $reader.Close()
                            $reader.Dispose()
                        } catch {
                        }

                        if (-not $NoTransaction) {
                            if ($completed) {
                                try {
                                    $null = $transaction.Commit()
                                } catch {
                                }
                            } else {
                                try {
                                    $null = $transaction.Rollback()
                                } catch {
                                }
                            }
                        }

                        try {
                            $sqlconn.Close()
                            $sqlconn.Dispose()
                        } catch {
                        }

                        try {
                            $bulkCopy.Close()
                            $bulkcopy.Dispose()
                        } catch {
                        }

                        $finalRowCountReported = Get-BulkRowsCopiedCount $bulkCopy

                        $script:totalRowsCopied += (Get-AdjustedTotalRowsCopied -ReportedRowsCopied $finalRowCountReported -PreviousRowsCopied $script:prevRowsCopied).NewRowCountAdded

                        if ($completed) {
                            Write-Progress -id 1 -activity "Inserting $($script:totalRowsCopied) rows" -status "Complete" -Completed
                        } else {
                            Write-Progress -id 1 -activity "Inserting $($script:totalRowsCopied) rows" -status "Failed" -Completed
                        }
                    }
                }
                if ($PSCmdlet.ShouldProcess($instance, "Finalizing import")) {
                    if ($completed) {
                        # "Note: This count does not take into consideration the number of rows actually inserted when Ignore Duplicates is set to ON."
                        $rowsPerSec = [math]::Round($script:totalRowsCopied / $elapsed.ElapsedMilliseconds * 1000.0, 1)

                        Write-Message -Level Verbose -Message "$($script:totalRowsCopied) total rows copied"

                        [pscustomobject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.ServiceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $Database
                            Table         = $table
                            Schema        = $schema
                            RowsCopied    = $script:totalRowsCopied
                            Elapsed       = [prettytimespan]$elapsed.Elapsed
                            RowsPerSecond = $rowsPerSec
                            Path          = $file
                        }
                    } else {
                        Stop-Function -Message "Transaction rolled back. Was the proper delimiter specified? Is the first row the column name?" -ErrorRecord $_
                        return
                    }
                }
            }
        }
    }
    end {
        # Close everything just in case & ignore errors
        try {
            $null = $sqlconn.close(); $null = $sqlconn.Dispose();
            $null = $bulkCopy.close(); $bulkcopy.dispose();
            $null = $reader.close(); $null = $reader.dispose()
        } catch {
            #here to avoid an empty catch
            $null = 1
        }

        # Script is finished. Show elapsed time.
        $totaltime = [math]::Round($scriptelapsed.Elapsed.TotalSeconds, 2)
        Write-Message -Level Verbose -Message "Total Elapsed Time for everything: $totaltime seconds"
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUFBl+jdkpzGTMPGdugZGNQivd
# cGCgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFFbJlqsHHrd0JFO3to1iMkLi/1sTMA0GCSqGSIb3DQEBAQUABIIBAIrVX9oB
# vDuCuaOZ32az+IOR2lJgtoUmzl6WZxfvUAVpXyGq+BOAukaUtxTaPLgcZh3IDx62
# +dWGf+U5MH6dCNL7xbsikrk/FoEe+lwsKf+Em4aQeF1cRowCVBW8YK2DvFeLxYY+
# OeLr9Vcq4pXC5wNECHMXoz+rbYFMHv/0iCOi1g4gcfI204TcACTp8RhO/MBpv29X
# xC4FmbWIBGY7tpMzgBXiflfJT5LNsP91CAYHxZhnEgr/h8E/9iuddA3vHOEH+rHT
# eY4m52qAtDBDYC93vLKEEE4VBv8qjymo760fNMf8niy7KDRaMp24hZ+HWV+WK6aj
# DrIAeQ9PWf3TELmhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUzMlowLwYJKoZIhvcNAQkEMSIEIGhpJblXJqfpVh6o/yE36Qdgh+iJ
# JhldJrdyU9JsLlymMA0GCSqGSIb3DQEBAQUABIIBABapWohdRVRdGwM6cdy9TArr
# w+PdyW6MTP180ZXhhCOu05JaRG3z0JsNPt/LQKOeu6mQAJGFI3+3nLOXZaPehWO5
# ynYSMo3zB6JqP1t1z+8qHU3MUJ8rPCBQs4P6PxuFHVwyzG4RdIiApwVf6aWhM9ws
# n9jhrGT+xFHjGk2Nts3ND+FKU4JM55jjEP+gwq1A47aGUb6lmtX/M6lHqnR0pHmg
# XSvGwsJOAO//l+if3Kv6mbMKD4fMZnfk0vK3E+xUg82QRQ6R/kjdL2XpNlZBsmju
# X+IBlnUoiMdXtQJxCvoOc1aEHAPzK5dH/HuQFsZHYQ2bcGZ6qPssnuk4f/Z6aoA=
# SIG # End signature block
