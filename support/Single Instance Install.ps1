clear-host

set-location (Join-Path -Path (join-path -path $env:HomeDrive -ChildPath $env:HOMEPATH) -ChildPath "\documents\source\deploysql")

$InstallUsername = "contoso\stecarr-adm"
$InstallPwd = Read-Host "Enter Admin Account Password" -AsSecureString
$InstallCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $InstallUsername, $InstallPwd


$Parameters = @{
    Computer = 'sql01a'
    SQLVersion = 'SQL2019'
    
    IsInAvailabilityGroup = $false

    NumberOfNonOSDrives = 1
    InstallSourcePath = '\\mgmt\DeploySQL'
    DBAOSAdminGroup = 'contoso\dba-os-team', 'contoso\stecarr-adm'
    DBASQLAdminGroup = 'contoso\dba-sql-team','contoso\stecarr-adm'

    IsAzureVM = $true
    SkipDriveConfig = $false
    SkipSQLInstall = $false
    SkipSSMS = $true
    AddOSAdminToHostAdmin = $true
    SkipPostDeployment = $true
    InstallCredential = $InstallCredential 
}
#Write-Output $Parameters
.\DeploySQL-Instance.ps1 @Parameters


<#
.\support\stage_computerObjects.ps1 -Computer 'sql02a' -Action create -Verbose
.\support\stage_computerObjects.ps1 -Computer 'sql01a' -Action delete -Verbose
#>