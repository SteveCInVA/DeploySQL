﻿[CmdletBinding()]
Param(
    [Parameter (Mandatory = $true)] 
    [string[]]$Computer,
    
    [Parameter (Mandatory = $true)] 
    [string]$ClusterName,

    [Parameter (Mandatory = $false)] 
    [string]$ObjectPath = "OU=SQL,OU=Servers,DC=Contoso,DC=COM",

    [Parameter (Mandatory=$false)]
    [ValidateSet('create', 'delete')] 
    [string]$Action = 'create', 

    [switch]$doNotDisableComputerAccounts,
    [switch]$doNotDeleteComputerAccounts
)

if ($Action -eq 'create')
{
    #Create computer objects
    foreach ($c in $Computer)
    {
    #create base computers
        try
        {
            New-ADComputer -Name $c -SamAccountName $c -Path $ObjectPath -Enabled $true
            Write-Verbose "Created computer account $c in $ObjectPath"
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityAlreadyExistsException]
        {
            Write-Warning "Computer object $c was already found... skipping"     
        }
        catch
        {
            Write-Error -Exception $_.Exception -Message "Error creating disabled computer object"
        }
    } 
    
    #create cluster object disabled
    try
    {
        New-ADComputer -Name $ClusterName -SamAccountName $ClusterName -Path $ObjectPath -Enabled $false
        Write-Verbose "Created disabled cluster account $ClusterName in $ObjectPath"
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityAlreadyExistsException]
    {
        Write-Warning "Cluster Object $ClusterName was already found... skipping"  
    }
    catch
    {
        Write-Error -Exception $_.Exception -Message "Error creating disabled cluster object"
    }

    #Grant Access to cluster object
    try 
    {
        $acl = get-acl "ad:CN=$ClusterName,$ObjectPath"
        $adRights = [System.DirectoryServices.ActiveDirectoryRights] "GenericAll"
        $type = [System.Security.AccessControl.AccessControlType] "Allow"
        $inheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance] "All"
    
        foreach ($c in $Computer)
        {
            $adc = get-adcomputer $c
            $sid = [System.Security.Principal.SecurityIdentifier] $adc.SID
            $identity = [System.Security.Principal.IdentityReference] $SID
            $ACE = New-Object System.DirectoryServices.ActiveDirectoryAccessRule $identity,$adRights,$type,$inheritanceType
            # Add the ACE to the ACL, then set the ACL to save the changes
            $acl.AddAccessRule($ace)
            Set-acl -aclobject $acl "ad:CN=$ClusterName,$ObjectPath"
            Write-Verbose "Granted 'Full Control' to $c on Cluster object $ClusterName"
        }
    }
    catch
    {
        Write-Error -Exception $_.Exception -Message "Error granting access to cluster object"
    }

    #disable computer accounts
    if(!($doNotDisableComputerAccounts.isPresent))
    {
        foreach ($c in $Computer)
        {
            try
            {
                Set-ADComputer -Identity $c -Enabled $false
                Write-Verbose "Disabled computer account $c in $ObjectPath"
            }
            catch [Microsoft.ActiveDirectory.Management.ADIdentityAlreadyExistsException]
            {
                Write-Warning "Computer object $c was already found... skipping"     
            }
            catch
            {
                Write-Error -Exception $_.Exception -Message "Error disabling computer object"
            }
        } 
    }
    Write-Output "Created Active Directory objects"
}

if ($action -eq 'delete')
{
    #delete computers
    if(!($doNotDeleteComputerAccounts.isPresent))
    {
        foreach ($c in $Computer)
        {
            try 
            {
                Remove-ADObject -Identity "CN=$c,$ObjectPath" -Confirm:$False -Recursive
                write-Verbose "Deleted $c computer object"
            }
            catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
            {
                Write-Warning "Computer $c was not found"
            }
            catch
            {
                Write-Error -Exception $_.Exception -Message "Error deleting computer objects"
            }
        }
    }
    #delete cluster name
        try 
        {
            Remove-ADObject -Identity "CN=$ClusterName,$ObjectPath" -Confirm:$False -Recursive
            write-Verbose "Deleted $ClusterName computer object"
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
        {
            Write-Warning "Cluster Object $ClusterName was not found"
        }
        catch
        {
            Write-Error -Exception $_.Exception -Message "Error deleting cluster object"
        }
    Write-Output "Deleted Active Directory objects"
}