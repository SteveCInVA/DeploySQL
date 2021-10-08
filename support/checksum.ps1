<#
[string]$scriptPath = $MyInvocation.MyCommand.Path
[string]$Dir = Split-Path $scriptPath

$path = 'C:\Users\stecarr\OneDrive - Microsoft\Documents\git\DeploySQL\PSModules\PendingReboot'

#Import-Module $dir\helperFunctions\Tools.psm1

$file = New-TemporaryFile

GetFolderFileHash($path) | export-csv $file

$hash = (Get-FileHash $file).Hash

if ($hash -eq '27B7693406CDBB2BEB281BFCDE5987EDE040A391C6AC0FF44CD1AC8C70995D62'){
    write-host 'valid'
}
else {
    write-warning 'different'
}
#>