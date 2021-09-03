function Test-DirectoryStructure {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $False)]
        [string]$InstallMediaPath = $pwd,

        [Parameter (Mandatory = $True)] 
        [ValidateSet('SQL2016', 'SQL2017', 'SQL2019')] 
        [string]$SQLVersion,
        
        [switch]$SkipCheckFilesExist
    )

    Write-Verbose "Checking Installation Media for required content..."

    if ((Test-Path -Path (Join-Path $InstallMediaPath -ChildPath ".\InstallMedia\$SQLVersion")) -eq $false) {
        Write-Warning "InstallMedia\$SQLVersion Folder is missing"
        $ret = $false
    }
    else {
        if ($SkipCheckFilesExist.IsPresent -eq $false) {
            if ((Test-Path -Path ".\InstallMedia\$SQLVersion\Setup.exe") -eq $false) {
                Write-Warning "InstallMedia\$SQLVersion setup files are missing"
                $ret = $false
            }
        }
    }
    if ((Test-Path -Path ".\InstallMedia\SQLManagementStudio") -eq $false) {
        Write-Warning "InstallMedia\SQLManagementStudio Folder is missing"
        $ret = $false
    }
    else {
        if ($SkipCheckFilesExist.IsPresent -eq $false) {
            if ((Test-Path -Path ".\InstallMedia\SQLManagementStudio\SSMS-Setup-ENU.exe") -eq $false) {
                Write-Warning "InstallMedia\SQLManagementStudio\SSMS-Setup-ENU.exe file is missing"
                $ret = $false
            }
        }
    }

    if ($null -eq $ret) {
        Write-Verbose "Successfully validated installation media exists"
        return $true
    }
    else {
        return $false
    }
}