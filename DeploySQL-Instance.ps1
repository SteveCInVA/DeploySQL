<#
 .SYNOPSIS

 SQL Server deployment script.

 .DESCRIPTION
 ###########################################################
 Copyright (C) 2021 Microsoft Corporation

    Disclaimer:
    This is SAMPLE code that is NOT production ready. It is the sole intention of this code to provide a proof of concept as a
    learning tool for Microsoft Customers. Microsoft does not provide warranty for or guarantee any portion of this code
    and is NOT responsible for any affects it may have on any system it is executed on or environment it resides within.
    Please use this code at your own discretion!

    Additional legalese:

    This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment.
    THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED ""AS IS"" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
    INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
    We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute
    the object code form of the Sample Code, provided that You agree:
    (i) to not use Our name, logo, or trademarks to market Your software product in which the Sample Code is embedded;
    (ii) to include a valid copyright notice on Your software product in which the Sample Code is embedded; and
    (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys' fees,
    that arise or result from the use or distribution of the Sample Code.
 ###########################################################

Script that was developed by the SQL team to deploy SQL Server in a known configuration to targeted servers.
 High level tasks performed by this script:

 - Copy required PowerShell modules to target computer
 - Configure Optical Drive to V:\
 - Configure Non-OS Drive(s) 1 or 5 disk configurations supported
 - Configure target computer for high performance power setting
 - Ensure .NET 4.5 is installed
 - Configure machine to Eastern Time Zone (GMT-4/5 depending on Daylight Savings)
 - Copy installation media to C:\Software
 - Install SQL Engine / Connectivity Tools / Backwards Compatibility
 - Installed provided SQL Service Packs / Cumulative Updates
 - Configure Windows Firewall rule for SQL Server
 - Configure Windows Firewall rule for SQL Browser
 - Install current version of SQL Server Management Studio
 - Disable Client Improvement Experience
 - Ensure DBATeam is granted file system permissions to necessary SQL folders
 - Configures Windows Cluster / Availability Group
 - Execute SQL Server Post Installation Configuration Script .\SQLInstanceConfiguration.ps1

 #####
 Known Issues
 - By adding in the -IsInAvailabilityGroup switch, if you don't have the -SkipSSMS switch enabled on the first installation,
    things appear to hang.  Investigating reboot cycles to help eliminate the issue, but for the workaround, on initial cluster creation
    include the -SkipSSMS flag.  Subsequent executions should work fine.

 .INPUTS

 -Computer [string[]] - Defaults to localhost

 [-Instance <string>] - If provided will install SQL in an instance, otherwise default instance is used.

 [-SQLVersion <string>] - Enumeration of supported SQL Version. Defaults to SQL2019

 [-NumberOfNonOSDrives <string>] - Number of drives to be used for SQL Server. Default is 5 (D:\SQLSystem, E:\SQLData, F:\SQLLog, G:\SQLTempDB, H:\SQLBackup). Optional config for single drive install.

 [-InstallSourcePath <string>] - Path to installation base. Should be a UNC Path such as \\server\SQLInstallation

 [-SQLEngineServiceAccount <psCredential>] - Credential used to execute the SQL Server Service

 [-SQLAgentServiceAccount <psCredential>] - Credential used to execute the SQL Agent Service

 [-DBAOSAdminGroup [string[]]] - Active directory group used for administration of SQL Server host machine.

 [-DBASQLAdminGroup [string[]]] - Active directory group used for administration of SQL Server databases and service.

 [-IsAzureVM] - Switch that if present will offset all drive letters by +1.  By default without this switch the assumption is that the first non-OS drive is D:\.  In Azure the first available non-OS drive is E:\

 [-SkipDriveConfig] - Switch used to use to prevent initial drive configuration. Default is False.

 [-SkipSQLInstall] - Switch is used to skip SQL Server installation (will not configure firewall, SSMS, PowerPlan, Timezone)

 [-NoOpticalDrive] - Script assumes target(s) have an optical drive.  This switch will skip configuration if not present.

 [-AddOSAdminToHostAdmin] - switch that if included will add members of the DBAOSAdminGroup to local machine administrators

 [-IsInAvailabilityGroup] - Master switch that if enabled will create a Windows Cluster and a SQL Server Availability Group.
 [-ClusterName [string]] - Required if -IsInAvailabilityGroup is specified.  Name of the Windows Cluster
 [-ClusterIP [System.Net.IPAddress]] - optional. if present will configure the cluster with a static IP address.  Otherwise uses DHCP.
 [-SQLAGName [string]] - Required if -IsInAvailabilityGroup is specified.  Name of Availability Group
 [-SQLHADREndpointPort[UInt16]] - required if -IsInAvailabilityGroup is specified.  Port used for HADR_Endpoint
 [-SQLAGIPAddr [System.Net.IPAddress]] - optional. If Present will configure the availability group with a static IP address.  Otherwise uses DHCP.
 [-SQLAGPort [UInt16]] - required if -IsInAvailabilityGroup is specified.  Port for Availability Group Listener
 [-SkipSQLAGListenerCreation] - optional.  If present will skip configuration of the SQL Listener for the availability group

 [-SkipSSMS] - switch that if included will skip the installation of SSMS

 [-SkipPostDeployment] - switch that if included will not run SQL Server post installation scripts

 -InstallCredential <psCredential> - Credential used to install SQL Server and perform all configurations. Account should be a member of the group specified in -DBATeamGroup as well as a local administrator of the target server.

 .EXAMPLE

 .\DeploySQL-Instance.ps1 -Computer computer1 -Instance Inst. 1 -SQLVersion SQL2017 -NumberOfNonOSDrives 5 -InstallSourcePath '\\computerShare\SQLInstall' -DBAOSAdminGroup domain\DBATeamMembers -DBASQLAdminGroup domain\DBATeamMembers -SkipDriveConfig False
 Would install SQL 2017 to Computer1 requiring 5 non-OS drives for installation.

 .\DeploySQL-Instance.ps1 -Computer computer2 -NumberOfNonOSDrives 1 -InstallSourcePaLh '\\computerShare\SQLInstall' -SkipDriveConfig True
 Would install SQL 2019 to Computer2 using only the D: for all files. Would not try to change any disk configurations during install.

 .NOTES

 AUTHOR: Steve Carroll - Microsoft - Sr. Customer Engineer
 SOURCE CODE AT: https://github.com/SteveCInVA/DeploySQL/

 VERSION HISTORY:
 2021/07/21 - 1.0.0 - Initial release of script
 2021/07/21 - 1.0.1 - Changed default parameter for DBATeamGroup to use local domain instead of hard-coded domain\DBATeamMembers
 - Added check to verify DBATeamGroup exists in current domain.
 2021/07/28 - 1.1.0 - Revised parameters to separate DBATeamGroup into OS administration from SQL administration
 2021/08/12 - 1.2.0 - Enabled support for multiple computers, DBAOSAdminGroup, DBASQLAdminGroup as parameters.
 - Added support for Azure by offsetting disk configuration by 1... so most environments Disk1 is the D drive, in Azure there is a D:\Temporary Storage drive that requires the offset.
 - Added support to handle if there is no optical drive present
 - Added support to ensure the required powershell modules were installed on the installing workstation
 - Added in several parameter validations
 - Moved validation procedures to external modules
 2021/08/13 - 1.3.0 - Added support of service accounts
 - fully tested sql config scripts
 2021/09/01 - 1.4.0 - Add support for availability groups
 2021/09/02 - 1.4.1 - Added support to skip availability group listener creation
 2021/09/03 - 1.4.2 - Fixed issue with overlapping ports with HADR_Endpoints

 This script makes some directory assumptions:
 1. There is a sub-folder called InstaLlMedia\SQL[XXXX] where XXXX is the SQL Server version to be deployed.
 2. All required PowerShell modules required for this script are present in the PSModules sub-folder.
 3. All post deployment scripts can be found in the SQLScripts sub-folder.
 #>

param (
    [Parameter (Mandatory = $true)]
    [string[]]$Computer = 'localhost',

    [Parameter (Mandatory = $false)]
    [string]$Instance,

    [Parameter (Mandatory = $false)]
    [ValidateSet('SQL2016', 'SQL2017', 'SQL2019')]
    [string]$SQLVersion = 'SQL2019',

    [Parameter (Mandatory = $false)]
    [ValidateSet('1', '5')]
    [string]$NumberOfNonOSDrives = '5',

    [Parameter (Mandatory = $false)]
    [string]$InstallSourcePath = "\\$env:COMPUTERNAME\DeploySQL",

    [Parameter (Mandatory = $false)]
    [System.Management.Automation.PSCredential]$SQLEngineServiceAccount,

    [Parameter (Mandatory = $false)]
    [System.Management.Automation.PSCredential]$SQLAgentServiceAccount,

    [Parameter (Mandatory = $false)]
    [string[]]$DBAOSAdminGroup = "$env:USERDOMAIN\group1",

    [Parameter (Mandatory = $false)]
    [string[]]$DBASQLAdminGroup = "$env:USERDOMAIN\group2",

    [switch]$IsAzureVM,

    [Switch]$SkipDriveConfig,

    [Switch]$SkipSQLInstall,

    [Switch]$NoOpticalDrive,

    [switch]$AddOSAdminToHostAdmin,

    #params needed for clustering
    [switch]$IsInAvailabilityGroup,
    [Parameter (Mandatory = $false)]
    [string]$ClusterName,
    [Parameter (Mandatory = $false)]
    [System.Net.IPAddress]$ClusterIP,
    [Parameter (Mandatory = $false)]
    [string]$SQLAGName,
    [Parameter (Mandatory = $false)]
    [ValidateRange(1, [UInt16]::MaxValue)]
    [UInt16]$SQLHADREndpointPort,
    [Parameter (Mandatory = $false)]
    [System.Net.IPAddress]$SQLAGIPAddr,
    [Parameter (Mandatory = $false)]
    [ValidateRange(1, [UInt16]::MaxValue)]
    [UInt16]$SQLAGPort,
    [switch]$SkipSQLAGListenerCreation,

    [switch]$SkipSSMS,

    [Switch]$SkipPostDeployment,

    [Parameter (Mandatory = $false)]
    [System.Management.Automation.PSCredential]
    $InstallCredential = $host.ui.promptForCredential("Install Credential", "Please specify the credential used for service installation", $env:USERNAME, $env:USERDOMAIN)
)

$scriptVersion = '1.4.2'
$InstallDate = Get-Date -Format "yyyy-mm-dd HH:mm:ss K"
$StartTime = $(Get-Date)

##########################################
#begin validation of parameters

#Set working directory
[string]$scriptPath = $MyInvocation.MyCommand.Path
[string]$Dir = Split-Path $scriptPath

Import-Module $dir\helperFunctions\AccountVerifications.psm1
Import-Module $dir\helperFunctions\DirectoryVerifications.psm1
Import-Module $dir\helperFunctions\Tools.psm1

#check if basic directory structure is present
if ((Test-DirectoryStructure -InstallMediaPath $dir -SQLVersion $SQLVersion) -eq $false) {
    Write-Warning "Key installation directories missing."
    $valid = $false
}

#check DBA OS Admin Group exists
foreach ($acct in $DBAOSAdminGroup) {
    if ((Test-AccountExists -AccountName $acct) -eq $False) {
        Write-Warning "Unable to find $acct in Active Directory for the DBAOSAdminGroup parameter"
        $valid = $false
    }
}

#check DBA SQL Admin Group exists
foreach ($acct in $DBASQLAdminGroup) {
    if ((Test-AccountExists -AccountName $acct) -eq $False) {
        Write-Warning "Unable to find $acct in Active Directory for the DBASQLAdminGroup parameter"
        $valid = $false
    }
}

# check SQL Engine service account if present
IF ($null -ne $SQLEngineServiceAccount) {
    if ((Test-AccountCredential -Credential $SQLEngineServiceAccount) -eq $false) {
        $valid = $false
    }
}

# check SQL agent service account if present
IF ($null -ne $SQLAgentServiceAccount) {
    if ((Test-AccountCredential -Credential $SQLAgentServiceAccount) -eq $false) {
        $valid = $false
    }
}

# check install credential is valid
IF ($null -eq $InstallCredential) {
    Write-Warning "User clicked cancel at credential prompt."
    Break
}
ELSE {
    if ((Test-AccountCredential -Credential $InstallCredential) -eq $false) {
        $valid = $false
    }
}

# test reach target computer(s)
FOREACH ($c in $Computer) {
    IF (!(Test-Connection -ComputerName $c -Quiet)) {
        Write-Warning "Unable to connect to $c"
        $valid = $false
    }
}

# test you can reach installation media
IF (!(Test-Path $InstallSourcePath)) {
    Write-Warning "Unable to connect to $InstallSourcePath"
    $valid = $false
}

# test if isInAvailabilityGroup is specified, that the cluster name and ag name is specified
IF ($IsInAvailabilityGroup.IsPresent -eq $true) {
    IF ($clusterName.length -eq 0) {
        Write-Warning "IsInAvailabilityGroup parameter is specified but ClusterName is missing"
        $valid = $false
    }
    IF ($SQLAGName.length -eq 0) {
        Write-Warning "IsInAvailabilityGroup parameter is specified but SQLAGName is missing"
        $valid = $false
    }
    IF ($SQLAGPort -eq 0) {
        Write-Warning "IsInAvailabilityGroup parameter is specified but SQLAGPort is missing"
        $valid = $false
    }
    IF ($SQLHADREndpointPort -eq 0) {
        Write-Warning "IsInAvailabilityGroup parameter is specified but SQLHADREndpointPort is missing"
        $valid = $false
    }
}

##########################################
# end of validations...  if any tests fail, quit
if ($valid -eq $false) {
    break
}

##########################################
# ensure all powershell modules exist in installing directory
#copyFiles -SourcePath "$dir\PSModules" -DestPath "$Env:HOMEDRIVE$Env:HOMEPATH\Documents\WindowsPowerShell\Modules" -Verbose
copyFiles -SourcePath "$dir\PSModules" -DestPath "$env:ProgramFiles\WindowsPowerShell\Modules" -Verbose

# get Installing Username for later
$InstallUserName = $InstallCredential.UserName


#define instance dependent variables
IF ($Instance.Length -EQ 0) {
    $SQLInstance = 'MSSQLSERVER'
    $InstancePath = ''
    $FirewallSvc = 'MSSQLSERVER'
    $SvcName = ''
}
else {
    $SQLInstance = $Instance
    $InstancePath = "\$Instance"
    $FirewallSvc = "MSSQL`$$Instance"
    $SvcName = "`$$Instance"
}

#array used to help determine drive letters
$driveLetterArr = [char[]]([int][char]'A'..[int][char]'Z')

#parameter used to handle the fact that azure VM's have a D: "Temporary Storage" disk presented
if ($IsAzureVM.IsPresent -eq $true) {
    $driveOffset = 1
}
else {
    $driveOffset = 0
}

# identify primary vs secondary computers for clustering
[System.Collections.ArrayList]$s = $Computer
$s.Remove($Computer[0]) # Secondary computers
$p = $Computer[0]   # primary computer

#Configure DrivePath Variables
switch ($NumberOfNonOSDrives) {
    1 {
        $SQLSystemDir = ($driveLetterArr[3 + $driveOffset] + ":\SQLSystem")
        $SQLUserDBDir = ($driveLetterArr[3 + $driveOffset] + ":\SQLData$InstancePath")
        $SQLUserDBLogDir = ($driveLetterArr[3 + $driveOffset] + ":\SQLLogs$InstancePath")
        $SQLTempDBDir = ($driveLetterArr[3 + $driveOffset] + ":\SQLTempDBs$InstancePath")
        $SQLTempDBLogDir = ($driveLetterArr[3 + $driveOffset] + ":\SQLTempDBs$InstancePath")
        $SQLBackupDir = ($driveLetterArr[3 + $driveOffset] + ":\SQLBackups$InstancePath")
    }
    5 {
        $SQLSystemDir = ($driveLetterArr[3 + $driveOffset] + ":\SQLSystem")
        $SQLUserDBDir = ($driveLetterArr[4 + $driveOffset] + ":\SQLData$InstancePath")
        $SQLUserDBLogDir = ($driveLetterArr[5 + $driveOffset] + ":\SQLLogs$InstancePath")
        $SQLTempDBDir = ($driveLetterArr[6 + $driveOffset] + ":\SQLTempDBs$InstancePath")
        $SQLTempDBLogDir = ($driveLetterArr[6 + $driveOffset] + ":\SQLTempDBs$InstancePath")
        $SQLBackupDir = ($driveLetterArr[7 + $driveOffset] + ":\SQLBackups$InstancePath")
    }
}

#Set dir to script location.
Set-Location $Dir

#create configuration that will copy required ps modules to target machine
Configuration InstallRequiredPSModules
{
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Node $AllNodes.NodeName
    {
        File InstallModules {
            DestinationPath = 'c:\Program Files\WindowsPowerShell\Modules\'
            SourcePath      = "$InstallSourcePath\PSModules\"
            Type            = 'Directory'
            Ensure          = 'Present'
            MatchSource     = $true
            Recurse         = $true
            Force           = $true
            Credential      = $InstallCredential
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
        LocalConfigurationManager {
            ActionAfterReboot  = 'ContinueConfiguration'
            ConfigurationMode  = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }
    }
}

#create configure drives
Configuration DriveConfiguration
{
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName StorageDsc

    Node $AllNodes.Where{ $_.OpticalDrive -eq $true }.NodeName
    {
        #Configure optical drive as V:\
        OpticalDiskDriveLetter CDRom {
            DiskId      = 1
            DriveLetter = 'V'
        }
    }

    Node $AllNodes.NodeName
    {
        ###################################
        #Configure Drive 1 for SQL System db's and binaries
        #This configuration is used in all setups
        WaitForDisk Disk1 {
            DiskId           = 1 + $driveOffset
            RetryIntervalSec = 60
            RetryCount       = 60
        }

        Disk Disk1Volume {
            DiskId             = 1 + $driveOffset
            DriveLetter        = $driveLetterArr[3 + $driveOffset] #D Drive or E drive if in azure
            FSLabel            = 'SQLSystem'
            AllocationUnitSize = 64KB
            DependsOn          = '[WaitForDisk]Disk1'
        }

        File SQLSystemFolder {
            DestinationPath = ($driveLetterArr[3 + $driveOffset] + ":\SQLSystem")
            Type            = 'Directory'
            Ensure          = 'Present'
            DependsOn       = '[Disk]Disk1Volume'
        }
    }

    Node $AllNodes.Where{ $_.NumberOfDataDrives -eq '5' }.NodeName
    {
        ###################################
        #Configure Drive 2 for SQL Data
        WaitForDisk Disk2 {
            DiskId           = 2 + $driveOffset
            RetryIntervalSec = 60
            RetryCount       = 60
        }

        Disk Disk2Volume {
            DiskId             = 2 + $driveOffset
            DriveLetter        = $driveLetterArr[4 + $driveOffset] #E Drive or F drive if in azure
            FSLabel            = 'SQLData'
            AllocationUnitSize = 64KB
            DependsOn          = '[WaitForDisk]Disk2'
        }

        File SQLDataFolder {
            DestinationPath = ($driveLetterArr[4 + $driveOffset] + ":\SQLData")
            Type            = 'Directory'
            Ensure          = 'Present'
            DependsOn       = '[Disk]Disk2Volume'
        }
        ###################################
        #Configure Drive 3 for SQL Logs
        WaitForDisk Disk3 {
            DiskId           = 3 + $driveOffset
            RetryIntervalSec = 60
            RetryCount       = 60
        }

        Disk Disk3Volume {
            DiskId             = 3 + $driveOffset
            DriveLetter        = $driveLetterArr[5 + $driveOffset] #F Drive or G drive if in azure
            FSLabel            = 'SQLLogs'
            AllocationUnitSize = 64KB
            DependsOn          = '[WaitForDisk]Disk3'
        }

        File SQLLogsFolder {
            DestinationPath = ($driveLetterArr[5 + $driveOffset] + ":\SQLLogs")
            Type            = 'Directory'
            Ensure          = 'Present'
            DependsOn       = '[Disk]Disk3Volume'
        }
        ###################################
        #Configure Drive 4 for SQL TempDBs
        WaitForDisk Disk4 {
            DiskId           = 4 + $driveOffset
            RetryIntervalSec = 60
            RetryCount       = 60
        }

        Disk Disk4Volume {
            DiskId             = 4 + $driveOffset
            DriveLetter        = $driveLetterArr[6 + $driveOffset] #G Drive or H drive if in azure
            FSLabel            = 'SQLTempDBs'
            AllocationUnitSize = 64KB
            DependsOn          = '[WaitForDisk]Disk4'
        }

        File SQLTempDBsFolder {
            DestinationPath = ($driveLetterArr[6 + $driveOffset] + ":\SQLTempDBs")
            Type            = 'Directory'
            Ensure          = 'Present'
            DependsOn       = '[Disk]Disk4Volume'
        }
        ###################################
        #Configure Drive 5 for SQL Backups
        WaitForDisk Disk5 {
            DiskId           = 5 + $driveOffset
            RetryIntervalSec = 60
            RetryCount       = 60
        }

        Disk Disk5Volume {
            DiskId             = 5 + $driveOffset
            DriveLetter        = $driveLetterArr[7 + $driveOffset] #H Drive or I drive if in azure
            FSLabel            = 'SQLBackups'
            AllocationUnitSize = 64KB
            DependsOn          = '[WaitForDisk]Disk5'
        }

        File SQLBackupsFolder {
            DestinationPath = ($driveLetterArr[7 + $driveOffset] + ":\SQLBackups")
            Type            = 'Directory'
            Ensure          = 'Present'
            DependsOn       = '[Disk]Disk5Volume'
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

    Node $AllNodes.Where{ $_.AddOSAdminToHostAdmin -eq $true }.NodeName
    {
        Group AdministratorsGroup {
            GroupName        = "Administrators"
            Ensure           = "Present"
            MembersToInclude = @($DBAOSAdminGroup)
            Credential       = $InstallCredential
        }
    }

    Node $AllNodes.NodeName
    {
        #Configure power plan for high performance
        PowerPlan PwrPlan {
            IsSingleInstance = 'Yes'
            Name             = 'High performance'
        }

        #Configure time zone
        TimeZone TimezoneEST {
            IsSingleInstance = 'Yes'
            TimeZone         = 'Eastern Standard Time'
        }

        WindowsFeature NetFramework {
            Name   = 'NET-Framework-45-Core'
            Ensure = 'Present'
        }

        File InstallMediaSQLENG {
            DestinationPath = "C:\Software\$SQLVersion"
            SourcePath      = "$InstallSourcePath\InstallMedia\$SQLVersion"
            Type            = 'Directory'
            Ensure          = 'Present'
            MatchSource     = $true
            Recurse         = $true
            Force           = $true
            Credential      = $InstallCredential
        }

        SQLSetup Instance {
            InstanceName          = $SQLInstance
            SourcePath            = "C:\Software\$SQLVersion"
            Features              = 'SQLENGINE,CONN,BC'
            SQLSvcAccount         = $SQLEngineServiceAccount
            AgtSvcAccount         = $SQLAgentServiceAccount
            SQLSysAdminAccounts   = @($DBASQLAdminGroup)
            InstallSQLDataDir     = "$SQLSystemDir"
            SQLUserDBDir          = "$SQLUserDBDir"
            SQLUserDBLogDir       = "$SQLUserDBLogDir"
            SQLTempDBDir          = "$SQLTempDBDir"
            SQLTempDBLogDir       = "$SQLTempDBLogDir"
            SQLBackupDir          = "$SQLBackupDir"
            UpdateEnabled         = $true
            UpdateSource          = "C:\Software\$SQLVersion\Updates"
            AgtSvcStartupType     = 'Automatic'
            SqlSvcStartupType     = 'Automatic'
            BrowserSvcStartupType = 'Automatic'
            DependsOn             = '[File]InstallMediaSQLENG', '[WindowsFeature]NetFramework'
        }

        Firewall SQLInstanceFirewall {
            Name        = "SQL Service - $SQLInstance"
            DisplayName = "SQL Server - $SQLInstance Instance"
            Ensure      = 'Present'
            Enabled     = 'True'
            Profile     = ('Domain')
            Protocol    = 'TCP'
            Service     = $FirewallSvc
            DependsOn   = '[SQLSetup]Instance'
        }

        Firewall SQLBrowserFirewall {
            Name        = 'SQLBrowser'
            DisplayName = 'SQL Server Browser Service'
            Ensure      = 'Present'
            Enabled     = 'True'
            Profile     = ('Domain')
            Protocol    = 'Any'
            Service     = 'SQLBrowser'
            DependsOn   = '[SQLSetup]Instance'
        }

        #Ensure CEIP service is disabled
        Service DisableCEIP {
            Name        = "SQLTELEMETRY$SvcName"
            StartupType = 'disabled'
            State       = 'Stopped'
            DependsOn   = '[SQLSetup]Instance'
        }

        #Grant DBATeam to file system
        NTFSAccessEntry SQLSystemFarmAdmins {
            Path              = "$SQLSystemDir"
            AccessControlList = @(
                foreach ($user in $DBAOSAdminGroup) {
                    NTFSAccessControlList {
                        Principal          = $user
                        ForcePrincipal     = $true
                        AccessControlEntry = @(
                            NTFSAccessControlEntry {
                                AccessControlType = 'Allow'
                                FileSystemRights  = 'FullControl'
                                Inheritance       = 'This folder subfolders and files'
                                Ensure            = 'Present'
                            }
                        )
                    }
                }
            )
            Force             = $False
            DependsOn         = '[SQLSetup]Instance'
        }

        NTFSAccessEntry SQLDataFarmAdmins {
            Path              = "$SQLUserDBDir"
            AccessControlList = @(
                foreach ($user in $DBAOSAdminGroup) {
                    NTFSAccessControlList {
                        Principal          = $user
                        ForcePrincipal     = $true
                        AccessControlEntry = @(
                            NTFSAccessControlEntry {
                                AccessControlType = 'Allow'
                                FileSystemRights  = 'FullControl'
                                Inheritance       = 'This folder subfolders and files'
                                Ensure            = 'Present'
                            }
                        )
                    }
                }
            )
            Force             = $False
            DependsOn         = '[SQLSetup]Instance'
        }

        NTFSAccessEntry SQLLogsFarmAdmins {
            Path              = "$SQLUserDBLogDir"
            AccessControlList = @(
                foreach ($user in $DBAOSAdminGroup) {
                    NTFSAccessControlList {
                        Principal          = $user
                        ForcePrincipal     = $true
                        AccessControlEntry = @(
                            NTFSAccessControlEntry {
                                AccessControlType = 'Allow'
                                FileSystemRights  = 'FullControl'
                                Inheritance       = 'This folder subfolders and files'
                                Ensure            = 'Present'
                            }
                        )
                    }
                }
            )
            Force             = $False
            DependsOn         = '[SQLSetup]Instance'
        }

        NTFSAccessEntry SQLTempDBFarmAdmins {
            Path              = "$SQLTempDBDir"
            AccessControlList = @(
                foreach ($user in $DBAOSAdminGroup) {
                    NTFSAccessControlList {
                        Principal          = $user
                        ForcePrincipal     = $true
                        AccessControlEntry = @(
                            NTFSAccessControlEntry {
                                AccessControlType = 'Allow'
                                FileSystemRights  = 'FullControl'
                                Inheritance       = 'This folder subfolders and files'
                                Ensure            = 'Present'
                            }
                        )
                    }
                }
            )
            Force             = $False
            DependsOn         = '[SQLSetup]Instance'
        }

        NTFSAccessEntry SQLBackupsFarmAdmins {
            Path              = "$SQLBackupDir"
            AccessControlList = @(
                foreach ($user in $DBAOSAdminGroup) {
                    NTFSAccessControlList {
                        Principal          = $user
                        ForcePrincipal     = $true
                        AccessControlEntry = @(
                            NTFSAccessControlEntry {
                                AccessControlType = 'Allow'
                                FileSystemRights  = 'FullControl'
                                Inheritance       = 'This folder subfolders and files'
                                Ensure            = 'Present'
                            }
                        )
                    }
                }
            )
            Force             = $False
            DependsOn         = '[SQLSetup]Instance'
        }

        Registry VersionStamp {
            Ensure    = "Present"
            Key       = "HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft SQL Server\DeploySQL\$SQLInstance"
            ValueName = "InstallScriptVersion"
            ValueData = "$scriptVersion"
        }
        Registry InstalledBy {
            Ensure    = "Present"
            Key       = "HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft SQL Server\DeploySQL\$SQLInstance"
            ValueName = "InstalledBy"
            ValueData = "$env:username"
        }
        Registry InstalledDate {
            Ensure    = "Present"
            Key       = "HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft SQL Server\DeploySQL\$SQLInstance"
            ValueName = "InstalledDate"
            ValueData = $InstallDate
        }
        Registry InstallParams {
            Ensure    = "Present"
            Key       = "HKEY_LOCAL_MACHINE\Software\Microsoft\Microsoft SQL Server\DeploySQL\$SQLInstance"
            ValueType = "MultiString"
            ValueName = "InstallParameters"
            ValueData = @(
                "Computer=$Computer",
                "Instance=$Instance",
                "SQLVersion=$SQLVersion",
                "NumberOfNonOSDrives=$NumberOfNonOSDrives",
                "InstallSourcePath=$InstallSourcePath",
                "SQLEngineServiceAccount=$SQLEngineServiceAccount",
                "SQLAgentServiceAccount=$SQLAgentServiceAccount",
                "DBAOSAdminGroup=$DBAOSAdminGroup",
                "DBASQLAdminGroup=$DBASQLAdminGroup",
                "IsAzureVM=$IsAzureVM",
                "SkipDriveConfig=$SkipDriveConfig",
                "SkipSQLInstall=$SkipSQLInstall",
                "NoOpticalDrive=$NoOpticalDrive",
                "AddOSAdminToHostAdmin=$AddOSAdminToHostAdmin",
                "IsInAvailabilityGroup=$IsInAvailabilityGroup",
                "ClusterName=$ClusterName",
                "ClusterIP=$ClusterIP",
                "SQLAGName=$SQLAGName",
                "SQLHADREndpointPort=$SQLHADREndpointPort",
                "SQLAGIPAddr=$SQLAGIPAddr",
                "SQLAGPort=$SQLAGPort",
                "SkipSQLAGListenerCreation=$SkipSQLAGListenerCreation",
                "SkipSSMS=$SkipSSMS",
                "SkipPostDeployment=$SkipPostDeployment",
                "InstallCredential=$InstallUserName"
            )
        }
    }

    Node $AllNodes.Where{ $_.SkipSSMS -eq $false }.NodeName
    {
        #Copy SSMS media
        File InstallMediaSSMS {
            DestinationPath = 'C:\Software\SSMS'
            SourcePath      = "$InstallSourcePath\InstallMedia\SQLManagementStudio"
            Type            = 'Directory'
            Ensure          = 'Present'
            MatchSource     = $true
            Recurse         = $true
            Force           = $true
            Credential      = $InstallCredential
        }

        #SSMS Installation
        Package SSMS {
            Ensure    = 'Present'
            Name      = 'SSMS-Setup-ENU.exe'
            Path      = 'c:\Software\SSMS\SSMS-Setup-ENU.exe'
            Arguments = '/install /quiet /norestart /DoNotInstallAzureDataStudio=1'
            ProductID = '{FFEDA3B1-242E-40C2-BB23-7E3B87DAC3C1}' ## this product id is associated to SSMS 18.9.1
            DependsOn = '[File]InstallMediaSSMS', '[SQLSetup]Instance'
        }

        Script RebootAfterSSMS {
            GetScript  = {
                $x = (Test-PendingReboot -SkipConfigurationManagerClientCheck | Select-Object IsRebootPending)
                Write-Verbose ("IsRebootPending = " + $x.IsRebootPending)
                return @{ Result = "!$x.IsRebootPending" }
            }

            SetScript  = {
                Write-Verbose "Restarting Server"
                Restart-Computer -Force
            }
            TestScript = {
                $x = (Test-PendingReboot -SkipConfigurationManagerClientCheck | Select-Object IsRebootPending)
                Write-Verbose ("IsRebootPending = " + $x.IsRebootPending)
                !$x.IsRebootPending
            }
            DependsOn  = "[Package]SSMS"
        }
        Log LogCompletion {
            Message   = "After reboot of SSMS"
            DependsOn = "[Script]RebootAfterSSMS"
        }

    }
}

Configuration ConfigureCluster
{
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ComputerManagementDsc
    Import-DscResource -ModuleName xFailoverCluster

    #base feature install
    Node $AllNodes.NodeName
    {
        PendingReboot BeforeClusterFeature {
            Name = "BeforeClusterFeature"
        }
        WindowsFeature FailoverFeature {
            Ensure    = "Present"
            Name      = "Failover-Clustering"
            DependsOn = "[PendingReboot]BeforeClusterFeature"
        }
        PendingReboot AfterClusterFeature {
            Name      = "AfterClusterFeature"
            DependsOn = "[WindowsFeature]FailoverFeature"
        }
        WindowsFeature RSATClusteringMgmt {
            Ensure    = "Present"
            Name      = "RSAT-Clustering-Mgmt"
            DependsOn = "[WindowsFeature]FailoverFeature", "[PendingReboot]AfterClusterFeature"
        }
        WindowsFeature RSATClusteringPowerShell {
            Ensure    = "Present"
            Name      = "RSAT-Clustering-PowerShell"
            DependsOn = "[WindowsFeature]FailoverFeature", "[PendingReboot]AfterClusterFeature"
        }
        WindowsFeature RSATClusteringCmdInterface {
            Ensure    = "Present"
            Name      = "RSAT-Clustering-CmdInterface"
            DependsOn = "[WindowsFeature]FailoverFeature", "[PendingReboot]AfterClusterFeature"
        }
    }

    Node $AllNodes.Where{ $_.NodeType -eq "Primary" }.NodeName
    {
        if ($Node.ClusterIP.length -eq 0 ) {
            # Cluster IP Address not specified - using DHCP
            xCluster createCluster {
                Name                          = $Node.ClusterName
                DomainAdministratorCredential = $InstallCredential
                DependsOn                     = "[WindowsFeature]FailoverFeature"
            }
        }
        else {
            # Cluster IP Address specified - using ClusterIP
            xCluster createCluster {
                Name                          = $Node.ClusterName
                StaticIPAddress               = $Node.ClusterIP
                DomainAdministratorCredential = $InstallCredential
                DependsOn                     = "[WindowsFeature]FailoverFeature"
            }
        }
    }
    Node $AllNodes.Where{ $_.NodeType -eq "Secondary" }.NodeName
    {
        xWaitForCluster waitForCluster {
            Name             = $Node.ClusterName
            RetryIntervalSec = 10
            RetryCount       = 60
            DependsOn        = "[WindowsFeature]FailoverFeature"
        }
        xCluster joinCluster {
            Name                          = $Node.ClusterName
            DomainAdministratorCredential = $InstallCredential
            DependsOn                     = "[xWaitForCluster]waitForCluster"
        }
    }
}

Configuration ConfigureAG
{
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xFailoverCluster
    Import-DscResource -ModuleName SqlServerDSC

    Node $AllNodes.NodeName
    {
        xWaitForCluster waitForCluster {
            Name             = $Node.ClusterName
            RetryIntervalSec = 10
            RetryCount       = 60
        }

        # Ensure SQL Engine account is granted access to server
        SqlLogin Add_WindowsUserSQLEngineAcct {
            Ensure               = 'Present'
            Name                 = $SQLEngineServiceAccount.userName
            ServerName           = $Node.NodeName
            LoginType            = 'WindowsUser'
            InstanceName         = $SQLInstance
            PsDscRunAsCredential = $InstallCredential
        }
        # Add the required permissions to the sql engine service login
        SqlPermission AddNTServiceSQLEngineSvcPermissions {
            DependsOn            = '[SqlLogin]Add_WindowsUserSQLEngineAcct'
            Ensure               = 'Present'
            ServerName           = $Node.NodeName
            InstanceName         = $SQLInstance
            Principal            = $SQLEngineServiceAccount.userName
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState', 'AlterAnyEndpoint', 'ConnectSQL'
            PsDscRunAsCredential = $InstallCredential
        }

        #failure identified if the user specified the same account for the sql engine and sql agent.
        #determined root issue was a duplicate key in the generated mof file.
        if ($SQLEngineServiceAccount.userName -ne $SQLAgentServiceAccount.userName) {
            # Ensure SQL Agent account is granted access to server
            SqlLogin Add_WindowsUserSQLAgentAcct {
                Ensure               = 'Present'
                Name                 = $SQLAgentServiceAccount.userName
                ServerName           = $Node.NodeName
                LoginType            = 'WindowsUser'
                InstanceName         = $SQLInstance
                PsDscRunAsCredential = $InstallCredential
            }
            # Add the required permissions to the sql agent service login
            SqlPermission AddNTServiceSQLAgentSvcPermissions {
                DependsOn            = '[SqlLogin]Add_WindowsUserSQLAgentAcct'
                Ensure               = 'Present'
                ServerName           = $Node.NodeName
                InstanceName         = $SQLInstance
                Principal            = $SQLAgentServiceAccount.userName
                Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState', 'AlterAnyEndpoint', 'ConnectSQL'
                PsDscRunAsCredential = $InstallCredential
            }
        }

        # Ensure cluster account is granted access to server
        SqlLogin Add_WindowsUserClusSvc {
            Ensure               = 'Present'
            Name                 = 'NT Service\ClusSvc'
            ServerName           = $Node.NodeName
            LoginType            = 'WindowsUser'
            InstanceName         = $SQLInstance
            PsDscRunAsCredential = $InstallCredential
        }
        # Add the required permissions to the cluster service login
        SqlPermission AddNTServiceClusSvcPermissions {
            DependsOn            = '[SqlLogin]Add_WindowsUserClusSvc'
            Ensure               = 'Present'
            ServerName           = $Node.NodeName
            InstanceName         = $SQLInstance
            Principal            = 'NT SERVICE\ClusSvc'
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
            PsDscRunAsCredential = $InstallCredential
        }

        # Ensure the HADR option is enabled for the instance
        SqlAlwaysOnService EnableHADR {
            Ensure               = 'Present'
            InstanceName         = $SQLInstance
            ServerName           = $Node.NodeName
            PsDscRunAsCredential = $InstallCredential
        }
        # Create a DatabaseMirroring endpoint
        SqlEndpoint HADREndpoint {
            EndPointName         = ("Hadr_Endpoint-" + $Node.InstanceName)
            EndpointType         = 'DatabaseMirroring'
            Ensure               = 'Present'
            Port                 = $Node.HADREndpointPort
            ServerName           = $Node.NodeName
            InstanceName         = $SQLInstance

            PsDscRunAsCredential = $InstallCredential
        }
        # Add permission of Service Account to each Endpoint
        SqlEndpointPermission 'SQLConfigureEndpointPermission' {
            Ensure               = 'Present'
            Name                 = ("Hadr_Endpoint-" + $Node.InstanceName)
            ServerName           = $Node.NodeName
            InstanceName         = $SqlInstance
            Principal            = $SQLEngineServiceAccount.userName
            Permission           = 'CONNECT'
            DependsOn            = '[SQLEndpoint]HADREndpoint'

            PsDscRunAsCredential = $SqlAdministratorCredential
        }
        if ($Node.NodeType -eq 'Primary') {
            SQLAG AddAG {
                Ensure                = 'Present'
                Name                  = $Node.AvailabilityGroupName
                ServerName            = $Node.NodeName
                InstanceName          = $SqlInstance
                AvailabilityMode      = 'SynchronousCommit'
                FailoverMode          = 'Automatic'
                DatabaseHealthTrigger = $true
                DtcSupportEnabled     = $true
                DependsOn             = '[SqlEndpointPermission]SQLConfigureEndpointPermission', '[SQLAlwaysOnService]EnableHADR', '[SqlPermission]AddNTServiceClusSvcPermissions'

                PsDscRunAsCredential  = $InstallCredential
            }
            if ($node.SkipSQLAGListenerCreation -eq $false) {
                # handle if the server is configured with DHCP or static addresses
                if ($node.AvailabilityGroupIP.length -gt 0) {
                    SQLAGListener AGListener {
                        Ensure               = 'Present'
                        ServerName           = $Node.NodeName
                        InstanceName         = $SqlInstance
                        AvailabilityGroup    = $Node.AvailabilityGroupName
                        Name                 = $Node.AvailabilityGroupName
                        Port                 = $Node.AvailabilityGroupPort
                        IPAddress            = $Node.AvailabilityGroupIP
                        DependsOn            = '[SQLAG]AddAG'

                        PsDscRunAsCredential = $InstallCredential
                    }
                }
                else {
                    SQLAGListener AGListener {
                        Ensure               = 'Present'
                        ServerName           = $Node.NodeName
                        InstanceName         = $SqlInstance
                        AvailabilityGroup    = $Node.AvailabilityGroupName
                        Name                 = $Node.AvailabilityGroupName
                        Port                 = $Node.AvailabilityGroupPort
                        DHCP                 = $True
                        DependsOn            = '[SQLAG]AddAG'

                        PsDscRunAsCredential = $InstallCredential
                    }
                }
            }

        }
        if ($Node.NodeType -eq 'Secondary') {
            WaitForAll AGWait {
                ResourceName         = '[SQLAG]AddAG'
                NodeName             = ($AllNodes | Where-Object { $_.NodeType -eq 'Primary' }).NodeName
                RetryIntervalSec     = 20
                RetryCount           = 30
                PsDscRunAsCredential = $InstallCredential
            }
            SQLAGReplica AddReplica {
                Ensure                     = 'Present'
                Name                       = $Node.SQLInstanceName
                AvailabilityGroupName      = $Node.AvailabilityGroupName
                ServerName                 = $Node.NodeName
                InstanceName               = $SqlInstance
                AvailabilityMode           = 'SynchronousCommit'
                FailoverMode               = 'Automatic'
                PrimaryReplicaServerName   = ($AllNodes | Where-Object { $_.NodeType -eq 'Primary' }).NodeName
                PrimaryReplicaInstanceName = $SqlInstance
                DependsOn                  = '[SqlEndpointPermission]SQLConfigureEndpointPermission', '[WaitForAll]AGWait'

                PsDscRunAsCredential       = $InstallCredential
            }
        }
    }
}

# Setup our configuration data object that will be used by our DSC configurations
$config = @{
    AllNodes = @(
        @{
            NodeName                    = "*"
            PSDscAllowPlainTextPassword = $true
            PsDscAllowDomainUser        = $true
            OpticalDrive                = (!$NoOpticalDrive.IsPresent)
            SkipSSMS                    = $SkipSSMS.IsPresent
            AddOSAdminToHostAdmin       = $AddOSAdminToHostAdmin.IsPresent
            NumberOfDataDrives          = $NumberOfNonOSDrives
            InstanceName                = $Instance

            ClusterName                 = $ClusterName
            ClusterIP                   = $ClusterIP
            AvailabilityGroupName       = $SQLAGName
            HADREndpointPort            = $SQLHADREndpointPort
            AvailabilityGroupIP         = $SQLAGIPAddr
            AvailabilityGroupPort       = $SQLAGPort
            SkipSQLAGListenerCreation   = $SkipSQLAGListenerCreation.IsPresent
        }
    )
}
# configuration specific to primary node
$config.AllNodes += @{
    NodeName        = $p
    NodeType        = 'Primary'
    SQLInstanceName = "$p\$Instance"
}
# configuration specific to all other nodes
foreach ($c in $s) {
    $config.AllNodes += @{
        NodeName        = $c
        NodeType        = 'Secondary'
        SQLInstanceName = "$c\$Instance"
    }
}

#$config.AllNodes | out-string | write-host

#create an array of CIM Sessions
$cSessions = New-CimSession -ComputerName $Computer -Credential $InstallCredential

#Configure LCM
LCMConfig -ConfigurationData $config -OutputPath "$Dir\MOF\LCMConfig"
try {
    Set-DscLocalConfigurationManager -Path "$Dir\MOF\LCMConfig" -CimSession $cSessions -Force
    Write-Output "Completed configurations of LCM on target machines"
}
catch {
    Write-Error -Exception $_.Exception -Message "Error configuring LCM"
    return $false
}

#Install Required PsDSCModules
InstallRequiredPSModules -ConfigurationData $config -OutputPath "$Dir\MOF\InstallPSModules"
Start-DscConfiguration -Path "$Dir\MOF\InstallPSModules" -Verbose -Wait -Force -CimSession $cSessions -ErrorAction Stop

if ($SkipDriveConfig.IsPresent -eq $false) {
    #Configure Drives
    DriveConfiguration -ConfigurationData $config -OutputPath "$Dir\MOF\DiskConfig"
    Start-DscConfiguration -Path "$Dir\MOF\DiskConfig" -Wait -Verbose -CimSession $cSessions -ErrorAction Stop
}

if ($SkipSQLInstall.IsPresent -eq $false) {
    #Install SQL
    InstallSQLEngine -ConfigurationData $config -OutputPath "$Dir\MOF\SQLConfig"
    Start-DscConfiguration -Path "$Dir\MOF\SQLConfig" -Wait -Verbose -CimSession $cSessions -ErrorAction Stop
}

#Configure IsInAvailabilityGroup
if ($IsInAvailabilityGroup.IsPresent -eq $true) {
    ConfigureCluster -ConfigurationData $config -OutputPath "$Dir\MOF\Cluster"
    Start-DscConfiguration -Path "$Dir\MOF\Cluster" -Wait -Verbose -CimSession $cSessions -ErrorAction Stop

    # visibility is lost in the above step.  pause for 5 minutes while host is rebooted, and cluster configuration is completed
    $ts = New-TimeSpan -Seconds 300
    $resumeTime = (Get-Date) + $ts
    Write-Host "##### Starting sleep cycle at " (Get-Date)
    Write-Host "##### Script will resume at " $resumeTime
    Start-Sleep -Seconds 300

    ConfigureAG -ConfigurationData $config -OutputPath "$Dir\MOF\AG"
    Start-DscConfiguration -Path "$Dir\MOF\AG" -Wait -Verbose -CimSession $cSessions -ErrorAction Stop
}

if ($SkipPostDeployment.IsPresent -eq $false) {
    foreach ($c in $Computer) {
        #Run SQLInstanceConfiguration.ps1
        If ($Instance.Length -EQ 0) {
            .\SQLInstanceConfiguration.ps1 -Computer $c -InstallSourcePath $InstallSourcePath -InstallCredential $InstallCredential
        }
        else {
            .\SQLInstanceConfiguration.ps1 -Computer $c -Instance $Instance -InstallSourcePath $InstallSourcePath -InstallCredential $InstallCredential
        }
    }
}

# remove mof files generated during install
Remove-Item "$Dir\MOF" -Force -Recurse

$elapsedTime = $(Get-Date) - $StartTime
$totalTime = "{0:HH:mm:ss}" -f ([datetime]$elapsedTime.Ticks)
Write-Host "Installation duration: $totalTime"
