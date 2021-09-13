# DeploySQL
Powershell based DSC deployment of SQL Server
Scripts / templates used to install / configure a new server build.

Did you ever deploy SQL Server only to forget to change the block size for the disks? Or do you forget to grant acess to the folders, to the administrators who manage your servers?
This project is for you!
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
- Ensure appropate teams are granted access as SA and are granted file system permissions to necessary SQL folders 
- Configures Windows Cluster / Availability Group
- Execute SQL Server Post Installation Configuration Script .\SQLInstanceConfiguration.ps1 

## Parameters
|Parameter|Default/Status|Description|
|---|---|---|
|**Computer**|Defaults to Localhost (arrays are supported)|The computer(s) that will have SQL Installed|

## Configuration

## Examples

## Assumptions
- Target machine is already joined to the domain.
- Credential used for installation has administrative rights to target machines.

## Known Issues
- Installing an availablity group and including SSMS installation causes a deadlock scenario.

## To-Do
- Automatic execution of all post-deployment scripts
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
