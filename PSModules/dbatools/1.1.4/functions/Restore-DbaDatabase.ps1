function Restore-DbaDatabase {
    <#
    .SYNOPSIS
        Restores a SQL Server Database from a set of backup files

    .DESCRIPTION
        Upon being passed a list of potential backups files this command will scan the files, select those that contain SQL Server
        backup sets. It will then filter those files down to a set that can perform the requested restore, checking that we have a
        full restore chain to the point in time requested by the caller.

        The function defaults to working on a remote instance. This means that all paths passed in must be relative to the remote instance.
        XpDirTree will be used to perform the file scans

        Various means can be used to pass in a list of files to be considered. The default is to recursively scan the folder
        passed in.

    .PARAMETER SqlInstance
        The target SQL Server instance.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Path to SQL Server backup files.

        Paths passed in as strings will be scanned using the desired method, default is a recursive folder scan
        Accepts multiple paths separated by ','

        Or it can consist of FileInfo objects, such as the output of Get-ChildItem or Get-Item. This allows you to work with
        your own file structures as needed

    .PARAMETER DatabaseName
        Name to restore the database under.
        Only works with a single database restore. If multiple database are found in the provided paths then we will exit

    .PARAMETER DestinationDataDirectory
        Path to restore the SQL Server backups to on the target instance.
        If only this parameter is specified, then all database files (data and log) will be restored to this location

    .PARAMETER DestinationLogDirectory
        Path to restore the database log files to.
        This parameter can only be specified alongside DestinationDataDirectory.

    .PARAMETER DestinationFileStreamDirectory
        Path to restore FileStream data to
        This parameter can only be specified alongside DestinationDataDirectory

    .PARAMETER RestoreTime
        Specify a DateTime object to which you want the database restored to. Default is to the latest point  available in the specified backups

    .PARAMETER NoRecovery
        Indicates if the databases should be recovered after last restore. Default is to recover

    .PARAMETER WithReplace
        Switch indicated is the restore is allowed to replace an existing database.

    .PARAMETER XpDirTree
        Switch that indicated file scanning should be performed by the SQL Server instance using xp_dirtree
        This will scan recursively from the passed in path
        You must have sysadmin role membership on the instance for this to work.

    .PARAMETER OutputScriptOnly
        Switch indicates that ONLY T-SQL scripts should be generated, no restore takes place
        Due to the limitations of SMO, this switch cannot be combined with VeriyOnly, and a warning will be raised if it is.

    .PARAMETER VerifyOnly
        Switch indicate that restore should be verified.
        Due to the limitations of SMO, this switch cannot be combined with OutputScriptOnly, and a warning will be raised if it is.

    .PARAMETER MaintenanceSolutionBackup
        Switch to indicate the backup files are in a folder structure as created by Ola Hallengreen's maintenance scripts.
        This switch enables a faster check for suitable backups. Other options require all files to be read first to ensure we have an anchoring full backup. Because we can rely on specific locations for backups performed with OlaHallengren's backup solution, we can rely on file locations.

    .PARAMETER FileMapping
        A hashtable that can be used to move specific files to a location.
        `$FileMapping = @{'DataFile1'='c:\restoredfiles\Datafile1.mdf';'DataFile3'='d:\DataFile3.mdf'}`
        And files not specified in the mapping will be restored to their original location
        This Parameter is exclusive with DestinationDataDirectory

    .PARAMETER IgnoreLogBackup
        This switch tells the function to ignore transaction log backups. The process will restore to the latest full or differential backup point only

    .PARAMETER IgnoreDiffBackup
        This switch tells the function to ignore differential backups. The process will restore to the latest full and onwards with transaction log backups only

    .PARAMETER UseDestinationDefaultDirectories
        Switch that tells the restore to use the default Data and Log locations on the target server. If they don't exist, the function will try to create them

    .PARAMETER ReuseSourceFolderStructure
        By default, databases will be migrated to the destination Sql Server's default data and log directories. You can override this by specifying -ReuseSourceFolderStructure.
        The same structure on the SOURCE will be kept exactly, so consider this if you're migrating between different versions and use part of Microsoft's default Sql structure (MSSql12.INSTANCE, etc)

        *Note, to reuse destination folder structure, specify -WithReplace

    .PARAMETER DestinationFilePrefix
        This value will be prefixed to ALL restored files (log and data). This is just a simple string prefix. If you want to perform more complex rename operations then please use the FileMapping parameter

        This will apply to all file move options, except for FileMapping

    .PARAMETER DestinationFileSuffix
        This value will be suffixed to ALL restored files (log and data). This is just a simple string suffix. If you want to perform more complex rename operations then please use the FileMapping parameter

        This will apply to all file move options, except for FileMapping

    .PARAMETER RestoredDatabaseNamePrefix
        A string which will be prefixed to the start of the restore Database's Name
        Useful if restoring a copy to the same sql server for testing.

    .PARAMETER TrustDbBackupHistory
        This switch can be used when piping the output of Get-DbaDbBackupHistory or Backup-DbaDatabase into this command.
        It allows the user to say that they trust that the output from those commands is correct, and skips the file header read portion of the process. This means a faster process, but at the risk of not knowing till halfway through the restore that something is wrong with a file.

    .PARAMETER MaxTransferSize
        Parameter to set the unit of transfer. Values must be a multiple by 64kb

    .PARAMETER Blocksize
        Specifies the block size to use. Must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb or 64kb
        Can be specified in bytes
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

    .PARAMETER BufferCount
        Number of I/O buffers to use to perform the operation.
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

    .PARAMETER NoXpDirRecurse
        If specified, prevents the XpDirTree process from recursing (its default behaviour)

    .PARAMETER DirectoryRecurse
        If specified the specified directory will be recursed into (overriding the default behaviour)

    .PARAMETER Continue
        If specified we will to attempt to recover more transaction log backups onto  database(s) in Recovering or Standby states
        When specified, WithReplace will be set to true

    .PARAMETER ExecuteAs
        If value provided the restore will be executed under this login's context. The login must exist, and have the relevant permissions to perform the restore

    .PARAMETER StandbyDirectory
        If a directory is specified the database(s) will be restored into a standby state, with the standby file placed into this directory (which must exist, and be writable by the target Sql Server instance)

    .PARAMETER AzureCredential
        The name of the SQL Server credential to be used if restoring from an Azure hosted backup using Storage Access Keys
        If a backup path beginning http is passed in and this parameter is not specified then if a credential with a name matching the URL

    .PARAMETER ReplaceDbNameInFile
        If switch set and occurrence of the original database's name in a data or log file will be replace with the name specified in the DatabaseName parameter

    .PARAMETER Recover
        If set will perform recovery on the indicated database

    .PARAMETER GetBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Get-DbaBackupInformation

    .PARAMETER SelectBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Select-DbaBackupInformation

    .PARAMETER FormatBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Format-DbaBackupInformation

    .PARAMETER TestBackupInformation
        Passing a string value into this parameter will cause a global variable to be created holding the output of Test-DbaBackupInformation

    .PARAMETER StopAfterGetBackupInformation
        Switch which will cause the function to exit after returning GetBackupInformation

    .PARAMETER StopAfterSelectBackupInformation
        Switch which will cause the function to exit after returning SelectBackupInformation

    .PARAMETER StopAfterFormatBackupInformation
        Switch which will cause the function to exit after returning FormatBackupInformation

    .PARAMETER StopAfterTestBackupInformation
        Switch which will cause the function to exit after returning TestBackupInformation

    .PARAMETER StatementTimeOut
        Timeout in minutes. Defaults to infinity (restores can take a while.)

    .PARAMETER KeepCDC
        Indicates whether CDC information should be restored as part of the database

    .PARAMETER KeepReplication
        Indicates whether replication configuration should be restored as part of the database restore operation

    .PARAMETER PageRestore
        Passes in an object from Get-DbaSuspectPages containing suspect pages from a single database.
        Setting this Parameter will cause an Online Page restore if the target Instance is Enterprise Edition, or offline if not.
        This will involve taking a tail log backup, so you must check your restore chain once it has completed

    .PARAMETER PageRestoreTailFolder
        This parameter passes in a location for the tail log backup required for page level restore

    .PARAMETER StopMark
        Marked point in the transaction log to stop the restore at (Mark is created via BEGIN TRANSACTION (https://docs.microsoft.com/en-us/sql/t-sql/language-elements/begin-transaction-transact-sql?view=sql-server-ver15))

    .PARAMETER StopBefore
        Switch to indicate the restore should stop before StopMark occurs, default is to stop when mark is created.

    .PARAMETER StopAfterDate
        By default the restore will stop at the first occurence of StopMark found in the chain, passing a datetime where will cause it to stop the first StopMark atfer that datetime


    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Restore-DbaDatabase

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups

        Scans all the backup files in \\server2\backups, filters them and restores the database to server1\instance1

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -MaintenanceSolutionBackup -DestinationDataDirectory c:\restores

        Scans all the backup files in \\server2\backups$ stored in an Ola Hallengren style folder structure,
        filters them and restores the database to the c:\restores folder on server1\instance1

    .EXAMPLE
        PS C:\> Get-ChildItem c:\SQLbackups1\, \\server\sqlbackups2 | Restore-DbaDatabase -SqlInstance server1\instance1

        Takes the provided files from multiple directories and restores them on  server1\instance1

    .EXAMPLE
        PS C:\> $RestoreTime = Get-Date('11:19 23/12/2016')
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -MaintenanceSolutionBackup -DestinationDataDirectory c:\restores -RestoreTime $RestoreTime

        Scans all the backup files in \\server2\backups stored in an Ola Hallengren style folder structure,
        filters them and restores the database to the c:\restores folder on server1\instance1 up to 11:19 23/12/2016

    .EXAMPLE
        PS C:\> $result = Restore-DbaDatabase -SqlInstance server1\instance1 -Path \\server2\backups -DestinationDataDirectory c:\restores -OutputScriptOnly
        PS C:\> $result | Out-File -Filepath c:\scripts\restore.sql

        Scans all the backup files in \\server2\backups, filters them and generate the T-SQL Scripts to restore the database to the latest point in time, and then stores the output in a file for later retrieval

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path c:\backups -DestinationDataDirectory c:\DataFiles -DestinationLogDirectory c:\LogFile

        Scans all the files in c:\backups and then restores them onto the SQL Server Instance server1\instance1, placing data files
        c:\DataFiles and all the log files into c:\LogFiles

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path http://demo.blob.core.windows.net/backups/dbbackup.bak -AzureCredential MyAzureCredential

        Will restore the backup held at  http://demo.blob.core.windows.net/backups/dbbackup.bak to server1\instance1. The connection to Azure will be made using the
        credential MyAzureCredential held on instance Server1\instance1

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path http://demo.blob.core.windows.net/backups/dbbackup.bak

        Will attempt to restore the backups from http://demo.blob.core.windows.net/backups/dbbackup.bak if a SAS credential with the name http://demo.blob.core.windows.net/backups exists on server1\instance1

    .EXAMPLE
        PS C:\> $File = Get-ChildItem c:\backups, \\server1\backups
        PS C:\> $File | Restore-DbaDatabase -SqlInstance Server1\Instance -UseDestinationDefaultDirectories

        This will take all of the files found under the folders c:\backups and \\server1\backups, and pipeline them into
        Restore-DbaDatabase. Restore-DbaDatabase will then scan all of the files, and restore all of the databases included
        to the latest point in time covered by their backups. All data and log files will be moved to the default SQL Server
        folder for those file types as defined on the target instance.

    .EXAMPLE
        PS C:\> $files = Get-ChildItem C:\dbatools\db1
        PS C:\> $params = @{
        >> SqlInstance = 'server\instance1'
        >> DestinationFilePrefix = 'prefix'
        >> DatabaseName ='Restored'
        >> RestoreTime = (get-date "14:58:30 22/05/2017")
        >> NoRecovery = $true
        >> WithReplace = $true
        >> StandbyDirectory = 'C:\dbatools\standby'
        >> }
        >>
        PS C:\> $files | Restore-DbaDatabase @params
        PS C:\> Invoke-DbaQuery -SQLInstance server\instance1 -Query "select top 1 * from Restored.dbo.steps order by dt desc"
        PS C:\> $params.RestoredTime = (get-date "15:09:30 22/05/2017")
        PS C:\> $params.NoRecovery = $false
        PS C:\> $params.Add("Continue",$true)
        PS C:\> $files | Restore-DbaDatabase @params
        PS C:\> Invoke-DbaQuery -SQLInstance server\instance1 -Query "select top 1 * from restored.dbo.steps order by dt desc"
        PS C:\> Restore-DbaDatabase -SqlInstance server\instance1 -DestinationFilePrefix prefix -DatabaseName Restored -Continue -WithReplace

        In this example we step through the backup files held in c:\dbatools\db1 folder.
        First we restore the database to a point in time in standby mode. This means we can check some details in the databases
        We then roll it on a further 9 minutes to perform some more checks
        And finally we continue by rolling it all the way forward to the latest point in the backup.
        At each step, only the log files needed to roll the database forward are restored.

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server\instance1 -Path c:\backups -DatabaseName example1 -NoRecovery
        PS C:\> Restore-DbaDatabase -SqlInstance server\instance1 -Recover -DatabaseName example1

        In this example we restore example1 database with no recovery, and then the second call is to set the database to recovery.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory - SqlInstance server\instance1 -Database ProdFinance -Last | Restore-DbaDatabase -PageRestore
        PS C:\> $SuspectPage -PageRestoreTailFolder c:\temp -TrustDbBackupHistory

        Gets a list of Suspect Pages using Get-DbaSuspectPage. The uses Get-DbaDbBackupHistory and Restore-DbaDatabase to perform a restore of the suspect pages and bring them up to date
        If server\instance1 is Enterprise edition this will be done online, if not it will be performed offline

    .EXAMPLE
        PS C:\> $BackupHistory = Get-DbaBackupInformation -SqlInstance sql2005 -Path \\backups\sql2000\ProdDb
        PS C:\> $BackupHistory | Restore-DbaDatabase -SqlInstance sql2000 -TrustDbBackupHistory

        Due to SQL Server 2000 not returning all the backup headers we cannot restore directly. As this is an issues with the SQL engine all we can offer is the following workaround
        This will use a SQL Server instance > 2000 to read the headers, and then pass them in to Restore-DbaDatabase as a BackupHistory object.

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1\instance1 -Path "C:\Temp\devops_prod_full.bak" -DatabaseName "DevOps_DEV" -ReplaceDbNameInFile
        PS C:\> Rename-DbaDatabase -SqlInstance server1\instance1 -Database "DevOps_DEV" -LogicalName "<DBN>_<FT>"

        This will restore the database from the "C:\Temp\devops_prod_full.bak" file, with the new name "DevOps_DEV" and store the different physical files with the new name. It will use the system default configured data and log locations.
        After the restore the logical names of the database files will be renamed with the "DevOps_DEV_ROWS" for MDF/NDF and "DevOps_DEV_LOG" for LDF

    .EXAMPLE
        PS C:\> $FileStructure = @{
        >> 'database_data' = 'C:\Data\database_data.mdf'
        >> 'database_log' = 'C:\Log\database_log.ldf'
        >> }
        >>
        PS C:\> Restore-DbaDatabase -SqlInstance server1 -Path \\ServerName\ShareName\File -DatabaseName database -FileMapping $FileStructure

        Restores 'database' to 'server1' and moves the files to new locations. The format for the $FileStructure HashTable is the file logical name as the Key, and the new location as the Value.

    .EXAMPLE
        PS C:\> $filemap = Get-DbaDbFileMapping -SqlInstance sql2016 -Database test
        PS C:\> Get-ChildItem \\nas\db\backups\test | Restore-DbaDatabase -SqlInstance sql2019 -Database test -FileMapping $filemap.FileMapping

        Restores test to sql2019 using the file structure built from the existing database on sql2016

    .EXAMPLE
        PS C:\> Restore-DbaDatabase -SqlInstance server1 -Path \\ServerName\ShareName\File -DatabaseName database -DatabaseName database -StopMark OvernightStart -StopBefore -StopAfterDate Get-Date('21:00 10/05/2020')

        Restores the backups from \\ServerName\ShareName\File as database, stops before the first 'OvernightStop' mark that occurs after '21:00 10/05/2020'.

        Note that Date time needs to be specified in your local SQL Server culture
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Restore")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "AzureCredential", Justification = "For Parameter AzureCredential")]
    param (
        [parameter(Mandatory)][DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Restore")][parameter(Mandatory, ValueFromPipeline, ParameterSetName = "RestorePage")][object[]]$Path,
        [parameter(ValueFromPipeline)][Alias("Name")][object[]]$DatabaseName,
        [parameter(ParameterSetName = "Restore")][String]$DestinationDataDirectory,
        [parameter(ParameterSetName = "Restore")][String]$DestinationLogDirectory,
        [parameter(ParameterSetName = "Restore")][String]$DestinationFileStreamDirectory,
        [parameter(ParameterSetName = "Restore")][DateTime]$RestoreTime = (Get-Date).AddYears(1),
        [parameter(ParameterSetName = "Restore")][switch]$NoRecovery,
        [parameter(ParameterSetName = "Restore")][switch]$WithReplace,
        [parameter(ParameterSetName = "Restore")][switch]$KeepReplication,
        [parameter(ParameterSetName = "Restore")][Switch]$XpDirTree,
        [parameter(ParameterSetName = "Restore")][Switch]$NoXpDirRecurse,
        [switch]$OutputScriptOnly,
        [parameter(ParameterSetName = "Restore")][switch]$VerifyOnly,
        [parameter(ParameterSetName = "Restore")][switch]$MaintenanceSolutionBackup,
        [parameter(ParameterSetName = "Restore", ValueFromPipelineByPropertyname)][hashtable]$FileMapping,
        [parameter(ParameterSetName = "Restore")][switch]$IgnoreLogBackup,
        [parameter(ParameterSetName = "Restore")][switch]$IgnoreDiffBackup,
        [parameter(ParameterSetName = "Restore")][switch]$UseDestinationDefaultDirectories,
        [parameter(ParameterSetName = "Restore")][switch]$ReuseSourceFolderStructure,
        [parameter(ParameterSetName = "Restore")][string]$DestinationFilePrefix = '',
        [parameter(ParameterSetName = "Restore")][string]$RestoredDatabaseNamePrefix,
        [parameter(ParameterSetName = "Restore")][parameter(ParameterSetName = "RestorePage")][switch]$TrustDbBackupHistory,
        [parameter(ParameterSetName = "Restore")][parameter(ParameterSetName = "RestorePage")][int]$MaxTransferSize,
        [parameter(ParameterSetName = "Restore")][parameter(ParameterSetName = "RestorePage")][int]$BlockSize,
        [parameter(ParameterSetName = "Restore")][parameter(ParameterSetName = "RestorePage")][int]$BufferCount,
        [parameter(ParameterSetName = "Restore")][switch]$DirectoryRecurse,
        [switch]$EnableException,
        [parameter(ParameterSetName = "Restore")][string]$StandbyDirectory,
        [parameter(ParameterSetName = "Restore")][switch]$Continue,
        [parameter(ParameterSetName = "Restore")][string]$ExecuteAs,
        [string]$AzureCredential,
        [parameter(ParameterSetName = "Restore")][switch]$ReplaceDbNameInFile,
        [parameter(ParameterSetName = "Restore")][string]$DestinationFileSuffix,
        [parameter(ParameterSetName = "Recovery")][switch]$Recover,
        [parameter(ParameterSetName = "Restore")][switch]$KeepCDC,
        [string]$GetBackupInformation,
        [switch]$StopAfterGetBackupInformation,
        [string]$SelectBackupInformation,
        [switch]$StopAfterSelectBackupInformation,
        [string]$FormatBackupInformation,
        [switch]$StopAfterFormatBackupInformation,
        [string]$TestBackupInformation,
        [switch]$StopAfterTestBackupInformation,
        [parameter(Mandatory, ParameterSetName = "RestorePage")][object]$PageRestore,
        [parameter(Mandatory, ParameterSetName = "RestorePage")][string]$PageRestoreTailFolder,
        [switch]$StopBefore,
        [string]$StopMark,
        [datetime]$StopAfterDate = (Get-Date '01/01/1971'),
        [int]$StatementTimeout = 0
    )
    begin {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Debug -Message "Parameters bound: $($PSBoundParameters.Keys -join ", ")"

        #region Validation
        try {
            $RestoreInstance = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database master
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $instance
            return
        }

        if ($RestoreInstance.DatabaseEngineEdition -eq "SqlManagedInstance") {
            Write-Message -Level Verbose -Message "Restore target is a Managed Instance, restricted feature set available"
            $MiParams = ("DestinationDataDirectory", "DestinationLogDirectory", "DestinationFileStreamDirectory", "XpDirTree", "FileMapping", "UseDestinationDefaultDirectories", "ReuseSourceFolderStructure", "DestinationFilePrefix", "StandbyDirecttory", "ReplaceDbNameInFile", "KeepCDC")
            ForEach ($MiParam in $MiParams) {
                if (Test-Bound $MiParam) {
                    # Write-Message -Level Warning "Restoring to a Managed SQL Instance, parameter $MiParm is not supported"
                    Stop-Function -Category InvalidArgument -Message "The parameter $MiParam cannot be used with a Managed SQL Instance"
                    return
                }
            }
        }

        if ($PSCmdlet.ParameterSetName -eq "Restore") {
            $UseDestinationDefaultDirectories = $true
            $paramCount = 0

            if (Test-Bound "FileMapping") {
                $paramCount += 1
            }
            If (Test-Bound "ExecuteAs") {
                if ((Get-DbaLogin -SqlInstance $RestoreInstance -Login $ExecuteAs).count -eq 0) {
                    Stop-Function -Category  InvalidArgument -Message "You specified a Login to execute the restore, but the login '$ExecuteAs' does not exist"
                    return
                }
            }
            if (Test-Bound "ReuseSourceFolderStructure") {
                $paramCount += 1
            }
            if (Test-Bound "DestinationDataDirectory") {
                $paramCount += 1
            }
            if ($paramCount -gt 1) {
                Stop-Function -Category InvalidArgument -Message "You've specified incompatible Location parameters. Please only specify one of FileMapping, ReuseSourceFolderStructure or DestinationDataDirectory"
                return
            }
            if (($ReplaceDbNameInFile) -and !(Test-Bound "DatabaseName")) {
                Stop-Function -Category InvalidArgument -Message "To use ReplaceDbNameInFile you must specify DatabaseName"
                return
            }

            if ((Test-Bound "DestinationLogDirectory") -and (Test-Bound "ReuseSourceFolderStructure")) {
                Stop-Function -Category InvalidArgument -Message "The parameters DestinationLogDirectory and UseDestinationDefaultDirectories are mutually exclusive"
                return
            }
            if ((Test-Bound "DestinationLogDirectory") -and -not (Test-Bound "DestinationDataDirectory")) {
                Stop-Function -Category InvalidArgument -Message "The parameter DestinationLogDirectory can only be specified together with DestinationDataDirectory"
                return
            }
            if ((Test-Bound "DestinationFileStreamDirectory") -and (Test-Bound "ReuseSourceFolderStructure")) {
                Stop-Function -Category InvalidArgument -Message "The parameters DestinationFileStreamDirectory and UseDestinationDefaultDirectories are mutually exclusive"
                return
            }
            if ((Test-Bound "DestinationFileStreamDirectory") -and -not (Test-Bound "DestinationDataDirectory")) {
                Stop-Function -Category InvalidArgument -Message "The parameter DestinationFileStreamDirectory can only be specified together with DestinationDataDirectory"
                return
            }
            if ((Test-Bound "ReuseSourceFolderStructure") -and (Test-Bound "UseDestinationDefaultDirectories")) {
                Stop-Function -Category InvalidArgument -Message "The parameters UseDestinationDefaultDirectories and ReuseSourceFolderStructure cannot both be applied "
                return
            }

            if (($null -ne $FileMapping) -or $ReuseSourceFolderStructure -or ($DestinationDataDirectory -ne '')) {
                $UseDestinationDefaultDirectories = $false
            }
            if (($MaxTransferSize % 64kb) -ne 0 -or $MaxTransferSize -gt 4mb) {
                Stop-Function -Category InvalidArgument -Message "MaxTransferSize value must be a multiple of 64kb and no greater than 4MB"
                return
            }
            if ($BlockSize) {
                if ($BlockSize -notin (0.5kb, 1kb, 2kb, 4kb, 8kb, 16kb, 32kb, 64kb)) {
                    Stop-Function -Category InvalidArgument -Message "Block size must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb,64kb"
                    return
                }
            }
            if ('' -ne $StandbyDirectory) {
                if (!(Test-DbaPath -Path $StandbyDirectory -SqlInstance $RestoreInstance)) {
                    Stop-Function -Message "$SqlServer cannot see the specified Standby Directory $StandbyDirectory" -Target $SqlInstance
                    return
                }
            }
            if ($KeepCDC -and ($NoRecovery -or ('' -ne $StandbyDirectory))) {
                Stop-Function -Category InvalidArgument -Message "KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work"
                return
            }
            if ($Continue) {
                Write-Message -Message "Called with continue, so assume we have an existing db in norecovery"
                $WithReplace = $True
                $ContinuePoints = Get-RestoreContinuableDatabase -SqlInstance $RestoreInstance
                $LastRestoreType = Get-DbaDbRestoreHistory -SqlInstance $RestoreInstance -Last
            }
            if (!($PSBoundParameters.ContainsKey("DataBasename"))) {
                $PipeDatabaseName = $true
            }
            if ($OutputScriptOnly -and $VerifyOnly) {
                Stop-Function -Category InvalidArgument -Message "The switches OutputScriptOnly and VerifyOnly cannot both be specified at the same time, stopping"
                return
            }
        }

        if ($StatementTimeout -eq 0) {
            Write-Message -Level Verbose -Message "Changing statement timeout to infinity"
        } else {
            Write-Message -Level Verbose -Message "Changing statement timeout to ($StatementTimeout) minutes"
        }
        $RestoreInstance.ConnectionContext.StatementTimeout = ($StatementTimeout * 60)
        #endregion Validation

        if ($UseDestinationDefaultDirectories) {
            $DefaultPath = (Get-DbaDefaultPath -SqlInstance $RestoreInstance)
            $DestinationDataDirectory = $DefaultPath.Data
            $DestinationLogDirectory = $DefaultPath.Log
        }

        $BackupHistory = @()
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if ($RestoreInstance.VersionMajor -eq 8 -and $true -ne $TrustDbBackupHistory) {
            foreach ($file in $Path) {
                $bh = Get-DbaBackupInformation -SqlInstance $RestoreInstance -Path $file
                $bound = $PSBoundParameters
                $bound['TrustDbBackupHistory'] = $true
                $bound['Path'] = $bh
                Restore-DbaDatabase @bound
            }
            # Flag function interrupt to silently not execute end
            ${__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r} = $true
            return
        }
        if ($PSCmdlet.ParameterSetName -like "Restore*") {
            if ($PipeDatabaseName -eq $true) {
                $DatabaseName = ''
            }
            Write-Message -message "ParameterSet  = Restore" -Level Verbose
            if ($TrustDbBackupHistory -or $path[0].GetType().ToString() -eq 'Sqlcollaborative.Dbatools.Database.BackupHistory') {
                foreach ($f in $path) {
                    Write-Message -Level Verbose -Message "Trust Database Backup History Set"
                    if ("BackupPath" -notin $f.PSObject.Properties.name) {
                        Write-Message -Level Verbose -Message "adding BackupPath - $($_.FullName)"
                        $f = $f | Select-Object *, @{ Name = "BackupPath"; Expression = { $_.FullName } }
                    }
                    if ("DatabaseName" -notin $f.PSObject.Properties.Name) {
                        $f = $f | Select-Object *, @{ Name = "DatabaseName"; Expression = { $_.Database } }
                    }
                    if ("Database" -notin $f.PSObject.Properties.Name) {
                        $f = $f | Select-Object *, @{ Name = "Database"; Expression = { $_.DatabaseName } }
                    }
                    if ("BackupSetGUID" -notin $f.PSObject.Properties.Name) {
                        $f = $f | Select-Object *, @{ Name = "BackupSetGUID"; Expression = { $_.BackupSetID } }
                    }
                    if ($f.BackupPath -like 'http*') {
                        if ('' -ne $AzureCredential) {
                            Write-Message -Message "At least one Azure backup passed in with a credential, assume correct" -Level Verbose
                            Write-Message -Message "Storage Account Identity access means striped backups cannot be restore"
                        } else {
                            if ($f.BackupPath.count -gt 1) {
                                $null = $f.BackupPath[0] -match '(http|https)://[^/]*/[^/]*'
                            } else {
                                $null = $f.BackupPath -match '(http|https)://[^/]*/[^/]*'
                            }
                            if (Get-DbaCredential -SqlInstance $RestoreInstance -Name $matches[0].trim('/') ) {
                                Write-Message -Message "We have a SAS credential to use with $($f.BackupPath)" -Level Verbose
                            } else {
                                Stop-Function -Message "A URL to a backup has been passed in, but no credential can be found to access it"
                                return
                            }
                        }
                    }
                    # Fix #5036 by implementing a deep copy of the FileList
                    $f.FileList = $f.FileList | Select-Object *
                    $BackupHistory += $f | Select-Object *, @{ Name = "ServerName"; Expression = { $_.SqlInstance } }, @{ Name = "BackupStartDate"; Expression = { $_.Start -as [DateTime] } }
                }
            } else {
                $files = @()
                foreach ($f in $Path) {
                    if ($f -is [System.IO.FileSystemInfo]) {
                        $files += $f.FullName
                    } else {
                        $files += $f
                    }
                }
                Write-Message -Level Verbose -Message "Unverified input, full scans - $($files -join ';')"
                if ($BackupHistory.GetType().ToString() -eq 'Sqlcollaborative.Dbatools.Database.BackupHistory') {
                    $BackupHistory = @($BackupHistory)
                }
                $BackupHistory += Get-DbaBackupInformation -SqlInstance $RestoreInstance -SqlCredential $SqlCredential -Path $files -DirectoryRecurse:$DirectoryRecurse -MaintenanceSolution:$MaintenanceSolutionBackup -IgnoreDiffBackup:$IgnoreDiffBackup -IgnoreLogBackup:$IgnoreLogBackup -AzureCredential $AzureCredential -NoXpDirRecurse:$NoXpDirRecurse
            }
            if ($PSCmdlet.ParameterSetName -eq "RestorePage") {
                if (-not (Test-DbaPath -SqlInstance $RestoreInstance -Path $PageRestoreTailFolder)) {
                    Stop-Function -Message "Instance $RestoreInstance cannot read $PageRestoreTailFolder, cannot proceed" -Target $PageRestoreTailFolder
                    return
                }
                $WithReplace = $true
            }
        } elseif ($PSCmdlet.ParameterSetName -eq "Recovery") {
            Write-Message -Message "$($Database.Count) databases to recover" -level Verbose
            foreach ($Database in $DatabaseName) {
                if ($Database -is [object]) {
                    #We've got an object, try the normal options Database, DatabaseName, Name
                    if ("Database" -in $Database.PSObject.Properties.Name) {
                        [string]$DataBase = $Database.Database
                    } elseif ("DatabaseName" -in $Database.PSObject.Properties.Name) {
                        [string]$DataBase = $Database.DatabaseName
                    } elseif ("Name" -in $Database.PSObject.Properties.Name) {
                        [string]$Database = $Database.name
                    }
                }
                Write-Message -Level Verbose -Message "existence - $($RestoreInstance.Databases[$DataBase].State)"
                if ($RestoreInstance.Databases[$DataBase].State -ne 'Existing') {
                    Write-Message -Message "$Database does not exist on $RestoreInstance" -level Warning
                    continue
                }
                if ($RestoreInstance.Databases[$Database].Status -ne "Restoring") {
                    Write-Message -Message "$Database on $RestoreInstance is not in a Restoring State" -Level Warning
                    continue
                }
                $RestoreComplete = $true
                $RecoverSql = "RESTORE DATABASE [$Database] WITH RECOVERY"
                Write-Message -Message "Recovery Sql Query - $RecoverSql" -level verbose
                try {
                    $RestoreInstance.query($RecoverSql)
                } catch {
                    $RestoreComplete = $False
                    $ExitError = $_.Exception.InnerException
                    Write-Message -Level Warning -Message "Failed to recover $Database on $RestoreInstance, `n $ExitError"
                } finally {
                    [PSCustomObject]@{
                        SqlInstance     = $SqlInstance
                        DatabaseName    = $Database
                        RestoreComplete = $RestoreComplete
                        Scripts         = $RecoverSql
                    }
                }
            }
        }
    }
    end {
        if (Test-FunctionInterrupt) {
            return
        }
        if (($BackupHistory.Database | Sort-Object -Unique).count -gt 1 -and ('' -ne $DatabaseName)) {
            Stop-Function -Message "Multiple Databases' backups passed in, but only 1 name to restore them under. Stopping as cannot work out how to proceed" -Category  InvalidArgument
            return
        }
        if ($PSCmdlet.ParameterSetName -like "Restore*") {
            if ($BackupHistory.Count -eq 0 -and $RestoreInstance.VersionMajor -ne 8) {
                Write-Message -Level Warning -Message "No backups passed through. `n This could mean the SQL instance cannot see the referenced files, the file's headers could not be read or some other issue"
                return
            }
            Write-Message -message "Processing DatabaseName - $DatabaseName" -Level Verbose
            $FilteredBackupHistory = @()
            if (Test-Bound -ParameterName GetBackupInformation) {
                Write-Message -Message "Setting $GetBackupInformation to BackupHistory" -Level Verbose
                Set-Variable -Name $GetBackupInformation -Value $BackupHistory -Scope Global
            }
            if ($StopAfterGetBackupInformation) {
                return
            }
            $pathSep = Get-DbaPathSep -Server $RestoreInstance
            $BackupHistory = $BackupHistory | Format-DbaBackupInformation -DataFileDirectory $DestinationDataDirectory -LogFileDirectory $DestinationLogDirectory -DestinationFileStreamDirectory $DestinationFileStreamDirectory -DatabaseFileSuffix $DestinationFileSuffix -DatabaseFilePrefix $DestinationFilePrefix -DatabaseNamePrefix $RestoredDatabaseNamePrefix -ReplaceDatabaseName $DatabaseName -Continue:$Continue -ReplaceDbNameInFile:$ReplaceDbNameInFile -FileMapping $FileMapping -PathSep $pathSep

            if (Test-Bound -ParameterName FormatBackupInformation) {
                Set-Variable -Name $FormatBackupInformation -Value $BackupHistory -Scope Global
            }
            if ($StopAfterFormatBackupInformation) {
                return
            }
            if ($VerifyOnly) {
                $FilteredBackupHistory = $BackupHistory
            } else {
                $FilteredBackupHistory = $BackupHistory | Select-DbaBackupInformation -RestoreTime $RestoreTime -IgnoreLogs:$IgnoreLogBackups -IgnoreDiffs:$IgnoreDiffBackup -ContinuePoints $ContinuePoints -LastRestoreType $LastRestoreType -DatabaseName $DatabaseName
            }
            if (Test-Bound -ParameterName SelectBackupInformation) {
                Write-Message -Message "Setting $SelectBackupInformation to FilteredBackupHistory" -Level Verbose
                Set-Variable -Name $SelectBackupInformation -Value $FilteredBackupHistory -Scope Global

            }
            if ($StopAfterSelectBackupInformation) {
                return
            }
            try {
                Write-Message -Level Verbose -Message "VerifyOnly = $VerifyOnly"
                $null = $FilteredBackupHistory | Test-DbaBackupInformation -SqlInstance $RestoreInstance -WithReplace:$WithReplace -Continue:$Continue -VerifyOnly:$VerifyOnly -EnableException:$true -OutputScriptOnly:$OutputScriptOnly
            } catch {
                Stop-Function -ErrorRecord $_ -Message "Failure" -Continue
            }
            if (Test-Bound -ParameterName TestBackupInformation) {
                Set-Variable -Name $TestBackupInformation -Value $FilteredBackupHistory -Scope Global
            }
            if ($StopAfterTestBackupInformation) {
                return
            }
            $DbVerfied = ($FilteredBackupHistory | Where-Object { $_.IsVerified -eq $True } | Sort-Object -Property Database -Unique).Database -join ','
            Write-Message -Message "$DbVerfied passed testing" -Level Verbose
            if ((@($FilteredBackupHistory | Where-Object { $_.IsVerified -eq $True })).count -lt $FilteredBackupHistory.count) {
                $DbUnVerified = ($FilteredBackupHistory | Where-Object { $_.IsVerified -eq $False } | Sort-Object -Property Database -Unique).Database -join ','
                Write-Message -Level Warning -Message "Database $DbUnverified failed testing,  skipping"
            }
            If ($PSCmdlet.ParameterSetName -eq "RestorePage") {
                if (($FilteredBackupHistory.Database | Sort-Object -Unique | Measure-Object).count -ne 1) {
                    Stop-Function -Message "Must only 1 database passed in for Page Restore. Sorry"
                    return
                } else {
                    $WithReplace = $false
                }
            }
            Write-Message -Message "Passing in to restore" -Level Verbose

            if ($PSCmdlet.ParameterSetName -eq "RestorePage" -and $RestoreInstance.Edition -notlike '*Enterprise*') {
                Write-Message -Message "Taking Tail log backup for page restore for non-Enterprise" -Level Verbose
                $TailBackup = Backup-DbaDatabase -SqlInstance $RestoreInstance -Database $DatabaseName -Type Log -BackupDirectory $PageRestoreTailFolder -NoRecovery -CopyOnly
            }
            try {
                $FilteredBackupHistory | Where-Object { $_.IsVerified -eq $true } | Invoke-DbaAdvancedRestore -SqlInstance $RestoreInstance -WithReplace:$WithReplace -RestoreTime $RestoreTime -StandbyDirectory $StandbyDirectory -NoRecovery:$NoRecovery -Continue:$Continue -OutputScriptOnly:$OutputScriptOnly -BlockSize $BlockSize -MaxTransferSize $MaxTransferSize -BufferCount $Buffercount -KeepCDC:$KeepCDC -VerifyOnly:$VerifyOnly -PageRestore $PageRestore -EnableException -AzureCredential $AzureCredential -KeepReplication:$KeepReplication -StopMark:$StopMark -StopAfterDate:$StopAfterDate -StopBefore:$StopBefore -ExecuteAs $ExecuteAs
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -Target $RestoreInstance
            }
            if ($PSCmdlet.ParameterSetName -eq "RestorePage") {
                if ($RestoreInstance.Edition -like '*Enterprise*') {
                    Write-Message -Message "Taking Tail log backup for page restore for Enterprise" -Level Verbose
                    $TailBackup = Backup-DbaDatabase -SqlInstance $RestoreInstance -Database $DatabaseName -Type Log -BackupDirectory $PageRestoreTailFolder -NoRecovery -CopyOnly
                }
                Write-Message -Message "Restoring Tail log backup for page restore" -Level Verbose
                $TailBackup | Restore-DbaDatabase -SqlInstance $RestoreInstance -TrustDbBackupHistory -NoRecovery -OutputScriptOnly:$OutputScriptOnly -BlockSize $BlockSize -MaxTransferSize $MaxTransferSize -BufferCount $Buffercount -Continue
                Restore-DbaDatabase -SqlInstance $RestoreInstance -Recover -DatabaseName $DatabaseName -OutputScriptOnly:$OutputScriptOnly
            }
            # refresh the SMO as we probably used T-SQL, but only if we already got a SMO
            if ($SqlInstance.InputObject -is [Microsoft.SqlServer.Management.Smo.Server]) {
                $SqlInstance.InputObject.Databases.Refresh()
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUzb+w+yTzR9sRJJPkdfsQrM41
# BCCgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFKiKPL0u7Rd1NkD9dkwGcgNzHMbPMA0GCSqGSIb3DQEBAQUABIIBAJohdSRt
# XhWmANFtty9Tfs/mMw0sSle8g6PD21ykM6BoWvVTF8jzvfTp+BriyGozd/T5Qvyg
# 9JnxKudkDIbus4hUyfrfZ7lVhSyVuam6IcJ41a9YzUhM8+LQg/80ULn/KFjljU5b
# 6b2131iJXSlzEPK97XI0/sQqjLVoSo9bcZrpAH4CmqPLHTGAdMypBT/X5SdwtBgk
# RQpehyNTfU60+i8wxvAuTAEtpOs+byGfuFHVAGavLc8vB+0+6CWApc01jVOvNDfX
# CTivzYsdWxBOfAX8vYDb/zYDGUAv1qTprIOMuUX7FVum6u5mVPgInqDRRS861FDN
# ABvKCW7ULU4qWkWhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAwNVowLwYJKoZIhvcNAQkEMSIEINc3oba4NlHg/+ddSVsL50kCh8J+
# IQ4z/uf3OUmHXdaxMA0GCSqGSIb3DQEBAQUABIIBAHK2e7I3W0kNVVs+WRHT9lgT
# AEmB7uFYAnYB1QBZ3i+uE5bail32Ii2Dfkq86aOkKQ11VZDhcLvelEgQPlrRPxQo
# Nf8ugCaxpy3rFWp3fZV2oObH8LjJNscx6WjGQU6xgERTD+atSxb+nmJ7hpMsWFor
# cjYGo8LcArIWorqih5t6cTxYrYyC4akhFf+k+bK26+45hGi/OBXZ5NWTJCcLXf5I
# 6Kw5Ppk42Tf6vSa5MVfAadu1uWBpicZMPvPa7URYS13ImekVf8FlhnT7CJ+otTrP
# +i01s0cNVU1G64+yoogdXjs8Ptzm+diSoK2VoyC9ETwjdCoLK39I4m1VMkGHKt4=
# SIG # End signature block
