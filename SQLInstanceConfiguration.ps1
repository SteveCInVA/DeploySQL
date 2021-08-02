param ( 
   [Parameter (Mandatory = $true)] 
   [string]$Computer, 
 
   [Parameter (Mandatory = $false)] 
   [string]$Instance, 
 
   [Parameter (Mandatory = $false)] 
   [string]$InstallSourcePath = '\\server\ServerBuildScripts', 
 
   [Parameter (Mandatory = $false)] 
   [System.Management.Automation.PSCredential] 
   $InstallCredential = $host.ui.promptForCredential("Install Credential", "Please specify the credential used for service installation", $env:username, $env:USERDOMAIN) 
)
 
If (Instance.Length -EQ 0) { 
   $SqlSvrInstance = $Computer 
   $Instance = 'MSSQLSERVER' 
} 
else {
   $SqlSvrInstance = "$Computer\$Instance" 
} 
 
Import-Module -Name dbatools 
 
#Set Traceflaq 3625 (prevent showing information for failed logins) 
Set-DbaStartupParameter -SQLInstance $SqlSvrInstance -TraceFlag 3625 -TraceFlagOverride -Confirm:Sfalse -Force 
 
#Rename the SA Account 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -Query "IF EXISTS (SELECT name FROM sys.sql logins WHERE name = 'sa') BEGIN ALTER LOGIN sa WITH NAME = [xAdmin] END" 
 
#ensure renamed SA account is disabled 
Set-DbaLogin -SQLInstance $SqlSvrInstance -Login xAdmin -Disable 
 
#Set MAXDOP based on recommended value 
Set-DbaMaxDOP -SQLInstance $SqlSvrInstance 
 
#Set MaxMemory based on recommended value 
Set-DbaMaxMemory -SQLInstance $SqlSvrInstance 
 
#Enable DAC 
Set-DbaSpConfigure -SqlInstance $SqlSvrInstance -ConfigName RemoteDacConnectionsEnabled -Value 
 
#Enable backup compression 
Set-DbaSpConfigure -SqlInstance $SqlSvrInstance -ConfigName DefaultBackupCompression -Value 1 
 
#Enable Optimize for adhoc workloads 
Set-DbaSpConfigure -SqlInstance $SqlSvrInstance -ConfigName OptimizeAdhocWorkloads -Value 1 
 
#Set maximum number of error logs 
Set-DbaErrorLogConfig -SQLInstance $SqlSvrInstance -LogCount 
 
#temp db configurations 
$totalFiles = (Get-CimInstance -CimSession $c -ClassName Win32 ComputerSystem).Number0fLogicalProcessors 
if ($totalFiles -ge 8) { $totalFiles = 8 }
$fileSize = (512 * $totalFiles) 
Set-DbaTempDbConfig -SqlInstance $SqlSvrInstance -DataFileSize $fileSize -DataFileCount $totalFiles 
 
#create server audits 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -InputFile "$InstallSourcePath\SQLScripts\Create Server Audit.sql" 
 
#ola's backup configs 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -InputFile "$InstallSourcePath\SQLScripts\MaintenanceSolution.sql" 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -InputFile "$InstallSourcePath\SQLScripts\MaintenanceSolution-Configurations.sql" 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -InputFile "$InstallSourcePath\SQLScripts\MaintenanceSolution-Scheduling.sql" 
 
#install who is active 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -InputFile "$InstallSourcePath\SQLScripts\who is active v11 32.sql" 
 
#install sp_blitz 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -InputFile "$InstallSourcePath\SQLScripts\sp Blitz.sql" 
 
#agent history configuration 
Set-DbaAgentServer -SQLInstance $SqlSvrInstance -MaximumHistoryRows 10000 MaximumJobHistoryRows 1000 
 
#Grant additional space to Master DB 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [master] MODIFY FILE (NAME = N'master' FILEGROWTH = 10MB, SIZE = 50MB)" 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [master] MODIFY FILE (NAME - N'mastlog', FILEGROWTH = 10MB, SIZE = 10MB)" 
 
#Grant additional space to MSDP 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [msdb] MODIFY FILE (NAME = N'MSDBData, FILEGROWTH = 50MB, SIZE = 100MB)" 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [msdb] MODIFY FILE (NAME = N'MSDBlog', FILEGROWTH = 10MB, SIZE = 30MB)" 
 
 
#Set configurations for Model database 
Set-DbaDbRecoveryModel -SqlInstance $SqlSvrInstance -RecoveryModel Full -Database Model -Confirm:$false -Verbose 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [model] MODIFY FILE (NAME - N'moaeldev', FILEGROWTH = 64MB)" 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [model] MODIFY FILE (NAME = N'modellog', FILEGROWTH = 64MB)" 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [model] SET PAGE VERIFY CHECKSUM WITH NO WAIT" 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [model] SET AUTO CLOSE OFF WITH NO WAIT" 
Invoke-Sqlcmd -ServerInstance $SqlSvrInstance -Database master -Query "ALTER DATABASE [model] SET AUTO SHRINK OFF WITH NO WAIT" 
 
Set-DbaCmConnection -ComputerName $Computer -OverrideExplicitCredential 
Restart-DbaService -ComputerName $Computer -InstanceName $Instance -Type Engine Credential $InstallCredential -Force 
