[CmdletBinding()]
param ( 
   [Parameter (Mandatory = $true)] 
   [string]$Computer, 
 
   [Parameter (Mandatory = $false)] 
   [string]$Instance, 
 
   [Parameter (Mandatory = $false)] 
   [string]$InstallSourcePath = "\\$env:COMPUTERNAME\DeploySQL", 
 
   [Parameter (Mandatory = $false)] 
   [System.Management.Automation.PSCredential] 
   $InstallCredential = $host.ui.promptForCredential("Install Credential", "Please specify the credential used for service installation", $env:username, $env:USERDOMAIN) 
)
 
If ($Instance.Length -EQ 0) { 
   $SqlSvrInstance = $Computer 
   $Instance = 'MSSQLSERVER' 
} 
else {
   $SqlSvrInstance = "$Computer\$Instance" 
} 
 
Import-Module -Name dbatools 
 
Write-Verbose "Starting SQL Instance Configuration"

#Set Traceflag 3625 (prevent showing information for failed logins) 
Write-Verbose "Testing for Trace Flag 3625"
$startupFlags = Get-DbaStartupParameter -SqlInstance $SqlSvrInstance
if ($startupFlags.TraceFlags.contains(3625) -eq $false) {
   Set-DbaStartupParameter -SqlInstance $SqlSvrInstance -TraceFlag 3625 -TraceFlagOverride -Confirm:$false -Force 
   Write-Verbose "Added TraceFlag 3625 to $SqlSvrInstance"
}
 
#Rename the SA Account 
Write-Verbose "Renaming the SA Account to xAdmin"
Rename-DbaLogin -SqlInstance $SqlSvrInstance -Login sa -NewLogin xAdmin
 
#ensure renamed SA account is disabled 
Write-Verbose "Disable the SA Account"
Set-DbaLogin -SqlInstance $SqlSvrInstance -Login xAdmin -Disable 
 
#Set MAXDOP based on recommended value 
Write-Verbose "Configure MaxDOP to recommended settings"
Set-DbaMaxDop -SqlInstance $SqlSvrInstance 
 
#Set MaxMemory based on recommended value 
Write-Verbose "Configure MaxMemory to recommended settings"
Set-DbaMaxMemory -SqlInstance $SqlSvrInstance 
 
#Enable DAC 
Write-Verbose "Enable Remote Dedicated Admin Connection"
Set-DbaSpConfigure -SqlInstance $SqlSvrInstance -ConfigName RemoteDacConnectionsEnabled -Value 1
 
#Enable backup compression 
Write-Verbose "Ensure Backup Compression is Enabled"
Set-DbaSpConfigure -SqlInstance $SqlSvrInstance -ConfigName DefaultBackupCompression -Value 1 
 
#Enable Optimize for adhoc workloads 
Write-Verbose "Configure OptimizeAdHocWorkloads"
Set-DbaSpConfigure -SqlInstance $SqlSvrInstance -ConfigName OptimizeAdhocWorkloads -Value 1 
 
#Set maximum number of error logs 
Write-Verbose "Set maximum number of ErrorLogs to keep to 99"
Set-DbaErrorLogConfig -SqlInstance $SqlSvrInstance -LogCount 99
 
#temp db configurations 
Write-Verbose "Configure tempdb per recommended settings"
#$cSession = New-CimSession -ComputerName $Computer -Credential $InstallCredential 
#$totalFiles = (Get-CimInstance -CimSession $cSession -ClassName Win32_ComputerSystem).Number0fLogicalProcessors 
$totalFiles = (Get-DbaCmObject -ComputerName $Computer -ClassName Win32_ComputerSystem -Credential $InstallCredential).NumberOfLogicalProcessors
if ($totalFiles -ge 8) { $totalFiles = 8 }
$fileSize = (512 * $totalFiles) 
Set-DbaTempDbConfig -SqlInstance $SqlSvrInstance -DataFileSize $fileSize -DataFileCount $totalFiles 
 
#create server audits 
Write-Verbose "Create SQL Server Audit"
Invoke-DbaQuery -SqlInstance $SqlSvrInstance -Database master -File "$InstallSourcePath\Scripts\Create Server Audit.sql"
 
Write-Verbose "Create standard backup plan - https://ola.hallengren.com/downloads.html"
#needed to move to Invoke-SqlCMD instead of Invoke-DBAQuery due to an issue where the Maintenance solution script is too large
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -InputFile "$InstallSourcePath\Scripts\MaintenanceSolution.sql" 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -InputFile "$InstallSourcePath\Scripts\MaintenanceSolution-Configuration.sql" 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -InputFile "$InstallSourcePath\Scripts\MaintenanceSolution-Scheduling.sql" 
 
#install who is active 
Write-Verbose "Install Who_Is_Active - http://whoisactive.com/downloads/"
Invoke-DbaQuery -SqlInstance $SqlSvrInstance -Database master -File "$InstallSourcePath\Scripts\who_is_active.sql" 
 
#install sp_blitz 
Write-Verbose "Install sp_Blitz - https://www.brentozar.com/blitz/"
Invoke-DbaQuery -SqlInstance $SqlSvrInstance -Database master -File "$InstallSourcePath\Scripts\sp_Blitz.sql" 

 
#agent history configuration 
Write-Verbose "Configure DBA Agent history retention"
Set-DbaAgentServer -SqlInstance $SqlSvrInstance -MaximumHistoryRows 10000 -MaximumJobHistoryRows 1000 
 
#Grant additional space to Master DB 
Write-Verbose "Grant additional space to Master & MSDB databases"
Invoke-DbaQuery -SqlInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [master] MODIFY FILE (NAME = N'master', FILEGROWTH = 10MB, SIZE = 50MB)" 
Invoke-DbaQuery -SqlInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [master] MODIFY FILE (NAME = N'mastlog', FILEGROWTH = 10MB, SIZE = 10MB)" 
 
#Grant additional space to MSDB 
Invoke-DbaQuery -SqlInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [msdb] MODIFY FILE (NAME = N'MSDBData', FILEGROWTH = 50MB, SIZE = 100MB)" 
Invoke-DbaQuery -SqlInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [msdb] MODIFY FILE (NAME = N'MSDBlog', FILEGROWTH = 10MB, SIZE = 30MB)" 
 
#Set configurations for Model database 
Write-Verbose "Configure Model DB"
Set-DbaDbRecoveryModel -SqlInstance $SqlSvrInstance -RecoveryModel Full -Database Model -Confirm:$false -Verbose 
Invoke-DbaQuery -SqlInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [model] MODIFY FILE (NAME = N'modeldev', FILEGROWTH = 64MB)" 
Invoke-DbaQuery -SqlInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [model] MODIFY FILE (NAME = N'modellog', FILEGROWTH = 64MB)" 
Invoke-DbaQuery -SqlInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [model] SET PAGE_VERIFY CHECKSUM WITH NO_WAIT" 
Invoke-DbaQuery -SqlInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [model] SET AUTO_CLOSE OFF WITH NO_WAIT" 
Invoke-DbaQuery -SqlInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [model] SET AUTO_SHRINK OFF WITH NO_WAIT" 
 
Write-Verbose "Restart SQL Service to ensure all settings take effect"
Set-DbaCmConnection -ComputerName $Computer -OverrideExplicitCredential 
Restart-DbaService -ComputerName $Computer -InstanceName $Instance -Type Engine -Credential $InstallCredential -Force 

Write-Verbose "Completed SQL Instance Configuration"
