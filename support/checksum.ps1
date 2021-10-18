
$Dir = get-location

Import-Module $dir\helperFunctions\DirectoryVerifications.psm1 -Force

if ((Test-ScriptIntegrity -InstallMediaPath $dir -Verbose) -eq $false) {
    Write-Warning "Key installation directories missing."
  #  $valid = $false
}