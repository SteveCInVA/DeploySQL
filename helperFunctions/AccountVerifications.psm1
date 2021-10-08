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

function Test-AccountExists {
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory = $True)]
        [string]$AccountName,

        [Parameter (Mandatory = $False)]
        [string]$ADDomain = $env:USERDOMAIN
    )
    Write-Verbose "Testing $AccountName"

    $domain = $ADDomain.ToUpper()
    $filter = $AccountName.ToUpper().Replace("$domain\", "")
    $filter = "SAMAccountName=$filter"

    try {
        $r = Get-ADObject -LDAPFilter $filter
        if ($null -eq $r) {
            Write-Verbose "$AccountName not found in Active Directory"
            return $false
        }
        else {
            Write-Verbose "$AccountName found in Active Directory"
            return $true
        }
    }
    catch {
        Write-Warning $_.Exception.Message
        return $False
    }
}

function Test-AccountCredential {
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory = $True)]
        [System.Management.Automation.PSCredential]$Credential
    )

    Try {
        $username = $Credential.Username
        Write-Verbose "Testing $Username"
        $root = "LDAP://" + ([ADSI]'').distinguishedName
        $domain = New-Object System.DirectoryServices.DirectoryEntry($root, $username, $Credential.GetNetworkCredential().Password)
    }
    Catch {
        $_.Exception.message
        continue
    }

    If (!$domain) {
        Write-Warning "Unable to query LDAP domain"
        return $false
        break
    }
    Else {
        if ($null -eq $domain.Name) {
            Write-Warning "Unable to authenticate '$username'"
            return $false
            break
        }
    }
    Write-Verbose "Successfully validated '$username'"
    return $true
}