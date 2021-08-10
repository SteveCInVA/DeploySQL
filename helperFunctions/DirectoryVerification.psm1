function Test-DirectoryStructure
{
    [CmdletBinding()]
    Param(
        [switch]$CheckFilesExist
    )

    [bool]$ret = $null
    if((test-path -path ".\InstallMedia\SQL2019") -eq $false)
    {
        write-error "InstallMedia\SQL2019 Folder is missing"
        $ret = $false
    }
    if((test-path -path ".\InstallMedia\SQL2017") -eq $false)
    {
        write-error "InstallMedia\SQL2017 Folder is missing"
        $ret = $false
    }
    if((test-path -path ".\InstallMedia\SQL2016") -eq $false)
    {
        write-error "InstallMedia\SQL2016 Folder is missing"
        $ret = $false
    }
    if((test-path -path ".\InstallMedia\SQLManagementStudio") -eq $false)
    {
        write-error "InstallMedia\SQLManagementStudio Folder is missing"
        $ret = $false
    }
    if($null -eq $ret)
    {
        return $true
    }
    else {
        return $false
    }

}
