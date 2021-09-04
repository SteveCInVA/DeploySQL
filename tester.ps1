clear-host

set-location (Join-Path -Path (join-path -path $env:HomeDrive -ChildPath $env:HOMEPATH) -ChildPath "\documents\source\deploysql")
$SQLEngine = "contoso\sqlengine"
$SQLEnginePWord = Read-Host "Enter Service Account Password" -AsSecureString
$SQLEngineCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $SQLEngine, $SQLEnginePWord

$SQLAgent = "contoso\sqlagent"
$SQLAgentCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $SQLAgent, $SQLEnginePWord

$InstallUsername = "contoso\stecarr-adm"
$InstallPwd = Read-Host "Enter Admin Account Password" -AsSecureString
$InstallCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $InstallUsername, $InstallPwd


$Parameters = @{
    Computer = 'sql01a', 'sql01b','sql01c'
#    Computer = 'sql01c', 'sql01d', 'sql01e'
#    ClusterName = 'SQLCluster2'
    Instance = 'Inst1'

    IsInAvailabilityGroup = $True
    ClusterName = 'SQLCluster'
    SQLAGName = 'AGInst1'
    SQLAGPort = 1436
    SQLHADREndpointPort = 5023
    SkipSQLAGListenerCreation = $True

    NumberOfNonOSDrives = 1
    InstallSourcePath = '\\mgmt\DeploySQL'
    SQLEngineServiceAccount = $SQLEngineCredential
    SQLAgentServiceAccount = $SQLAgentCredential
    DBAOSAdminGroup = 'contoso\dba', 'contoso\stecarr-adm'
    DBASQLAdminGroup = 'contoso\dba','contoso\stecarr-adm'

    IsAzureVM = $true
    SkipDriveConfig = $false
    SkipSQLInstall = $false
    SkipSSMS = $true
    AddOSAdminToHostAdmin = $true
    SkipPostDeployment = $false
    InstallCredential = $InstallCredential 
}
#Write-Output $Parameters
.\DeploySQL-Instance.ps1 @Parameters


<#
.\support\stage_computerObjects.ps1 -Computer 'sql01a', 'sql01b' -ClusterName 'SQLCluster1' -Action delete -Verbose
.\support\stage_computerObjects.ps1 -Computer 'sql01a', 'sql01b' -ClusterName 'SQLCluster1' -Action delete -doNotDeleteComputerAccounts -Verbose

.\support\stage_computerObjects.ps1 -Computer 'sql01a', 'sql01b', 'sql01c' -ClusterName 'SQLCluster' -Action create  -Verbose
.\support\stage_computerObjects.ps1 -Computer 'sql01a', 'sql01b', 'sql01c' -ClusterName 'SQLCluster' -Action delete -Verbose

.\support\stage_computerObjects.ps1 -Computer 'sql01a', 'sql01b' -ClusterName 'SQLCluster1' -Action create -doNotDisableComputerAccounts -Verbose
.\support\stage_computerObjects.ps1 -Computer 'sql01c', 'sql01d' -ClusterName 'SQLCluster2' -Action create -doNotDisableComputerAccounts -Verbose
.\support\stage_computerObjects.ps1 -Computer 'sql01c', 'sql01d' -ClusterName 'SQLCluster2' -Action delete

#>