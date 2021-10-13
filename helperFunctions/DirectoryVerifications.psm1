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

    $path = "$InstallMediaPath\PSModules\PendingReboot"
    write-verbose "Testing $path"
    if ('40E0AAD21BE1ECDE7888F2DA2D2404CCF97FC0BA5490FC5060804BF0E2D544F2' -ne (Get-FolderHash -Path $path)){
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
