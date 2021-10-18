# DeploySQL

Powershell based DSC deployment of SQL Server
Scripts / templates used to install / configure a new server build.

Did you ever deploy SQL Server only to forget to change the block size for the disks?
Or do you forget to grant access to the folders, to the administrators who manage your servers?
Windows firewall rules, doh' I forget them all the time...

If so, his project is for you!

Using the power of Desired State Configuration, the following actions can be performed:

- Change the optical drive to V:\
- Configure a single or five disks with 64k allocations
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
- Ensure appropriate teams are granted access as SA and are granted file system permissions to necessary SQL folders
- Configures Windows Cluster / Availability Group
- Execute SQL Server Post Installation Configuration Script .\SQLInstanceConfiguration.ps1

## Parameters

|Parameter|Type|Default/Status|Description|
|---|---|---|---|
|Computer|\[string\[\]\]|Required - defaults to localhost|The computer(s) that will have SQL Installed|
|Instance|\<string\>|Optional|If provided will install SQL in an instance, otherwise default instance is used.|
|SQLVersion|\<string\>|Optional - defaults to SQL2019|Version of SQL Server to deploy.|
|NumberOfNonOSDrives|\<string\>|Optional - defaults to 5| Number of drives to be used for SQL Server. <br>1 drive configuration  (D:\SQLSystem, D:\SQLData, D:\SQLLog, D:\SQLTempDB, D:\SQLBackup). <br>5 Drive configuration  (D:\SQLSystem, E:\SQLData, F:\SQLLog, G:\SQLTempDB, H:\SQLBackup).|
|InstallSourcePath|\<string\>|Optional - defaults to \\currentmachine\DeploySQL|Path where installation media and scripts are located.|
|SQLEngineServiceAccount|\<psCredential\>|Optional|Credential used to executed the SQL Server Service.  When omitted will used a local managed account.|
|SQLAgentServiceAccount|\<psCredential\>|Optional|Credential used to executed the SQL Agent Service.  When omitted will used a local managed account.|
|DBAOSAdminGroup|\[string\[\]\]|Required|Active directory group used for administration of SQL Server host machine. Supports multiple accounts in an array.|
|DBASQLAdminGroup|\[string\[\]\]|Required|Active directory group used for administration of SQL Server databases and instance. Supports multiple accounts in an array.|
|IsAzureVM|switch|Optional|Switch that if present will offset all drive letters by +1.  By default without this switch the assumption is that the first non-OS drive is D:\.  In Azure the first available non-OS drive is E:\|
|SkipDriveConfig|switch|Optional|Switch used to use to prevent initial drive configuration. Default is False.|
|SkipSQLInstall|switch|Optional|Switch is used to skip SQL Server installation (will not configure firewall, SSMS, PowerPlan, Timezone).|
|NoOpticalDrive|switch|Optional|Script assumes target(s) have an optical drive.  This switch will skip configuration if not present.|
|AddOSAdminToHostAdmin|switch|Optional|switch that if included will add members of the DBAOSAdminGroup to local machine administrators.|
|IsInAvailabilityGroup|switch|Optional|Master switch that if enabled will create a Windows Cluster and a SQL Server Availability Group.|
|ClusterName|[string]|Required if -IsInAvailabilityGroup is specified.|Name of the Windows Cluster|
|ClusterIP|[System.Net.IPAddress]|Optional|If present will configure the cluster with a static IP address.  Otherwise uses DHCP.|
|SQLAGName|[string]|Required if -IsInAvailabilityGroup is specified.|Name of Availability Group|
|SQLHADREndpointPort|[UInt16]|Required if -IsInAvailabilityGroup is specified.|Port used for HADR_Endpoint.|
|SQLAGIPAddr|[System.Net.IPAddress]|Optional|If Present will configure the availability group with a static IP address.  Otherwise uses DHCP.|
|SQLAGPort|[UInt16]|Required if -IsInAvailabilityGroup is specified.|Port for Availability Group Listener.|
|SkipSQLAGListenerCreation|switch|Optional|If present will skip configuration of the SQL Listener for the availability group.|
|SkipSSMS|switch|Optional|If included will skip the installation of SSMS|
|SkipPostDeployment|switch|Optional|If included will not run SQL Server post installation scripts|
|SkipInstallIntegrityCheck|switch|Optional|If included will not run checksum verifications of required Powershell modules|
|InstallCredential|[psCredential]|Required|Credential used to install SQL Server and perform all configurations. Account should be a member of the group specified in -DBATeamGroup as well as a local administrator of the target server.|

## Getting Started

1. Ensure installation files are all unblocked (if downloaded from GitHub)

    Get-ChildItem [path to your folder] -recurse | Unblock-File

2. Ensure powershell execution mode is set to unrestricted

     Set-ExecutionPolicy Unrestricted

3. Create a file share at the root of the installation path... so c:\git\deploySQL should be available at \\\computer\deploySQL

4. Ensure the Active Directory Module for Windows Powershell feature is enabled

5. Copy the contents of [InstallPath]\PSModules to C:\ProgramFiles\WindowsPowerShell\Modules

6. Copy installation media to the [InstallPath]\InstallMedia folders as appropriate.

7. Test your installation media is intact.

    .\support\checksum.ps1

8. Pre-stage Active Directory accounts needed for install

    .\support\stage_computerObjects.ps1 -Computer 'sql01a', 'sql01b' -ClusterName 'SQLCluster1' -VirtualClusterObject 'SQLAG1' -Action create -Verbose

9. Review examples in .\support\Clustered Instance Install.ps1

## Assumptions

- Target machine is already joined to the domain.
- Credential used for installation has administrative rights to target machines.

## Known Issues

- By adding in the -IsInAvailabilityGroup switch, if you don't have the -SkipSSMS switch enabled on the first installation,
    things appear to hang.  Investigating reboot cycles to help eliminate the issue, but for the workaround, on initial cluster creation
    include the -SkipSSMS flag.  Subsequent executions should work fine.

## To-Do

- Automatic execution of all post-deployment scripts (not just hard coded items)
- Configure SQL Server performance baseline

## Tested Configurations

|Operating System|SQL Server Version|SSMS Version |Notes|
|---|---|---|---|
|Windows Server 2019|SQL Server 2019 Enterprise Edition - CU10|SSMS 18.9.1|Tested|
|Windows Server 2019|SQL Server 2017 Enterprise Edition - CU22|SSMS 18.9.1|Tested|
|Windows Server 2019|SQL Server 2016 Enterprise Edition - SP2 + CU17|SSMS 18.9.1|Tested|
|Windows Server 2016|SQL Server 2019 Enterprise Edition - CU10|SSMS 18.9.1|Tested|
|Windows Server 2016|SQL Server 2017 Enterprise Edition - CU22|SSMS 18.9.1|Tested|
|Windows Server 2016|SQL Server 2016 Enterprise Edition - SP2 + CU17|SSMS 18.9.1|Tested|
