<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   AUTHOR:  Steve Carroll - Microsoft - Sr. Customer Engineer
   SOURCE:  https://github.com/SteveCInVA/DeploySQL

   VERSION HISTORY:
        2021/07/21 - 1.0.0  - Initial release
        2021/07/21 - 1.0.1  - Changed default parameter for DBATeam group to default to local domain
                            - Added check to verify DBATeamGroup exists in current domain
        2021/07/28 - 1.1.0  - Revised parameters to separate OS administrators from Database adminstrators

        This script makes some directory assumptions:
        1. There is a sub-folder called InstallMedia\SQL[XXXX] where XXX is the SQL Server version to be deployed.
        2. All required PowerShell modules requred for this script are present in the PSModules sub-folder.
        3. All post deployment scripts can be found in the SQLScripts sub-folder.
.COMPONENT
   The primary component behind the DeploySQL-Instance packages

#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$computer = 'localhost',

    [Parameter(Mandatory = $false)]
    [string]$instance  , 

    [Parameter(Mandatory = $false)]
    [ValidateSet('SQL2016', 'SQL2017', 'SQL2019')]
    [string]$sqlVersion = 'SQL2019' , 

    [Parameter(Mandatory = $false)]
    [ValidateSet('1', '5')]
    [string]$numberOfNonOSDrives = '5',

    [Parameter(Mandatory = $false)]
    [string]$installSourcePath , #= '\\server\ServerBuildScripts', 

    [Parameter(Mandatory = $false)]
    [string]$dbaOSAdminGroup , #= '$env:USERDOMAIN:group1'  

    [Parameter(Mandatory = $false)]
    [string]$dbaSQLAdminGroup , #= '$env:USERDOMAIN:group2'  

    [Parameter(Mandatory = $false)]
    [ValidateSet($true, $false)]
    $skipDriveConfig = $false,

    [Parameter(Mandatory = $false)]
    [ValidateSet($true, $false)]
    $skipValidations = $false,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]
    $installCredential = $Host.ui.promptForCredential("Install Credential", "Please specify the credential used for service installation", $env:USERNAME, $env:USERDOMAIN)
)

$scriptVersion = '1.1.0'
$installDate = get-date -Format "yyyy-mm-dd HH:mm:ss K"

# convert passed parameters into boolean types
$skipDriveConfig = [System.Convert]::ToBoolean($skipDriveConfig)
$skipValidations = [System.convert]::ToBoolean($skipValidations)

# establish defaults based on parameters
if ($instance.Length -eq 0) {
    $sqlInstance = 'MSSQLSERVER'    
    $instancePath = ''
    $firewallSvc = 'MSSQLSERVER'
    $svcName = ''
}
else {
    $sqlInstance = $instance    
    $instancePath = "\$instance"
    $firewallSvc = "MSSQL`$$instance"
    $svcName = "`$$instance"    
}

# check DBA OS admin group exists
if ($skipValidations -eq $false) {
    
}
else {
    Write-Verbose "Skipped validation of groups / service accounts"
}