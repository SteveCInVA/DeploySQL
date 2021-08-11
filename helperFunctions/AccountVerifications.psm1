function Test-AccountExists
{
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory=$True)]
        [string]$AccountName,

        [Parameter (Mandatory=$False)]
        [string]$ADDomain=$env:USERDOMAIN
    )
    Write-Verbose "Testing $AccountName"

    $domain = $ADDomain.ToUpper()
    $filter = $AccountName.ToUpper().Replace("$domain\","")
    $filter = "CN=$filter"
    
    try{
        $r = Get-ADObject -LDAPFilter $filter
        if ($null -eq $r){
            Write-Verbose "$AccountName not found in Active Directory"
            return $false
        }
        else {
            write-verbose "$AccountName found in Active Directory"
            return $true
        }
    }
    catch{
        Write-warning $_.Exception.Message
        return $False
    }
}

function Test-AccountCredential
{
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory=$True)]
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