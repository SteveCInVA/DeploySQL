
 param ( 
    [Parameter (Mandatory=$true)] 
    [string]$Computer='localhost', 
    
    [Parameter (Mandatory=$false)] 
    [string]$Instance, 
       
    [Parameter (Mandatory=$false)] 
    [System.Management.Automation.PSCredential] 
    $InstallCredential = $host.ui.promptForCredential("Install Credential", "Please specify the credential used for service installation", $env:USERNAME, $env:USERDOMAIN) 
    ) 


