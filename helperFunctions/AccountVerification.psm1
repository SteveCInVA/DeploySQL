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
        Write-Verbose $_.Exception.Message
        return $False
    }
}