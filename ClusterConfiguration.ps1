param ( 
    [Parameter (Mandatory = $true)] 
    [string[]]$Computer = 'localhost', 

    [Parameter (Mandatory = $false)] 
    [string]$InstallSourcePath = "\\$env:COMPUTERNAME\DeploySQL",

    [Parameter (Mandatory = $false)] 
    [string]$Instance = 'MSSQLSERVER',

    [Parameter (Mandatory = $false)]
    [string]$ClusterName = 'SQLCluster1',

    [Parameter (Mandatory = $false)] 
    [System.Management.Automation.PSCredential] 
    $InstallCredential = $host.ui.promptForCredential("Install Credential", "Please specify the credential used for service installation", $env:USERNAME, $env:USERDOMAIN) 
)

###################################################################
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
            DebugMode          = 'ForceModuleImport'
            RefreshMode        = 'Push' 
            RebootNodeIfNeeded = $true
        } 
    } 
} 

###################################################################

Configuration ConfigureCluster
{
    Import-DscResource -ModuleName PSDesiredStateConfiguration 
    Import-DscResource -ModuleName ComputerManagementDsc
    Import-DscResource -ModuleName xFailoverCluster

    #base feature install
    Node $AllNodes.NodeName
    {
        WindowsFeature FailoverFeature {
            Ensure = "Present"
            Name   = "Failover-Clustering"
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
        xCluster createCluster {
            Name                          = $Node.ClusterName
            DomainAdministratorCredential = $InstallCredential 
            DependsOn                     = "[WindowsFeature]FailoverFeature"
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

###################################################################

[System.Collections.ArrayList]$s = $Computer
$s.Remove($Computer[0])
$p = $Computer[0]

###################################################################

# Setup our configuration data object that will be used by our DSC configurations 
$config = @{ 
    AllNodes = @( 
        @{ 
            NodeName                    = "*"
            PSDscAllowPlainTextPassword = $true 
            PsDscAllowDomainUser        = $true 

            ClusterName                 = $ClusterName
        }
    )
} 
# configuration specific to primary node
$config.AllNodes += @{
    NodeName = $p
    NodeType = 'Primary'
}
# configuration specific to all other nodes
foreach ($c in $s) {
    $config.AllNodes += @{
        NodeName = $c 
        NodeType = 'Secondary'
    }
}

###################################################################

#$config.AllNodes | out-string | write-host

#Set working directory 
[string]$Scriptpath = $MyInvocation.MyCommand.Path 
[string]$Dir = Split-Path $Scriptpath

#create an array of CIM Sessions 
$cSessions = New-CimSession -ComputerName $Computer -Credential $InstallCredential 

###################################################################

#Configure LCM 
LCMConfig -ConfigurationData $config -OutputPath "$Dir\MOF\LCMConfig" 
Set-DscLocalConfigurationManager -Path "$Dir\MOF\LCMConfig" -CimSession $cSessions -Verbose -Force 

#Install Required PsDSCModules 
InstallRequiredPSModules -ConfigurationData $config -OutputPath "$Dir\MOF\InstallPSModules" 
Start-DscConfiguration -Path "$Dir\MOF\InstallPSModules" -Verbose -Wait -Force -CimSession $cSessions -ErrorAction Stop 

#Configure Cluster
ConfigureCluster -ConfigurationData $config -OutputPath "$Dir\MOF\Cluster" 
Start-DscConfiguration -Path "$Dir\MOF\Cluster" -Wait -Verbose -CimSession $cSessions -ErrorAction Stop 
