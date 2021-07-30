#requires -Version 3.0
param(
    [Collections.IDictionary]
    [Alias('Options')]
    $Option = @{ }
)

$start = [DateTime]::Now

if (($PSVersionTable.PSVersion.Major -lt 6) -or ($PSVersionTable.Platform -and $PSVersionTable.Platform -eq 'Win32NT')) {
    $script:isWindows = $true
} else {
    $script:isWindows = $false
}

if ('Sqlcollaborative.Dbatools.dbaSystem.DebugHost' -as [Type]) {
    # If we've already got for module import,
    [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Clear() # clear it (since we're clearly re-importing)
}

#region Import helper functions
function Import-ModuleFile {
    <#
    .SYNOPSIS
        Helps import dbatools files according to configuration

    .DESCRIPTION
        Helps import dbatools files according to configuration
        Always dotsource this function!

    .PARAMETER Path
        The full path to the file to import

    .EXAMPLE
        PS C:\> Import-ModuleFile -Path $function.FullName

        Imports the file stored at '$function.FullName'
    #>
    [CmdletBinding()]
    param (
        $Path
    )

    if (-not $path) {
        return
    }

    if ($script:doDotSource) {
        . (Resolve-Path -Path $Path)
    } else {
        $txt = [IO.File]::ReadAllText((Resolve-Path -Path $Path).ProviderPath)
        $ExecutionContext.InvokeCommand.InvokeScript($TXT, $false, [Management.Automation.Runspaces.PipelineResultTypes]::None, $null, $null)
    }
}

function Write-ImportTime {
    <#
    .SYNOPSIS
        Writes an entry to the import module time debug list

    .DESCRIPTION
        Writes an entry to the import module time debug list

    .PARAMETER Text
        The message to write

    .EXAMPLE
        PS C:\> Write-ImportTime -Text "Starting SMO Import"

        Adds the message "Starting SMO Import" to the debug list
#>
    param (
        [string]$Text,
        $Timestamp = ([DateTime]::now)
    )


    if (-not $script:dbatools_ImportPerformance) {
        $script:dbatools_ImportPerformance = New-Object Collections.ArrayList
    }

    if (-not ('Sqlcollaborative.Dbatools.Configuration.Config' -as [type])) {
        $script:dbatools_ImportPerformance.AddRange(@(New-Object PSObject -Property @{ Time = $timestamp; Action = $Text }))
    } else {
        if ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Count -eq 0) {
            foreach ($entry in $script:dbatools_ImportPerformance) {
                $te = New-Object Sqlcollaborative.Dbatools.dbaSystem.StartTimeEntry($entry.Action, $entry.Time, [Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId)
                [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Add($te)
            }
            $script:dbatools_ImportPerformance.Clear()
        }
        $te = New-Object Sqlcollaborative.Dbatools.dbaSystem.StartTimeEntry($Text, $timestamp, ([Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId))
        [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Add($te)
    }
}

Write-ImportTime -Text "Start" -Timestamp $start
Write-ImportTime -Text "Loading System.Security"
Add-Type -AssemblyName System.Security
Write-ImportTime -Text "Loading import helper functions"
#endregion Import helper functions

# Not supporting the provider path at this time 2/28/2017
if ($ExecutionContext.SessionState.Path.CurrentLocation.Drive.Name -eq 'SqlServer') {
    Write-Warning "SQLSERVER:\ provider not supported. Please change to another directory and reload the module."
    Write-Warning "Going to continue loading anyway, but expect issues."
}

Write-ImportTime -Text "Resolved path to not SQLSERVER PSDrive"

$script:PSModuleRoot = $PSScriptRoot

if ($PSVersionTable.PSEdition -and $PSVersionTable.PSEdition -ne 'Desktop') {
    $script:core = $true
} else {
    $script:core = $false
}

#region Import Defines
if ($psVersionTable.Platform -ne 'Unix' -and 'Microsoft.Win32.Registry' -as [Type]) {
    $regType = 'Microsoft.Win32.Registry' -as [Type]
    $hkcuNode = $regType::CurrentUser.OpenSubKey("SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System")
    if ($dbaToolsSystemNode) {
        $userValues = @{ }
        foreach ($v in $hkcuNode.GetValueNames()) {
            $userValues[$v] = $hkcuNode.GetValue($v)
        }
        $dbatoolsSystemUserNode = $systemValues
    }
    $hklmNode = $regType::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System")
    if ($dbaToolsSystemNode) {
        $systemValues = @{ }
        foreach ($v in $hklmNode.GetValueNames()) {
            $systemValues[$v] = $hklmNode.GetValue($v)
        }
        $dbatoolsSystemSystemNode = $systemValues
    }
} else {
    $dbatoolsSystemUserNode = @{ }
    $dbatoolsSystemSystemNode = @{ }
}

#region Dot Sourcing
# Detect whether at some level dotsourcing was enforced
$script:doDotSource = $dbatools_dotsourcemodule -or
$dbatoolsSystemSystemNode.DoDotSource -or
$dbatoolsSystemUserNode.DoDotSource -or
$option.DoDotSource
#endregion Dot Sourcing

#region Copy DLL Mode
# copy dll mode adds mess but is useful for installations using install.ps1
$script:copyDllMode = $dbatools_copydllmode -or
$dbatoolsSystemSystemNode.CopyDllMode -or
$dbatoolsSystemUserNode.CopyDllMode -or
$option.CopyDllMode
#endregion Copy DLL Mode

#region Always Compile
$script:alwaysBuildLibrary = $dbatools_alwaysbuildlibrary -or
$dbatoolsSystemSystemNode.AlwaysBuildLibrary -or
$dbatoolsSystemUserNode.AlwaysBuildLibrary -or
$option.AlwaysBuildLibrary
#endregion Always Compile

#region Serial Import
$script:serialImport = $dbatools_serialimport -or
$dbatoolsSystemSystemNode.SerialImport -or
$dbatoolsSystemUserNode.SerialImport -or
$Option.SerialImport
#endregion Serial Import

#region Multi File Import
$script:multiFileImport = $dbatools_multiFileImport -or
$dbatoolsSystemSystemNode.MultiFileImport -or
$dbatoolsSystemUserNode.MultiFileImport -or
$option.MultiFileImport


$gitDir = $script:PSModuleRoot, '.git' -join [IO.Path]::DirectorySeparatorChar
if ($dbatools_enabledebug -or
    $option.Debug -or
    $DebugPreference -ne 'silentlycontinue' -or
    [IO.Directory]::Exists($gitDir)) {
    $script:multiFileImport, $script:SerialImport, $script:doDotSource = $true, $true, $true
}
#endregion Multi File Import

Write-ImportTime -Text "Validated defines"
#endregion Import Defines

if (($PSVersionTable.PSVersion.Major -le 5) -or $script:isWindows) {
    Get-ChildItem -Path (Resolve-Path "$script:PSModuleRoot\bin\") -Filter "*.dll" -Recurse | Unblock-File -ErrorAction Ignore
    Write-ImportTime -Text "Unblocking Files"
}


$script:DllRoot = (Resolve-Path -Path "$script:PSModuleRoot\bin\").ProviderPath

<#
If dbatools has not been imported yet, it also hasn't done libraries yet. Fix that.
Previously checked for SMO being available, but that would break import with SqlServer loaded
Some people also use the dbatools library for other things without the module, so also check,
whether the modulebase has been set (first thing it does after loading library through dbatools import)
Theoretically, there's a minor cuncurrency collision risk with that, but since the cost is only
a little import time loss if that happens ...
#>
if ((-not ('Sqlcollaborative.Dbatools.dbaSystem.DebugHost' -as [type])) -or (-not [Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase)) {
    . $script:psScriptRoot\internal\scripts\libraryimport.ps1
    Write-ImportTime -Text "Starting import SMO libraries"
}

<#

    Do the rest of the loading

#>

# This technique helps a little bit
# https://becomelotr.wordpress.com/2017/02/13/expensive-dot-sourcing/

# Load our own custom library
# Should always come before function imports
. $psScriptRoot\bin\library.ps1
. $psScriptRoot\bin\typealiases.ps1
Write-ImportTime -Text "Loading dbatools library"

# Tell the library where the module is based, just in case
[Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase = $script:PSModuleRoot

if ($script:multiFileImport) {
    # All internal functions privately available within the toolset
    foreach ($file in (Get-ChildItem -Path "$psScriptRoot\internal\functions\" -Recurse -Filter *.ps1)) {
        . $file.FullName
    }
    Write-ImportTime -Text "Loading Internal Commands"

    #    . $psScriptRoot\internal\scripts\cmdlets.ps1

    Write-ImportTime -Text "Registering cmdlets"

    # All exported functions
    foreach ($file in (Get-ChildItem -Path "$script:PSModuleRoot\functions\" -Recurse -Filter *.ps1)) {
        . $file.FullName
    }
    Write-ImportTime -Text "Loading Public Commands"

} else {
    #    . $psScriptRoot\internal\scripts\cmdlets.ps1

    . $psScriptRoot\allcommands.ps1
    #. (Resolve-Path -Path "$script:PSModuleRoot\allcommands.ps1")
    Write-ImportTime -Text "Loading Public and Private Commands"

    Write-ImportTime -Text "Registering cmdlets"
}

# Load configuration system
# Should always go after library and path setting
. $psScriptRoot\internal\configurations\configuration.ps1
Write-ImportTime -Text "Configuration System"

# Resolving the path was causing trouble when it didn't exist yet
# Not converting the path separators based on OS was also an issue.
if (-not ([Sqlcollaborative.Dbatools.Message.LogHost]::LoggingPath)) {
    [Sqlcollaborative.Dbatools.Message.LogHost]::LoggingPath = Join-DbaPath $script:AppData "PowerShell" "dbatools"
}

# Run all optional code
# Note: Each optional file must include a conditional governing whether it's run at all.
# Validations were moved into the other files, in order to prevent having to update dbatools.psm1 every time
# 96ms
foreach ($file in (Get-ChildItem -Path "$script:PSScriptRoot\optional" -Filter *.ps1)) {
    . $file.FullName
}
Write-ImportTime -Text "Loading Optional Commands"

# Process TEPP parameters
. $psScriptRoot\internal\scripts\insertTepp.ps1
Write-ImportTime -Text "Loading TEPP"


# Process transforms
. $psScriptRoot\internal\scripts\message-transforms.ps1
Write-ImportTime -Text "Loading Message Transforms"

# Load scripts that must be individually run at the end #
#-------------------------------------------------------#

# Start the logging system (requires the configuration system up and running)
. $psScriptRoot\internal\scripts\logfilescript.ps1
Write-ImportTime -Text "Script: Logging"

# Start the tepp asynchronous update system (requires the configuration system up and running)
. $psScriptRoot\internal\scripts\updateTeppAsync.ps1
Write-ImportTime -Text "Script: Asynchronous TEPP Cache"

# Start the maintenance system (requires pretty much everything else already up and running)
. $psScriptRoot\internal\scripts\dbatools-maintenance.ps1
Write-ImportTime -Text "Script: Maintenance"

#region Aliases

# New 3-char aliases
$shortcuts = @{
    'ivq' = 'Invoke-DbaQuery'
    'cdi' = 'Connect-DbaInstance'
}
foreach ($_ in $shortcuts.GetEnumerator()) {
    New-Alias -Name $_.Key -Value $_.Value
}

# Leave forever
$forever = @{
    'Get-DbaRegisteredServer' = 'Get-DbaRegServer'
    'Attach-DbaDatabase'      = 'Mount-DbaDatabase'
    'Detach-DbaDatabase'      = 'Dismount-DbaDatabase'
    'Start-SqlMigration'      = 'Start-DbaMigration'
    'Write-DbaDataTable'      = 'Write-DbaDbTableData'
    'Get-DbaDbModule'         = 'Get-DbaModule'
}
foreach ($_ in $forever.GetEnumerator()) {
    Set-Alias -Name $_.Key -Value $_.Value
}
#endregion Aliases

#region Post-Import Cleanup
Write-ImportTime -Text "Loading Aliases"

# region Commands
$script:xplat = @(
    'Start-DbaMigration',
    'Copy-DbaDatabase',
    'Copy-DbaLogin',
    'Copy-DbaAgentServer',
    'Copy-DbaSpConfigure',
    'Copy-DbaDbMail',
    'Copy-DbaDbAssembly',
    'Copy-DbaAgentSchedule',
    'Copy-DbaAgentOperator',
    'Copy-DbaAgentJob',
    'Copy-DbaCustomError',
    'Copy-DbaInstanceAuditSpecification',
    'Copy-DbaEndpoint',
    'Copy-DbaInstanceAudit',
    'Copy-DbaServerRole',
    'Copy-DbaResourceGovernor',
    'Copy-DbaXESession',
    'Copy-DbaInstanceTrigger',
    'Copy-DbaRegServer',
    'Copy-DbaSysDbUserObject',
    'Copy-DbaAgentProxy',
    'Copy-DbaAgentAlert',
    'Copy-DbaStartupProcedure',
    'Get-DbaDbDetachedFileInfo',
    'Copy-DbaAgentJobCategory',
    'Test-DbaPath',
    'Export-DbaLogin',
    'Watch-DbaDbLogin',
    'Expand-DbaDbLogFile',
    'Test-DbaMigrationConstraint',
    'Test-DbaNetworkLatency',
    'Find-DbaDbDuplicateIndex',
    'Remove-DbaDatabaseSafely',
    'Set-DbaTempdbConfig',
    'Test-DbaTempdbConfig',
    'Repair-DbaDbOrphanUser',
    'Remove-DbaDbOrphanUser',
    'Find-DbaDbUnusedIndex',
    'Get-DbaDbSpace',
    'Test-DbaDbOwner',
    'Set-DbaDbOwner',
    'Test-DbaAgentJobOwner',
    'Set-DbaAgentJobOwner',
    'Measure-DbaDbVirtualLogFile',
    'Get-DbaDbRestoreHistory',
    'Get-DbaTcpPort',
    'Test-DbaDbCompatibility',
    'Test-DbaDbCollation',
    'Test-DbaConnectionAuthScheme',
    'Test-DbaInstanceName',
    'Repair-DbaInstanceName',
    'Stop-DbaProcess',
    'Find-DbaOrphanedFile',
    'Get-DbaAvailabilityGroup',
    'Get-DbaLastGoodCheckDb',
    'Get-DbaProcess',
    'Get-DbaRunningJob',
    'Set-DbaMaxDop',
    'Test-DbaDbRecoveryModel',
    'Test-DbaMaxDop',
    'Remove-DbaBackup',
    'Get-DbaPermission',
    'Get-DbaLastBackup',
    'Connect-DbaInstance',
    'Get-DbaDbBackupHistory',
    'Get-DbaAgBackupHistory',
    'Read-DbaBackupHeader',
    'Test-DbaLastBackup',
    'Get-DbaMaxMemory',
    'Set-DbaMaxMemory',
    'Get-DbaDbSnapshot',
    'Remove-DbaDbSnapshot',
    'Get-DbaDbRoleMember',
    'Get-DbaServerRoleMember',
    'Get-DbaDbAsymmetricKey',
    'New-DbaDbAsymmetricKey',
    'Remove-DbaDbAsymmetricKey',
    'Invoke-DbaDbTransfer',
    'New-DbaDbTransfer',
    'Remove-DbaDbData',
    'Resolve-DbaNetworkName',
    'Export-DbaAvailabilityGroup',
    'Write-DbaDbTableData',
    'New-DbaDbSnapshot',
    'Restore-DbaDbSnapshot',
    'Get-DbaInstanceTrigger',
    'Get-DbaDbTrigger',
    'Get-DbaDbState',
    'Set-DbaDbState',
    'Get-DbaHelpIndex',
    'Get-DbaAgentAlert',
    'Get-DbaAgentOperator',
    'Get-DbaSpConfigure',
    'Rename-DbaLogin',
    'Find-DbaAgentJob',
    'Find-DbaDatabase',
    'Get-DbaXESession',
    'Export-DbaXESession',
    'Test-DbaOptimizeForAdHoc',
    'Find-DbaStoredProcedure',
    'Measure-DbaBackupThroughput',
    'Get-DbaDatabase',
    'Find-DbaUserObject',
    'Get-DbaDependency',
    'Find-DbaCommand',
    'Backup-DbaDatabase',
    'New-DbaDirectory',
    'Get-DbaDbQueryStoreOption',
    'Set-DbaDbQueryStoreOption',
    'Restore-DbaDatabase',
    'Copy-DbaDbQueryStoreOption',
    'Get-DbaExecutionPlan',
    'Export-DbaExecutionPlan',
    'Set-DbaSpConfigure',
    'Test-DbaIdentityUsage',
    'Get-DbaDbAssembly',
    'Get-DbaAgentJob',
    'Get-DbaCustomError',
    'Get-DbaCredential',
    'Get-DbaBackupDevice',
    'Get-DbaAgentProxy',
    'Get-DbaDbEncryption',
    'Remove-DbaDatabase',
    'Get-DbaQueryExecutionTime',
    'Get-DbaTempdbUsage',
    'Find-DbaDbGrowthEvent',
    'Test-DbaLinkedServerConnection',
    'Get-DbaDbFile',
    'Read-DbaTransactionLog',
    'Get-DbaDbTable',
    'Invoke-DbaDbShrink',
    'Get-DbaEstimatedCompletionTime',
    'Get-DbaLinkedServer',
    'New-DbaAgentJob',
    'Get-DbaLogin',
    'New-DbaScriptingOption',
    'Save-DbaDiagnosticQueryScript',
    'Invoke-DbaDiagnosticQuery',
    'Export-DbaDiagnosticQuery',
    'Invoke-DbaWhoIsActive',
    'Set-DbaAgentJob',
    'Remove-DbaAgentJob',
    'New-DbaAgentJobStep',
    'Set-DbaAgentJobStep',
    'Remove-DbaAgentJobStep',
    'New-DbaAgentSchedule',
    'Set-DbaAgentSchedule',
    'Remove-DbaAgentSchedule',
    'Backup-DbaDbCertificate',
    'Get-DbaDbCertificate',
    'Get-DbaEndpoint',
    'Get-DbaDbMasterKey',
    'Get-DbaSchemaChangeHistory',
    'Get-DbaInstanceAudit',
    'Get-DbaInstanceAuditSpecification',
    'Get-DbaProductKey',
    'Get-DbatoolsLog',
    'Restore-DbaDbCertificate',
    'New-DbaDbCertificate',
    'New-DbaDbMasterKey',
    'New-DbaServiceMasterKey',
    'Remove-DbaDbCertificate',
    'Remove-DbaDbMasterKey',
    'New-DbaConnectionStringBuilder',
    'Get-DbaInstanceProperty',
    'Get-DbaInstanceUserOption',
    'New-DbaConnectionString',
    'Get-DbaAgentSchedule',
    'Read-DbaTraceFile',
    'Get-DbaInstanceInstallDate',
    'Backup-DbaDbMasterKey',
    'Get-DbaAgentJobHistory',
    'Get-DbaMaintenanceSolutionLog',
    'Invoke-DbaDbLogShipRecovery',
    'Find-DbaTrigger',
    'Find-DbaView',
    'Invoke-DbaDbUpgrade',
    'Get-DbaDbUser',
    'Get-DbaAgentLog',
    'Get-DbaDbMailLog',
    'Get-DbaDbMailHistory',
    'Get-DbaDbView',
    'Get-DbaDbUdf',
    'Get-DbaDbPartitionFunction',
    'Get-DbaDbPartitionScheme',
    'Get-DbaDefaultPath',
    'Get-DbaDbStoredProcedure',
    'Test-DbaDbCompression',
    'Mount-DbaDatabase',
    'Dismount-DbaDatabase',
    'Get-DbaAgReplica',
    'Get-DbaAgDatabase',
    'Get-DbaModule',
    'Sync-DbaLoginPermission',
    'New-DbaCredential',
    'Get-DbaFile',
    'Set-DbaDbCompression',
    'Get-DbaTraceFlag',
    'Invoke-DbaCycleErrorLog',
    'Get-DbaAvailableCollation',
    'Get-DbaUserPermission',
    'Get-DbaAgHadr',
    'Find-DbaSimilarTable',
    'Get-DbaTrace',
    'Get-DbaSuspectPage',
    'Get-DbaWaitStatistic',
    'Clear-DbaWaitStatistics',
    'Get-DbaTopResourceUsage',
    'New-DbaLogin',
    'Get-DbaAgListener',
    'Invoke-DbaDbClone',
    'Disable-DbaTraceFlag',
    'Enable-DbaTraceFlag',
    'Start-DbaAgentJob',
    'Stop-DbaAgentJob',
    'New-DbaAgentProxy',
    'Test-DbaDbLogShipStatus',
    'Get-DbaXESessionTarget',
    'New-DbaXESmartTargetResponse',
    'New-DbaXESmartTarget',
    'Get-DbaDbVirtualLogFile',
    'Get-DbaBackupInformation',
    'Start-DbaXESession',
    'Stop-DbaXESession',
    'Set-DbaDbRecoveryModel',
    'Get-DbaDbRecoveryModel',
    'Get-DbaWaitingTask',
    'Remove-DbaDbUser',
    'Get-DbaDump',
    'Invoke-DbaAdvancedRestore',
    'Format-DbaBackupInformation',
    'Get-DbaAgentJobStep',
    'Test-DbaBackupInformation',
    'Invoke-DbaBalanceDataFiles',
    'Select-DbaBackupInformation',
    'Publish-DbaDacPackage',
    'Copy-DbaDbTableData',
    'Copy-DbaDbViewData',
    'Invoke-DbaQuery',
    'Remove-DbaLogin',
    'Get-DbaAgentJobCategory',
    'New-DbaAgentJobCategory',
    'Remove-DbaAgentJobCategory',
    'Set-DbaAgentJobCategory',
    'Get-DbaServerRole',
    'Find-DbaBackup',
    'Remove-DbaXESession',
    'New-DbaXESession',
    'Get-DbaXEStore',
    'New-DbaXESmartTableWriter',
    'New-DbaXESmartReplay',
    'New-DbaXESmartEmail',
    'New-DbaXESmartQueryExec',
    'Start-DbaXESmartTarget',
    'Get-DbaDbOrphanUser',
    'Get-DbaOpenTransaction',
    'Get-DbaDbLogShipError',
    'Test-DbaBuild',
    'Get-DbaXESessionTemplate',
    'ConvertTo-DbaXESession',
    'Start-DbaTrace',
    'Stop-DbaTrace',
    'Remove-DbaTrace',
    'Set-DbaLogin',
    'Copy-DbaXESessionTemplate',
    'Get-DbaXEObject',
    'ConvertTo-DbaDataTable',
    'Find-DbaDbDisabledIndex',
    'Get-DbaXESmartTarget',
    'Remove-DbaXESmartTarget',
    'Stop-DbaXESmartTarget',
    'Get-DbaRegServerGroup',
    'New-DbaDbUser',
    'Measure-DbaDiskSpaceRequirement',
    'New-DbaXESmartCsvWriter',
    'Invoke-DbaXeReplay',
    'Find-DbaInstance',
    'Test-DbaDiskSpeed',
    'Get-DbaDbExtentDiff',
    'Read-DbaAuditFile',
    'Get-DbaDbCompression',
    'Invoke-DbaDbDecryptObject',
    'Get-DbaDbForeignKey',
    'Get-DbaDbCheckConstraint',
    'Set-DbaAgentAlert',
    'Get-DbaWaitResource',
    'Get-DbaDbPageInfo',
    'Get-DbaConnection',
    'Test-DbaLoginPassword',
    'Get-DbaErrorLogConfig',
    'Set-DbaErrorLogConfig',
    'Get-DbaPlanCache',
    'Clear-DbaPlanCache',
    'ConvertTo-DbaTimeline',
    'Get-DbaDbMail',
    'Get-DbaDbMailAccount',
    'Get-DbaDbMailProfile',
    'Get-DbaDbMailConfig',
    'Get-DbaDbMailServer',
    'New-DbaDbMailServer',
    'New-DbaDbMailAccount',
    'New-DbaDbMailProfile',
    'Get-DbaResourceGovernor',
    'Get-DbaRgResourcePool',
    'Get-DbaRgWorkloadGroup',
    'Get-DbaRgClassifierFunction',
    'Export-DbaInstance',
    'Invoke-DbatoolsRenameHelper',
    'Measure-DbatoolsImport',
    'Get-DbaDeprecatedFeature',
    'Test-DbaDeprecatedFeature'
    'Get-DbaDbFeatureUsage',
    'Stop-DbaEndpoint',
    'Start-DbaEndpoint',
    'Set-DbaDbMirror',
    'Repair-DbaDbMirror',
    'Remove-DbaEndpoint',
    'Remove-DbaDbMirrorMonitor',
    'Remove-DbaDbMirror',
    'New-DbaEndpoint',
    'Invoke-DbaDbMirroring',
    'Invoke-DbaDbMirrorFailover',
    'Get-DbaDbMirrorMonitor',
    'Get-DbaDbMirror',
    'Add-DbaDbMirrorMonitor',
    'Test-DbaEndpoint',
    'Get-DbaDbSharePoint',
    'Get-DbaDbMemoryUsage',
    'Clear-DbaLatchStatistics',
    'Get-DbaCpuRingBuffer',
    'Get-DbaIoLatency',
    'Get-DbaLatchStatistic',
    'Get-DbaSpinLockStatistic',
    'Add-DbaAgDatabase',
    'Add-DbaAgListener',
    'Add-DbaAgReplica',
    'Grant-DbaAgPermission',
    'Invoke-DbaAgFailover',
    'Join-DbaAvailabilityGroup',
    'New-DbaAvailabilityGroup',
    'Remove-DbaAgDatabase',
    'Remove-DbaAgListener',
    'Remove-DbaAvailabilityGroup',
    'Revoke-DbaAgPermission',
    'Get-DbaDbCompatibility',
    'Set-DbaDbCompatibility',
    'Invoke-DbatoolsFormatter',
    'Remove-DbaAgReplica',
    'Resume-DbaAgDbDataMovement',
    'Set-DbaAgListener',
    'Set-DbaAgReplica',
    'Set-DbaAvailabilityGroup',
    'Set-DbaEndpoint',
    'Suspend-DbaAgDbDataMovement',
    'Sync-DbaAvailabilityGroup',
    'Get-DbaMemoryCondition',
    'Remove-DbaDbBackupRestoreHistory',
    'New-DbaDatabase'
    'New-DbaDacOption',
    'Get-DbaDbccHelp',
    'Get-DbaDbccMemoryStatus',
    'Get-DbaDbccProcCache',
    'Get-DbaDbccUserOption',
    'Get-DbaAgentServer',
    'Set-DbaAgentServer',
    'Invoke-DbaDbccFreeCache'
    'Export-DbatoolsConfig',
    'Import-DbatoolsConfig',
    'Reset-DbatoolsConfig',
    'Unregister-DbatoolsConfig',
    'Join-DbaPath',
    'Resolve-DbaPath',
    'Import-DbaCsv',
    'Invoke-DbaDbDataMasking',
    'New-DbaDbMaskingConfig',
    'Get-DbaDbccSessionBuffer',
    'Get-DbaDbccStatistic',
    'Get-DbaDbDbccOpenTran',
    'Invoke-DbaDbccDropCleanBuffer',
    'Invoke-DbaDbDbccCheckConstraint',
    'Invoke-DbaDbDbccCleanTable',
    'Invoke-DbaDbDbccUpdateUsage',
    'Get-DbaDbIdentity',
    'Set-DbaDbIdentity',
    'Get-DbaRegServer',
    'Get-DbaRegServerStore',
    'Add-DbaRegServer',
    'Add-DbaRegServerGroup',
    'Export-DbaRegServer',
    'Import-DbaRegServer',
    'Move-DbaRegServer',
    'Move-DbaRegServerGroup',
    'Remove-DbaRegServer',
    'Remove-DbaRegServerGroup',
    # Config system
    'Get-DbatoolsConfig',
    'Get-DbatoolsConfigValue',
    'Set-DbatoolsConfig',
    'Register-DbatoolsConfig',
    # Data generator
    'New-DbaDbDataGeneratorConfig',
    'Invoke-DbaDbDataGenerator',
    'Get-DbaRandomizedValue',
    'Get-DbaRandomizedDatasetTemplate',
    'Get-DbaRandomizedDataset',
    'Get-DbaRandomizedType',
    'Export-DbaDbTableData',
    'Backup-DbaServiceMasterKey',
    'Invoke-DbaDbPiiScan',
    'New-DbaAzAccessToken',
    'Add-DbaDbRoleMember',
    'Disable-DbaStartupProcedure',
    'Enable-DbaStartupProcedure',
    'Get-DbaDbFilegroup',
    'Get-DbaDbObjectTrigger',
    'Get-DbaStartupProcedure',
    'Get-DbatoolsChangeLog',
    'Get-DbaXESessionTargetFile',
    'Get-DbaDbRole',
    'New-DbaDbRole',
    'New-DbaDbTable',
    'New-DbaDiagnosticAdsNotebook',
    'New-DbaServerRole',
    'Remove-DbaDbRole',
    'Remove-DbaDbRoleMember',
    'Remove-DbaServerRole',
    'Test-DbaDbDataGeneratorConfig',
    'Test-DbaDbDataMaskingConfig',
    'Get-DbaAgentAlertCategory',
    'New-DbaAgentAlertCategory',
    'Remove-DbaAgentAlertCategory',
    'Save-DbaKbUpdate',
    'Get-DbaKbUpdate',
    'Get-DbaDbLogSpace',
    'Export-DbaDbRole',
    'Export-DbaServerRole',
    'Get-DbaBuildReference',
    'Update-DbaBuildReference',
    'Install-DbaFirstResponderKit',
    'Install-DbaWhoIsActive',
    'Update-Dbatools',
    'Add-DbaServerRoleMember',
    'Get-DbatoolsPath',
    'Set-DbatoolsPath',
    'Export-DbaSysDbUserObject',
    'Test-DbaDbQueryStore',
    'Install-DbaMultiTool',
    'New-DbaAgentOperator',
    'Remove-DbaAgentOperator',
    'Remove-DbaDbTableData',
    'Get-DbaDbSchema',
    'New-DbaDbSchema'
)

$script:noncoresmo = @(
    # SMO issues
    'Export-DbaUser',
    'Get-DbaSsisExecutionHistory',
    'Get-DbaRepDistributor',
    'Copy-DbaPolicyManagement',
    'Copy-DbaDataCollector',
    'Copy-DbaSsisCatalog',
    'New-DbaSsisCatalog',
    'Get-DbaSsisEnvironmentVariable',
    'Get-DbaPbmCategory',
    'Get-DbaPbmCategorySubscription',
    'Get-DbaPbmCondition',
    'Get-DbaPbmObjectSet',
    'Get-DbaPbmPolicy',
    'Get-DbaPbmStore',
    'Get-DbaRepPublication',
    'Test-DbaRepLatency',
    'Export-DbaRepServerSetting',
    'Get-DbaRepServer',
    'Move-DbaDbFile'
)
$script:windowsonly = @(
    # solvable filesystem issues or other workarounds
    'Copy-DbaBackupDevice',
    'Install-DbaSqlWatch',
    'Uninstall-DbaSqlWatch',
    'Get-DbaRegistryRoot',
    'Install-DbaMaintenanceSolution',
    'New-DbatoolsSupportPackage',
    'Export-DbaScript',
    'Get-DbaAgentJobOutputFile',
    'Set-DbaAgentJobOutputFile',
    'New-DbaDacProfile',
    'Import-DbaXESessionTemplate',
    'Export-DbaXESessionTemplate',
    'Import-DbaSpConfigure',
    'Export-DbaSpConfigure',
    'Read-DbaXEFile',
    'Watch-DbaXESession',
    'Test-DbaMaxMemory', # can be fixed by not testing remote when linux is detected
    'Rename-DbaDatabase', # can maybebe fixed by not remoting when linux is detected
    # CM and Windows functions
    'Get-DbaExtendedProtection',
    'Set-DbaExtendedProtection',
    'Install-DbaInstance',
    'Invoke-DbaAdvancedInstall',
    'Update-DbaInstance',
    'Invoke-DbaAdvancedUpdate',
    'Invoke-DbaPfRelog',
    'Get-DbaPfDataCollectorCounter',
    'Get-DbaPfDataCollectorCounterSample',
    'Get-DbaPfDataCollector',
    'Get-DbaPfDataCollectorSet',
    'Start-DbaPfDataCollectorSet',
    'Stop-DbaPfDataCollectorSet',
    'Export-DbaPfDataCollectorSetTemplate',
    'Get-DbaPfDataCollectorSetTemplate',
    'Import-DbaPfDataCollectorSetTemplate',
    'Remove-DbaPfDataCollectorSet',
    'Add-DbaPfDataCollectorCounter',
    'Remove-DbaPfDataCollectorCounter',
    'Get-DbaPfAvailableCounter',
    'Export-DbaXECsv',
    'Get-DbaOperatingSystem',
    'Get-DbaComputerSystem',
    'Set-DbaPrivilege',
    'Set-DbaTcpPort',
    'Set-DbaCmConnection',
    'Get-DbaUptime',
    'Get-DbaMemoryUsage',
    'Clear-DbaConnectionPool',
    'Get-DbaLocaleSetting',
    'Get-DbaFilestream',
    'Enable-DbaFilestream',
    'Disable-DbaFilestream',
    'Get-DbaCpuUsage',
    'Get-DbaPowerPlan',
    'Get-DbaWsfcAvailableDisk',
    'Get-DbaWsfcCluster',
    'Get-DbaWsfcDisk',
    'Get-DbaWsfcNetwork',
    'Get-DbaWsfcNetworkInterface',
    'Get-DbaWsfcNode',
    'Get-DbaWsfcResource',
    'Get-DbaWsfcResourceType',
    'Get-DbaWsfcRole',
    'Get-DbaWsfcSharedVolume',
    'Export-DbaCredential',
    'Export-DbaLinkedServer',
    'Get-DbaFeature',
    'Update-DbaServiceAccount',
    'Remove-DbaClientAlias',
    'Disable-DbaAgHadr',
    'Enable-DbaAgHadr',
    'Stop-DbaService',
    'Start-DbaService',
    'Restart-DbaService',
    'New-DbaClientAlias',
    'Get-DbaClientAlias',
    'Remove-DbaNetworkCertificate',
    'Enable-DbaForceNetworkEncryption',
    'Disable-DbaForceNetworkEncryption',
    'Get-DbaForceNetworkEncryption',
    'Get-DbaHideInstance',
    'Enable-DbaHideInstance',
    'Disable-DbaHideInstance',
    'New-DbaComputerCertificateSigningRequest',
    'Remove-DbaComputerCertificate',
    'New-DbaComputerCertificate',
    'Get-DbaComputerCertificate',
    'Add-DbaComputerCertificate',
    'Backup-DbaComputerCertificate',
    'Get-DbaNetworkCertificate',
    'Set-DbaNetworkCertificate',
    'Remove-DbaDbLogshipping',
    'Invoke-DbaDbLogShipping',
    'New-DbaCmConnection',
    'Get-DbaCmConnection',
    'Remove-DbaCmConnection',
    'Test-DbaCmConnection',
    'Get-DbaCmObject',
    'Set-DbaStartupParameter',
    'Get-DbaNetworkActivity',
    'Get-DbaInstanceProtocol',
    'Install-DbatoolsWatchUpdate',
    'Uninstall-DbatoolsWatchUpdate',
    'Watch-DbatoolsUpdate',
    'Get-DbaPrivilege',
    'Get-DbaMsdtc',
    'Get-DbaPageFileSetting',
    'Copy-DbaCredential',
    'Test-DbaConnection',
    'Reset-DbaAdmin',
    'Copy-DbaLinkedServer',
    'Get-DbaDiskSpace',
    'Test-DbaDiskAllocation',
    'Test-DbaPowerPlan',
    'Set-DbaPowerPlan',
    'Test-DbaDiskAlignment',
    'Get-DbaStartupParameter',
    'Get-DbaSpn',
    'Test-DbaSpn',
    'Set-DbaSpn',
    'Remove-DbaSpn',
    'Get-DbaService',
    'Get-DbaClientProtocol',
    'Get-DbaWindowsLog',
    # WPF
    'Show-DbaInstanceFileSystem',
    'Show-DbaDbList',
    # AD?
    'Test-DbaWindowsLogin',
    'Find-DbaLoginInGroup',
    # 3rd party non-core DLL or exe
    'Export-DbaDacPackage', # relies on sqlpackage.exe
    # Unknown
    'Get-DbaErrorLog',
    'Get-DbaManagementObject',
    'Test-DbaManagementObject'
)

# If a developer or appveyor calls the psm1 directly, they want all functions
# So do not explicitly export because everything else is then implicitly excluded
if (-not $script:multiFileImport) {
    $exports =
    @(if (($PSVersionTable.Platform)) {
            if ($PSVersionTable.Platform -ne "Win32NT") {
                $script:xplat
            } else {
                $script:xplat
                $script:windowsonly
            }
        } else {
            $script:xplat

            $script:windowsonly
            $script:noncoresmo
        })

    $aliasExport = @(
        foreach ($k in $script:Renames.Keys) {
            $k
        }
        foreach ($k in $script:Forever.Keys) {
            $k
        }
        foreach ($c in $script:shortcuts.Keys) {
            $c
        }
    )

    Export-ModuleMember -Alias $aliasExport -Function $exports -Cmdlet Select-DbaObject, Set-DbatoolsConfig

    Write-ImportTime -Text "Exported module member"
} else {
    Export-ModuleMember -Alias * -Function * -Cmdlet *
}

$timeout = 20000
$timeSpent = 0
while ($script:smoRunspace.Runspace.RunspaceAvailability -eq 'Busy') {
    [Threading.Thread]::Sleep(10)
    $timeSpent = $timeSpent + 50

    if ($timeSpent -ge $timeout) {
        Write-Warning @"
The module import has hit a timeout while waiting for some background tasks to finish.
This may result in some commands not working as intended.
This should not happen under reasonable circumstances, please file an issue at:
https://github.com/sqlcollaborative/dbatools/issues
Or contact us directly in the #dbatools channel of the SQL Server Community Slack Channel:
https://dbatools.io/slack/
Timeout waiting for temporary runspaces reached! The Module import will complete, but some things may not work as intended
"@
        $global:smoRunspace = $script:smoRunspace
        break
    }
}

if ($script:smoRunspace) {
    $script:smoRunspace.Runspace.Close()
    $script:smoRunspace.Runspace.Dispose()
    $script:smoRunspace.Dispose()
    $script:smoRunspace = $null
}
Write-ImportTime -Text "Waiting for runspaces to finish"
$myInv = $MyInvocation
if ($option.LoadTypes -or
    ($myInv.Line -like '*.psm1*' -and
        (-not (Get-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server)
        ))) {
    Update-TypeData -AppendPath (Resolve-Path -Path "$script:PSModuleRoot\xml\dbatools.Types.ps1xml")
    Write-ImportTime -Text "Loaded type extensions"
}
#. Import-ModuleFile "$script:PSModuleRoot\bin\type-extensions.ps1"
#Write-ImportTime -Text "Loaded type extensions"

$td = (Get-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server)
[Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleImported = $true;
$loadedModuleNames = Get-Module | Select-Object -ExpandProperty Name
if ($loadedModuleNames -contains 'sqlserver' -or $loadedModuleNames -contains 'sqlps') {
    if (Get-DbatoolsConfigValue -FullName Import.SqlpsCheck) {
        Write-Warning -Message 'SQLPS or SqlServer was previously imported during this session. If you encounter weird issues with dbatools, please restart PowerShell, then import dbatools without loading SQLPS or SqlServer first.'
        Write-Warning -Message 'To disable this message, type: Set-DbatoolsConfig -Name Import.SqlpsCheck -Value $false -PassThru | Register-DbatoolsConfig'
    }
}
#endregion Post-Import Cleanup

# SIG # Begin signature block
# MIIZawYJKoZIhvcNAQcCoIIZXDCCGVgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUFVAYO7JSXJKoIsMixtz2mZAD
# RJ2gghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# QijGGFbPQTS2Zl22dHv1VjMiLyI2skuiSpXY9aaOUjGCBEwwggRIAgEBMIGGMHIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJ
# RCBDb2RlIFNpZ25pbmcgQ0ECEAMFu4YhsKFjX7/erhIE520wCQYFKw4DAhoFAKB4
# MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQB
# gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkE
# MRYEFPQz2/2AO4xuVd1fAHoowuQATMOwMA0GCSqGSIb3DQEBAQUABIIBAGNRMd4l
# HSOxS+5POb8w91VUh5s3+EB3gm+w/RrHBXCKJAvTUu9ti+BHzeWOMzUVT51riPmN
# LMoPk1gKIQySLOYFbrzIXWMAncyIzX1VIv9Rl1UkoT+QGWKDc8+VqozNhGzGiXeD
# gLpstFIvq1wVtxVBqQeqs5XDR27oeC5VjtyRdgR1QsX9SWN0EZqZAxHcPhNdLQyN
# LVet60tesP+CbLZgFHqFhtFxoi4kWJPEJNTaX5DSrPqHdfCfYYxoU4SPvDh5f+3T
# eSJJ2GWPw4sNZP1pj7/S+ZHakeLV24Ta109kIefF6LiC6EUWzL1ADkSKkV6TvEQK
# ckGybcrQKUKwTF+hggIgMIICHAYJKoZIhvcNAQkGMYICDTCCAgkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TAJBgUrDgMCGgUAoF0w
# GAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMjEwMjIz
# MTcyMTQ2WjAjBgkqhkiG9w0BCQQxFgQUy/v27Ab6PRuAr2PGPoaxGC1Ck5gwDQYJ
# KoZIhvcNAQEBBQAEggEAua1G8ieQzgxvKoTqcNiGxq3uWtx81xc67Hakyz5UN0xN
# m90uTn6AepgIdwzql6DSOPQvtEBt6hae9uB2sfIJnKFNlSILstjErdkZm6gkqscn
# ktx78UulU9/srS04d5mTRYggzxtnmxdARz6BOVsugbbwoTOOoHYFb+TO1y1nOwYL
# eV0FWBp0zvcA+FQCZN2fvOuGnZguH+cL3HEyolKPtMXO5C6hwYD8KIKAJl06mMrQ
# XS9mkOIlfai/Kp9cyfAj60t7Y+Wt1DdTOr0bHXCjQHo73QJ2YM4jDWnsH8DGxErL
# hpS0VIx0A06FLtba8P8+Tj/tk0urvqeJM0ETBMEE/w==
# SIG # End signature block
