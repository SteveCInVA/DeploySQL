
$Dir = get-location

Import-Module $dir\helperFunctions\DirectoryVerifications.psm1

if ((Test-ScriptIntegrity -InstallMediaPath $dir ) -eq $false) {
    Write-Warning "Key installation directories missing."
  #  $valid = $false
}