<#
 ###########################################################
 Copyright (C) 2021 Microsoft Corporation

    Disclaimer:
    This is SAMPLE code that is NOT production ready. It is the sole intention of this code to provide a proof of concept as a
    learning tool for Microsoft Customers. Microsoft does not provide warranty for or guarantee any portion of this code
    and is NOT responsible for any affects it may have on any system it is executed on or environment it resides within.
    Please use this code at your own discretion!

    Additional legalese:

    This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment.
    THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED ""AS IS"" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
    INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
    We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute
    the object code form of the Sample Code, provided that You agree:
    (i) to not use Our name, logo, or trademarks to market Your software product in which the Sample Code is embedded;
    (ii) to include a valid copyright notice on Your software product in which the Sample Code is embedded; and
    (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys' fees,
    that arise or result from the use or distribution of the Sample Code.
 ###########################################################
#>

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

function Test-ScriptIntegrity{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $False)]
        [string]$InstallMediaPath = $pwd
    )

    Write-Verbose "Checking integrity of scripts..."
    Import-Module $InstallMediaPath\helperFunctions\Tools.psm1

    $path = "$InstallMediaPath\PSModules\AccessControlDSC"
    write-verbose "Testing $path"
    if ('C77F157B66FA79C3FDF7977CBE7CC8754DDF48F21F204ADDD4F1B89B81C0D66F' -ne (Get-FolderHash -Path $path)){
        Write-Warning "Script differences found in: $path"
        $ret = $false
    }

    $path = "$InstallMediaPath\PSModules\ComputerManagementDsc"
    write-verbose "Testing $path"
    if ('5B89F086B5124CE77D832F933AC9D1340E025DD2088EC0ECB47275F0F2458AA2' -ne (Get-FolderHash -Path $path)){
        Write-Warning "Script differences found in: $path"
        $ret = $false
    }

    $path = "$InstallMediaPath\PSModules\dbatools"
    write-verbose "Testing $path"
    if ('4AA4FA71CD4F62EFFE0E9F28E5709373FD26430C380FEE2A977F30FA88034AAE' -ne (Get-FolderHash -Path $path)){
        Write-Warning "Script differences found in: $path"
        $ret = $false
    }

    $path = "$InstallMediaPath\PSModules\NetworkingDsc"
    write-verbose "Testing $path"
    if ('7992DBEAC119FDDF3498CD66C5AAE9A9B07C6B9629941D6E459C2F6A4B243FC4' -ne (Get-FolderHash -Path $path)){
        Write-Warning "Script differences found in: $path"
        $ret = $false
    }

    $path = "$InstallMediaPath\PSModules\PendingReboot"
    write-verbose "Testing $path"
    if ('40E0AAD21BE1ECDE7888F2DA2D2404CCF97FC0BA5490FC5060804BF0E2D544F2' -ne (Get-FolderHash -Path $path)){
        Write-Warning "Script differences found in: $path"
        $ret = $false
    }

#TODO:  resolve which version of PSFramework is needed and add in correct test

    $path = "$InstallMediaPath\PSModules\SqlServer"
    write-verbose "Testing $path"
    if ('8EB09A86E5F8B4573CB5346BCCE21DEA5DC7F6202546B76D51477C3E4E56B6C1' -ne (Get-FolderHash -Path $path)){
        Write-Warning "Script differences found in: $path"
        $ret = $false
    }

    $path = "$InstallMediaPath\PSModules\SqlServerDsc"
    write-verbose "Testing $path"
    if ('1B61857D2DEC26F9FC5C2122967987A27883B6412D40C10FF62F68F986CB9BE1' -ne (Get-FolderHash -Path $path)){
        Write-Warning "Script differences found in: $path"
        $ret = $false
    }

    $path = "$InstallMediaPath\PSModules\StorageDsc"
    write-verbose "Testing $path"
    if ('3609B9160F080669A9150CA1225DD332083F986D83CA2CCC7AEB2C543CA4BB8D' -ne (Get-FolderHash -Path $path)){
        Write-Warning "Script differences found in: $path"
        $ret = $false
    }

    $path = "$InstallMediaPath\PSModules\xFailOverCluster"
    write-verbose "Testing $path"
    if ('77D45714265F4DF6CD5A3BDF9FBEDEFE7ECCDE61CA7C9C37677F88E5927DD9EC' -ne (Get-FolderHash -Path $path)){
        Write-Warning "Script differences found in: $path"
        $ret = $false
    }

    if ($null -eq $ret) {
        Write-Verbose "Successfully validated script integrity"
        return $true
    }
    else {
        return $false
    }

}
