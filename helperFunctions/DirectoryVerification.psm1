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

    write-verbose "Checking Installation Media for required content..."

    if ((test-path -path (join-path $InstallMediaPath -childPath ".\InstallMedia\$SQLVersion")) -eq $false) {
        write-warning "InstallMedia\$SQLVersion Folder is missing"
        $ret = $false
    }
    else {
        if ($SkipCheckFilesExist.IsPresent -eq $false) {
            if ((test-path -path ".\InstallMedia\$SQLVersion\Setup.exe") -eq $false) {
                write-warning "InstallMedia\$SQLVersion setup files are missing"
                $ret = $false
            }
        }
    }
    if ((test-path -path ".\InstallMedia\SQLManagementStudio") -eq $false) {
        write-warning "InstallMedia\SQLManagementStudio Folder is missing"
        $ret = $false
    }
    else {
        if ($SkipCheckFilesExist.IsPresent -eq $false) {
            if ((test-path -path ".\InstallMedia\SQLManagementStudio\SSMS-Setup-ENU.exe") -eq $false) {
                write-warning "InstallMedia\SQLManagementStudio\SSMS-Setup-ENU.exe file is missing"
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