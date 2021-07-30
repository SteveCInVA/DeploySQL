 <# 
 .SYNOPSIS 
 
 SQL Server deployment script. 
 
 .DESCRIPTION 
 
 Script that was developed by the PESB SQL team to deploy SQL Server in a known configuration to targeted servers. 
 High level tasks performed by this script: 
 
 - Copy required PowerShell modules to target computer 
 - Configure Optical Drive to V:\ 
 - Configure Non-OS Drive(s) 1 or 5 disk configurations supported 
 - Configure target computer for high performance power setting 
 - Ensure .NET 4.5 is installed 
 - Configure machine to Eastern Time Zone (GMT-4/5 depending on Daylight Savings) 
 - Copy installation media to C:\Software 
 - Install SQL Engine / Connectivy Tools / Backwards Compatability 
 - Installed provided SQL Service Packs / Cumulative Updates 
 - Configure Windows Firewall rule for SQL Server 
 - Configure Windows Firewall rule for SQL Browser 
 - Install current version of SQL Server Management Studio 
 - Disable Client Improvement Experience 
 - Ensure DBATeam is granted file system permissions to necessary SQL folders 
 - Restarts target computer 
 - Execute SQL Server Post Installation Configuration Script .\SQLInstanceConfiguration.ps1 
 
 For questions or issues please contact 
 
 .PARAMETER 
 
 -Computer <string> - Defaults to localhost 
 
 [-Instance <string>] - If provided will install SQL in an instance, otherwise default instance is used. 
 
 [-SQLVersion <string>] - Enumeration of supported SQL Version. Defaults to SQL2019 
 
 [-NumberOfNonOSDrives <string>] - Number of drives to be used for SQL Server. Default is 5 (D:\SQLSystem, E:\SQLData, F:\SQLLog, G:\SQLTempDB, H:\SQLBackup). Optional config for single drive install. 
 
 [-InstallSourcePath <string>] - Path to installation base. Should be a UNC Path such as \\server\SQLInstallation 
 
 [-DBAOSAdminGroup <string>] - Active directory group used for administration of SQL Server host machine. 
 
 [-DBASQLAdminGroup <string>] - Active directory group used for administration of SQL Server databases and service. 
 
 [-SkipDriveConfig <boolean>] - Boolean value (True/False) to use to prevent initial drive configuration. Default is False. 
 
 -InstallCredential <pscredential> - Credential used to install SQL Server and perform all configurations. Account should be a member of the group specified in -DBATeamGroup as well as a local administrator of the target server. 
 
 .EXAMPLE 
 
 .\DeploySQL-Instance.ps1 -Computer computerl -Instance Inst. 1 -SQLVersion SQL2017 -NumberOfNonOSDrives 5 -InstallSourcePath '\\computerShare\SQLInstall' -DBAOSAdminGroup domain\DBATeamMembers -DBASQLAdminGroup domain\DBATeamMembers -SkipDriveConfig False 
 Would install SQL 2017 to Computerl requiring 5 non-OS drives for installation. 
 
 .\DeploySQL-Instance.ps1 -Computer computer2 -NumberOfNonOSDrives 1 -InstallSourcePaLh '\\computerShare\SQLInstall' -SkipDriveConfig True 
 Would install SQL 2019 to Computer2 using only the D: for all files. Would not try to change any disk configurations during install. 
 
 .NOTES 
 
 AUTHOR: Steve Carroll - Microsoft - Sr. Customer Engineer 
 DATE: 7/27/2021 - SC - Version 1.0.0 
 SOURCE CODE AT: 
 
 VERSION HISTORY: 
 2021/07/21 - 1.0.0 - Initial release of script 
 2021/07/21 - 1.0.1 - Changed default parameter for DBATeamGroup to use local domain instead of hard-coded domain\DBATeamMembers 
 - Added check to verify DBATeamGroup exists in current domain. 
 2021/07/28 - 1.1.0 - Revised parameters to separate DBATeamGroup into OS administration from SQL administration 
 
 This script makes some directory assumptions: 
 1. There is a sub-folder called InstaLlMedia\SQL[XXXX] where XXXX is the SQL Server version to be deployed. 
 2. All required PowerShell modules required for this script are present in the PSModules sub-folder. 
 3. All post deployment scripts can be found in the SQLScripts sub-folder. 
 #> 
 
 param ( 
 [Parameter (Mandatory=$true)] 
 [string]$Computer='localhost', 
 
 [Parameter (Mandatory=$false)] 
 [string]$Instance, 

 [Parameter (Mandatory=$false)] 
 [ValidateSet('SQL2016', 'SQL2017', 'SQL2019')] 
 [string]$SQLVersion='SQL2019', 
 
 [Parameter (Mandatory=$false)] 
 [ValidateSet('1', '5')] 
 [string]$NumberOfNonOSDrives='5', 
 
 [Parameter (Mandatory=$false)] 
 [string]$InstallSourcePath='\\server\ServerBuildScripts', 
 
 [Parameter (Mandatory=$false)] 
 [string]$DBAOSAdminGroup="$env:USERDOMAIN\groupl", 
 
 [Parameter (Mandatory=$false)] 
 [string]$DBASQLAdminGroup="$env:USERDOMAIN\group2", 
 
 [Parameter (Mandatory=$false)] 
 [ValidateSet($false,$true)] 
 $SkipDriveConfig=$False, 
 
 [Parameter (Mandatory=$false)] 
 [System.Management.Automation.PSCredential] 
 $InstallCredential = $host.ui.promptForCredential("Install Credential", "Please specify the credential used for service installation", $env:USERNAME, $env:USERDOMAIN) 
 ) 
 
 $scriptVersion = '1.1.0' 
 $InstallDate = get-date -format "yyyy-mm-dd HH:mm:ss K" 
 
 IF($Instance.Length -EQ 0) 
 { 
 $SQLInstance = 'MSSQLSERVER' 
 $InstancePath = '' 
 $FirewallSvc = 'MSSQLSERVER' 
 $SvcName = '' 
 } 
 else 
 { 
 $SQLInstance = $Instance 
 $InstancePath = "\$Instance" 
 $FirewallSvc = "MSSQL`$$Instance" 
 $SvcName = "`$$Instance" 
 } 
 
 #check DBA OS Admin Group exists 
 Try 
 { 
 $r = get-adgroup -Identity $DBAOSAdminGroup.Replace("$env:USERDOMAIN\", "") 
 } 
 catch 
 { 
 Write-Warning $_.exception.Message 
 Break 
 } 
 
 #check DBA SQL Admin Group exists 
 Try 
 { 
 $r = get-adgroup -Identity $DBASQLAdminGroup.Replace("$env:USERDOMAIN\", "") 
 } 
 catch 
 { 
 Write-Warning $_.exception.Message 
 Break 
 } 
 
 # check install credential is valid 
 IF($InstallCredential -eq $null) 
 { 
 Write-Warning "User clicked cancel at credential prompt." 
 Break 
 } 
 ELSE 
 { 
 Try 
{ 
 $username = $InstallCredential.Username 
 $root = "LDAP://" + ([ADSI]'').distinguishedName 
 $domain = New-Object System.DirectoryServices.DirectoryEntry($root,$username,$InstallCredential.GetNetworkCredential().Password) 
}
 Catch 
{ 
 $_.Exception.message 
 continue 
} 
 
 If(!$domain) 
{ 
 Write-Warning "Unable to query LDAP domain" 
 break 
} 
 Else 
{ 
 if($domain.Name -eq $null) 
{ 
 Write-Warning "Unable to authenticate '$username'" 
 break 
} 
 } 
 } 
 
 
 IF(!(Test-Connection -ComputerName $Computer -Quiet)) 
 { 
 Write-Warning "Unable to connect to $Computer" 
 Break 
 } 
 
 IF(! (Test-Path $InstallSourcePath)) 
 { 
 Write-Warning "Unable to connect to $InstallSourcePath" 
 Break 
 } 
 
 #Convert passed parameter to expected boolean value 
 $SkipDriveconfig = [System.Convert]::ToBoolean($SkipDriveConfig) 
 
 #Configure DrivePath Variables 
 switch($NumberOfNonOSDrives) 
 { 
 1 { 
 $SQLUserDBDir = "D:\SQLData$InstancePath" 
 $SQLUserDBLogDir = "D:\SQLLogs$InstancePath" 
 $SQLTempDBDir = "D:\SQLTempDBs$InstancePath" 
 $SQLTempDBLogDir = "D:\SQLTempDBs$InstancePath" 
 $SQLBackupDir = "D:\SQLBackups$InstancePath" 
 } 
 5 { 
 $SQLUserDBDir = "E:\SQLData$InstancePath" 
 $SQLUserDBLogDir = "F:\SQLLogs$InstancePath" 
 $SQLTempDBDir = "G:\SQLTempDBs$InstancePath" 
 $SQLTempDBLogDir = "G:\SQLTempDBs$InstancePath" 
 $SQLBackupDir = "H:\SQLBackups$InstancePath" 
 } 
 } 
 
 #Set working directory 
 [string]$Scriptpath = $MyInvocation.MyCommand.Path 
 [string]$Dir = Split-Path $Scriptpath 
 
 #Set dir to script location. 
 Set-Location $Dir 
 
 #create configuration that will copy required ps modules to target machine 
 Configuration InstallRequiredPSModules 
 { 
 Import-DscResource -ModuleName PSDesiredStateConfiguration 
 Node $AllNodes.NodeName 
{ 
 File InstallModules 
{ 
 DestinationPath = 'c:\Program Files\WindowsPowerShell\Modules\' 
 SourcePath = "$InstallSourcePath\PSModules\" 
 Type = 'Directory' 
 Ensure = 'Present' 
 MatchSource = $true 
 Recurse = $true 
 Force = $true 
 Credential = $InstallCredential 
} 
} 
 } 
 
 #create configuration to configure the LCM to reboot during installation 
 Configuration LCMConfig 
 { 
 Import-DscResource -ModuleName PSDesiredStateConfiguration 
 Node $AllNodes.NodeName 
{
 #Set LCM for Reboot 
 LocalConfigurationManager 
{ 
 ActionAfterReboot = 'ContinueConfiguration' 
 ConfigurationMode = 'ApplyOnly' 
 RebootNodeIfNeeded = $False 
 } 
 } 
 } 
 
 #create configure 5 drive scenario 
 Configuration DriveConfiguration5 
 { 
 Import-DscResource -ModuleName PSDesiredStateConfiguration 
 Import-DscResource -ModuleName StorageDsc 
 Import-DscResource -ModuleName AccessControlDSC 
 Node $AllNodes.NodeName 
{ 
 #Configure optical drive as V:\ 
 OpticalDiskDriveLetter CDRom 
 {
 DiskId = 1 
 DriveLetter = 
 } 
 #Configure Drive 1 for SQL System db's and binaries 
 WaitForDisk Diskl 
{ 
 DiskId = 1 
 RetryIntervalSec = 60 
 RetryCount = 60 
 } 
 
 Disk DVolume 
{ 
 DiskId = 1 
 DriveLetter = 
 FSLabel = 'SQLSystem' 
 AllocationUnitSize = 64KB 
 DependsOn = '[WaitForDisk]Diskl' 
 } 
 
 File SQLSystemFolder 
{ 
 DestinationPath = 'D:\SQLSystem' 
 Type = 'Directory' 
 Ensure = 'Present' 
 DependsOn = '[Disk]DVolume' 
 } 
 
 #Configure Drive 2 for SQL Data 
 WaitForDisk Disk2 
{ 
 DiskId = 2 
 RetryIntervalSec = 60 
 RetryCount = 60 
 } 
 
 Disk EVolume 
{ 
 DiskId = 2 
 DriveLetter = 'E' 
 FSLabel = 'SQLData' 
 AllocationUnitSize = 64KB 
 DependsOn = '[WaitForDisk]Disk2' 
 } 
 
 File SQLDataFolder 
{ 
DestinationPath = 'E:\SQLData' 
 Type = 'Directory' 
 Ensure = 'Present' 
 DependsOn = '[Disk]EVolume' 
 } 
 
 #Configure Drive 3 for SQL Log files 
 WaitForDisk Disk3 
{ 
 DiskId = 3 
 RetryIntervalSec = 60 
 RetryCount = 60 
 } 
 
 Disk FVolume 
{ 
 DiskId = 3 
 DriveLetter = 'F' 
 FSLabel = 'SQLLogs' 
 AllocationUnitSize = 64KB 
 DependsOn = '[WaitForDisk]Disk3' 
 } 
 
 File SQLLogsFolder 
{ 
 DestinationPath = 'F:\SQLLogs' 
 Type = 'Directory' 
 Ensure = 'Present' 
 DependsOn = '[Disk]FVolume' 
 } 
 
 #Configure Drive 4 for SQL Temp DB files 
 WaitForDisk Disk4 
{ 
 DiskId = 4 
 RetryIntervalSec = 60 
 RetryCount = 60 
} 
 
 Disk GVolume 
{ 
 DiskId = 4 
 DriveLetter = 'G' 
 FSLabel = 'SQLTempDBs' 
 AllocationUnitSize = 64KB 
 DependsOn = '[WaitForDisk]Disk4' 
 } 
 
 File SQLTempDBSFolder 
{ 
 DestinationPath = 'G:\SQLTempDBs' 
 Type = 'Directory' 
 Ensure = 'Present' 
 DependsOn = '[Disk]GVolume' 
} 
 
 #Configure Drive 5 for SQL Backup files 
 WaitForDisk Disk5 
{ 
 DiskId = 5 
 RetryIntervalSec = 60 
 RetryCount = 60 
 } 
 
 Disk HVolume 
{ 
 DiskId = 5 
 DriveLetter = 'H' 
 FSLabel = 'SQLBackups' 
 AllocationUnitSize = 64KB 
 DependsOn = '[WaitForDisk]Disk5' 
 } 
 
 File SQLBackupsFolder 
{ 
 DestinationPath = 'H:\SQLBackups' 
 Type = 'Directory' 
 Ensure = 'Present' 
 DependsOn = '[Disk]HVolume' 
 } 
 } 
 } 
 
 #create configure 1 drive scenario 
 Configuration DriveConfigurationl 
 { 
 Import-DscResource -ModuleName PSDesiredStateConfiguration 
 Import-DscResource -ModuleName StorageDsc 
 Import-DscResource -ModuleName AccessControlDSC 
 Node $AllNodes.NodeName 
{ 
 #Configure optical drive as V:\ 
 OpticalDiskDriveLetter CDRom 
{ 
 DiskId = 1 
 DriveLetter = 
 } 
 #Configure Drive 1 for SQL System db's and binaries 
 WaitForDisk Diskl 
{ 
 DiskId = 1 
 RetryIntervalSec = 60 
 RetryCount = 60 
 } 
 
 Disk DVolume 
{ 
 DiskId = 1 
 DriveLetter = 
 FSLabel = 'SQLSystem' 
 AllocationUnitSize = 64KB 
 DependsOn = '[WaitForDisk]Diskl' 
 } 
 
 File SQLSystemFolder 
{ 
 DestinationPath = 'D:\SQLSystem' 
 Type = 'Directory' 
 Ensure = 'Present' 
 DependsOn = '[Disk]DVolume' 
 } 
 
 } 
 } 
 
 #create configuration for SQL Server 
 Configuration InstallSQLEngine 
 { 
 Import-DscResource -ModuleName PSDesiredStateConfiguration 
 Import-DscResource -ModuleName ComputerManagementDsc 
 Import-DscResource -ModuleName SqlServerDsc 
 Import-DscResource -ModuleName StorageDsc 
 Import-DscResource -ModuleName AccessControlDSC 
 Import-DscResource -ModuleName NetworkingDsc 
 
 Node $AllNodes.NodeName 
{ 
 
 #Configure power plan for high performance 
 PowerPlan PwrPlan 
{ 
 IsSingleInstance = 'Yes' 
 Name = 'High performance' 
} 
 
 #Configure time zone 
 TimeZone TimezoneEST 
{ 
 IsSingleInstance = 'Yes' 
 TimeZone = 'Eastern Standard Time' 
 } 
 
 WindowsFeature NetFramework 
{ 
 Name = 'NET-Framework-45-Core' 
 Ensure = 'Present' 
 } 
 
 File InstallMediaSQLENG 
{ 
 DestinationPath = "C:\Software\$SQLVersion" 
 SourcePath = "$InstallSourcePath\InstallMedia\$SQLVersion" 
 Type = 'Directory' 
 Ensure = 'Present' 
 MatchSource = $true 
 Recurse = $true 
 Force = $true 
 Credential = $InstallCredential 
 } 
 
 File InstallMediaSSMS 
{ 
 DestinationPath = 'C:\Software\SSMS' 
 SourcePath = "$InstallSourcePath\InstallMedia\SQLManagementStudio" 
 Type = 'Directory' 
 Ensure = 'Present' 
 MatchSource = $true 
 Recurse = $true 
 Force = $true 
 Credential = $InstallCredential 
 } 
 
 SQLSetup Instance 
{ 
 InstanceName = $SQLInstance 
 SourcePath = "C:\Software\$SQLVersion" 
 Features = 'SQLENGINE,CONN,BC' 
 SQLSysAdminAccounts = "$DBASQLAdminGroup" 
 InstallSQLDataDir = 'D:\SQLSystem' 
 SQLUserDBDir = "$SQLUserDBDir" 
 SQLUserDBLogDir = "$SQLUserDBLogDir" 
 SQLTempDBDir = "$SQLTempDBDir" 
 SQLTempDBLogDir = "$SQLTempDBLogDir" 
 SQLBackupDir = "$SQLBackupDir" 
 UpdateEnabled = $true 
 UpdateSource = "C:\Software\$SQLVersion\Updates" 
 AgtSvcStartupType = 'Automatic' 
 SqlSvcStartupType = 'Automatic' 
 BrowserSvcStartupType = 'Automatic' 
 DependsOn = '[File]InstallMediaSQLENG','[WindowsFeature]NetFramework' 
} 
 
 Firewall SQLInstanceFirewall 
{ 
 Name = "SQL Service - $SQLInstance" 
 DisplayName = "SQL Server - $SQLInstance Instance" 
 Ensure = 'Present' 
 Enabled = 'True' 
 Profile = ('Domain') 
 Protocol = 'TCP' 
 Service = $FirewallSvc 
 DependsOn = '[SQLSetup]Instance' 
 } 
 
 Firewall SQLBrowserFirewall 
{ 
 Name = 'SQLBrowser' 
 DisplayName = 'SQL Server Browser Service' 
 Ensure = 'Present' 
 Enabled = 'True' 
 Profile = ('Domain') 
 Protocol = 'Any' 
 Service = 'SQLBrowser' 
 DependsOn = '[SQLSetup]Instance' 
} 
 
 #SSMS 
 Package SSMS 
{ 
 Ensure = 'Present' 
 Name = 'SSMS-Setup-ENU.exe' 
 Path = 'c:\Software\SSMS\SSMS-Setup-ENU.exe' 
 Arguments = '/install /quiet /norestart /DoNotInstallAzureDataStudio=1' 
 ProductID = '{FFEDA3B1-242E-40C2-BB23-7E3B87DAC3C1}' ## this product id is associated to SSMS 18.9.1 
 DependsOn = '[File]InstallMediaSSMS' 
} 
 
 #Ensure CEIP service is disabled 
 Service DisableCEIP 
{ 
 Name = "SQLTELEMETRY$SvcName" 
 StartupType = 'disabled' 
 State = 'Stopped' 
 DependsOn = '[SQLSetup]Instance' 
} 
 
 #Grant DBATeam to file system 
NTFSAccessEntry SQLSystemFarmAdmins 
{ 
 Path = 'D:\SQLSystem' 
 AccessControlList = @( 
 NTFSAccessControlList 
{ 
 Principal = "$DBAOSAdminGroup" 
 ForcePrincipal = $true 
 AccessControlEntry = @( 
 NTFSAccessControlEntry 
{ 
 AccessControlType = 'Allow' 
 FileSystemRights = 'FullControl' 
 Inheritance = 'This folder subfolders and files' 
 Ensure = 'Present' 
} 
} 
} 
 ) 
 Force = $False 
 DependsOn = '[SQLSetup]Instance' 
} 
 
 NTFSAccessEntry SQLDataFarmAdmins 
{ 
 Path = "$SQLUserDBDir" 
 AccessControlList = @( 
 NTFSAccessControlList 
{ 
 Principal = "$DBAOSAdminGroup" 
 ForcePrincipal = $true 
 AccessControlEntry = @( 
 NTFSAccessControlEntry 
{ 
 AccessControlType = 'Allow' 
 FileSystemRights = 'FullControl' 
 Inheritance = 'This folder subfolders and files' 
 Ensure = 'Present' 
} 
 ) 
} 
 ) 
 Force = $False 
 DependsOn = '[SQLSetup]Instance' 
} 
 
 NTFSAccessEntry SQLLogsFarmAdmins 
{ 
 Path = "$SQLUserDBLogDir" 
 AccessControlList = @( 
 NTFSAccessControlList 
{ 
 Principal = "$DBAOSAdminGroup" 
 ForcePrincipal = $true 
 AccessControlEntry = @( 
 NTFSAccessControlEntry 
{ 
 AccessControlType = 'Allow' 
 FileSystemRights = 'FullControl' 
 Inheritance = 'This folder subfolders and files' 
 Ensure = 'Present' 
} 
 ) 
} 
 ) 
 Force = $False 
 DependsOn = '[SQLSetup]Instance' 
} 
 
 NTFSAccessEntry SQLTempDBFarmAdmins 
{ 
 Path = "$SQLTempDBDir" 
 AccessControlList = @( 
 NTFSAccessControlList 
{ 
 Principal = "$DBAOSAdminGroup" 
 ForcePrincipal = $true 
 AccessControlEntry = @( 
 NTFSAccessControlEntry 
{ 
 AccessControlType = 'Allow' 
 FileSystemRights = 'FullControl' 
 Inheritance = 'This folder subfolders and files' 
 Ensure = 'Present' 
} 
) 
} 
 ) 
 Force = $False 
 DependsOn = '[SQLSetup]Instance' 
} 
 
 NTFSAccessEntry SQLBackupsFarmAdmins 
{ 
 Path = "$SQLBackupDir" 
 AccessControlList = @(
    NTFSAccessControlList 
        { 
            Principal = "$DBAOSAdminGroup" 
            ForcePrincipal = $true 
            AccessControlEntry = @( 
                NTFSAccessControlEntry 
                { 
                    AccessControlType = 'Allow' 
                    FileSystemRights = 'FullControl' 
                    Inheritance = 'This folder subfolders and files' 
                    Ensure = 'Present' 
                } 
            ) 
        }
    ) 
 Force = $False 
 DependsOn = '[SQLSetup]Instance' 
} 
 
 Registry VersionStamp 
{ 
 Ensure = "Present" 
 Key = "HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft SQL Server\PESB Install\$SQLInstance" 
 ValueName = "InstallScriptVersion" 
 ValueData = "$scriptVersion" 
} 
 Registry InstalledBy 
{ 
 Ensure = "Present" 
 Key = "HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft SQL Server\PESB Install\$SQLInstance" 
 ValueName = "InstalledBy" 
 ValueData = "$env:username" 
} 
 Registry InstalledDate 
{ 
 Ensure = "Present" 
 Key = "HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft SQL Server\PESB Install\$SQLInstance" 
 ValueName = "InstalledDate" 
 ValueData = $InstallDate 
} 
 Registry InstallParams 
{ 
 Ensure = "Present" 
 Key = "HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft SQL Server\PESB_Install\$SQLInstance" 
 ValueType = "MultiString" 
 ValueName = "InstallParameters" 
 ValueData = @("Computer=$Computer","Instance=$Instance", "SQLVersion=$SQLVersion","NumberOfNonOSDrives=$NumberOfNonOSDrives", "InstallSourcePath=$InstallSourcePath", "DBAOSAdminGroup=$DBAOSAdminGrcup","DBASQLAdminGroup=$DBASQLAdminGroup", "SkipDriveConfig=$SkipDriveConfig","InstallCredential=$username") 
} 
 
 } 
} 
 
 # Setup our configuration data object that will be used by our DSC configurations 
 $config = @( 
 AllNodes = @( 
 @{ 
 NodeName = '*'
 PSDscAllowPlainTextPassword = $true 
 PsDscAllowDomainUser = $true 
 }
 )
 } 
 
 #create an array of CIM Sessions 
 $cSessions = New-CimSession -ComputerName $Computer -Credential $InstallCredential 
 
 #Add each computer to the data object 
 foreach($c in $cSessions) 
 { 
 $config.AllNodes += @{NodeName=$c.ComputerName} 
 } 
 
 #Create array of PSSessions that will be used to prep our target nodes 
 $pSessions = New-PSSession -ComputerName $Computer -Credential $InstallCredential 
 
 #Copy dependencies to target nodes 
 foreach($p in $pSessions){ 

 #Set the execution policy for all the targets in case it's disabled. User rights assignment makes a call to external scripts 
 Invoke-Command -session $p -ScriptBlock {Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force) 
}
 
 #Install Required PsDSCModules 
 InstallRequiredPSModules -ConfigurationData $config -OutputPath "$Dir\MOF\InstallPSModules" 
Start-DscConfiguration -Path "$Dir\MOF\InstallPSModules" -Verbose -Wait -Force CimSession $cSessions -ErrorAction SilentlyContinue 
Start-DscConfiguration -Path "$Dir\MOF\InstallPSModules" -Verbose -Wait -Force CimSession $cSessions -ErrorAction Stop 
 
 #Configure LCM 
 LCMConfig -ConfigurationData $config -OutputPath "$Dir\MOF\LCMConfig" 
 Set-DscLocalConfigurationManager -Path "$Dir\MOF\LCMConfig" -CimSession $cSessions -Verbose -Force 

#Configure Drives 
 IF ($SkipDriveConfig -eq $False) 
 { 
 switch($NumberOfNonOSDrives) 
{ 
1{ 
 DriveConfigurationl -ConfigurationData $config -OutputPath "$Dir\MOF\DiskConfig" 
}
5 { 
 DriveConfiguration5 -ConfigurationData $config -OutputPath "$Dir\MOF\DiskConfig" 
}
} 
 Start-DscConfiguration -Path "$Dir\MOF\DiskConfig" -Wait -Verbose -CimSession $cSessions -ErrorAction Stop 
}
 
#Install SQL 
InstallSQLEngine -ConfigurationData $config -OutputPath "$Dir\MOF\SQLConfig" 
Start-DscConfiguration -Path "$Dir\MOF\SQLConfig" -Wait -Verbose -CimSession $cSessions -ErrorAction Stop 

 #reboot server on completion (wait for up to 30 minutes for powershell to be available) 
restart-computer -ComputerName $Computer -Wait -for Powershell -Timeout 1800 -Delay 2 

 #Run SQLInstanceConfiguration.ps1 
 If($Instance.Length -EQ 0) 
{ 
 .\SQLInstanceConfiguration.ps1 -Computer $Computer -InstallSourcePath $InstallSourcePath -InstallCredential $InstallCredential 
}
else 
 { 
 .\SQLInstanceConfiguration.ps1 -Computer $Computer -Instance $Instance -InstallSourcePath $InstallSourcePath -InstallCredential $InstallCredential 
} 
  