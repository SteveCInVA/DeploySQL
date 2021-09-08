clear-host

Configuration Reboot
{ 
    Import-DscResource -ModuleName PSDesiredStateConfiguration 
    Import-DscResource -ModuleName StorageDsc 
      
    Node @('sql01a', 'sql01b', 'sql01c')
    {
        #Configure optical drive as V:\ 
        Script ScriptExample
        {
            GetScript = { 
                $x = (Test-PendingReboot -SkipConfigurationManagerClientCheck | select-object IsRebootPending) 
                write-verbose ("IsRebootPending = " + $x.IsRebootPending)
                return @{ Result = "!$x.IsRebootPending"}
            }

            SetScript = {
                Write-Verbose "Restarting Server"
                Restart-Computer -Force
            }
            TestScript = { 
                $x = (Test-PendingReboot -SkipConfigurationManagerClientCheck | select-object IsRebootPending) 
                write-verbose ("IsRebootPending = " + $x.IsRebootPending)
                !$x.IsRebootPending
            }
        }
    } 
}

$config = @{ 
    AllNodes = @( 
        @{ 
            NodeName                    = "*"
        }
    )
} 
    # configuration specific to primary node

$computer = 'sql01a'

$InstallUsername = "contoso\stecarr-adm"
$InstallPwd = Read-Host "Enter Admin Account Password" -AsSecureString
$InstallCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $InstallUsername, $InstallPwd

$cSessions = New-CimSession -ComputerName $Computer -Credential $InstallCredential     

[string]$scriptPath = $MyInvocation.MyCommand.Path 
[string]$Dir = Split-Path $scriptPath
Set-Location $Dir 

Reboot -ConfigurationData $config -OutputPath "$Dir\MOF\Test" 
Start-DscConfiguration -Path "$Dir\MOF\Test" -Verbose -Wait -Force -CimSession $cSessions -ErrorAction Stop 
