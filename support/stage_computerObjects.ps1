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

[CmdletBinding()]
Param(
    [Parameter (Mandatory = $true)]
    [string[]]$Computer,

    [Parameter (Mandatory = $false)]
    [string]$ClusterName,

    [Parameter (Mandatory = $false)]
    [string[]]$VirtualClusterObject,

    [Parameter (Mandatory = $false)]
    [string]$ObjectPath = "OU=SQL,OU=Servers,DC=Contoso,DC=COM",

    [Parameter (Mandatory = $false)]
    [ValidateSet('create', 'delete')]
    [string]$Action = 'create',

    [switch]$doNotDisableAccounts,
    [switch]$doNotDeleteComputerAccounts
)


##########################################
# perform parameter validations
$valid = $null

# check length of computer names is less than 15 characters
foreach ($c in $Computer) {
    if($c.Length -gt 15){
        Write-Warning "Computer $c length is greater than 15 characters."
        $valid = $false
    }
}

if ($ClusterName.Length -gt 15){
    Write-Warning "ClusterName parameter length is greater than 15 characters."
    $valid = $false
}

foreach ($c in $VirtualClusterObject) {
    if($c.Length -gt 15){
        Write-Warning "VirtualComputerObject $c length is greater than 15 characters."
        $valid = $false
    }
}

# check if Virtual Cluster Objects is specified but cluster name is not
if (($VirtualClusterObject.length -gt 0) -and ($ClusterName.Length -eq 0)) {
    Write-Warning "VirtualClusterObject parameter is specified but ClusterName is missing"
    $valid = $false
}
##########################################
# end of validations...  if any tests fail, quit
if ($valid -eq $false) {
    break
}
##########################################

if ($Action -eq 'create') {
    #Create computer objects
    foreach ($c in $Computer) {
        #create base computers
        try {
            New-ADComputer -Name $c -SamAccountName $c -Path $ObjectPath -Enabled $true
            Write-Verbose "Created computer account $c in $ObjectPath"
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityAlreadyExistsException] {
            Write-Warning "Computer object $c was already found... skipping"
        }
        catch {
            Write-Error -Exception $_.Exception -Message "Error creating disabled computer object"
        }
    }

    #Create Cluster Object
    if (($ClusterName -ne $null) -and ($ClusterName -ne "")){
        try {
            New-ADComputer -Name $ClusterName -SamAccountName $ClusterName -Path $ObjectPath -Enabled $false
            Write-Verbose "Created disabled cluster account $ClusterName in $ObjectPath"
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityAlreadyExistsException] {
            Write-Warning "Cluster Object $ClusterName was already found... skipping"
        }
        catch {
            Write-Error -Exception $_.Exception -Message "Error creating disabled cluster object"
        }

        #Grant Access to cluster object
        try {
            $acl = Get-Acl "ad:CN=$ClusterName,$ObjectPath"
            $adRights = [System.DirectoryServices.ActiveDirectoryRights] "GenericAll"
            $type = [System.Security.AccessControl.AccessControlType] "Allow"
            $inheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance] "All"

            foreach ($c in $Computer) {
                $adc = Get-ADComputer $c
                $sid = [System.Security.Principal.SecurityIdentifier] $adc.SID
                $identity = [System.Security.Principal.IdentityReference] $SID
                $ACE = New-Object System.DirectoryServices.ActiveDirectoryAccessRule $identity, $adRights, $type, $inheritanceType
                # Add the ACE to the ACL, then set the ACL to save the changes
                $acl.AddAccessRule($ace)
                Set-Acl -AclObject $acl "ad:CN=$ClusterName,$ObjectPath"
                Write-Verbose "Granted 'Full Control' to $c on Cluster object $ClusterName"
            }
        }
        catch {
            Write-Error -Exception $_.Exception -Message "Error granting access to cluster object"
        }
        if (((Get-ADComputer -Identity $ClusterName).Enabled) -and (!($doNotDisableAccounts.isPresent))){
            try {
                Set-ADComputer -Identity $ClusterName -Enabled $false
                Write-Verbose "Disabled cluster account $ClusterName in $ObjectPath"
            }
            catch {
                Write-Error -Exception $_.Exception -Message "Error disabling cluster object"
            }
        }
    }

    #virtual cluster objects
    foreach ($vco in $VirtualClusterObject) {
        #create virtual cluster objects
        try {
            New-ADComputer -Name $vco -SamAccountName $vco -Path $ObjectPath -Enabled $false
            Write-Verbose "Created virtual cluster object $vco in $ObjectPath"
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityAlreadyExistsException] {
            Write-Warning "Virtual cluster object $vco was already found... skipping"
        }
        catch {
            Write-Error -Exception $_.Exception -Message "Error creating disabled virtual cluster object"
        }
    }

        #Grant Access to virtual cluster object
    foreach ($vco in $VirtualClusterObject) {
        try {
            $acl = Get-Acl "ad:CN=$vco,$ObjectPath"
            $adRights = [System.DirectoryServices.ActiveDirectoryRights] "GenericAll"
            $type = [System.Security.AccessControl.AccessControlType] "Allow"
            $inheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance] "All"

            $adc = Get-ADComputer $ClusterName
            $sid = [System.Security.Principal.SecurityIdentifier] $adc.SID
            $identity = [System.Security.Principal.IdentityReference] $SID
            $ACE = New-Object System.DirectoryServices.ActiveDirectoryAccessRule $identity, $adRights, $type, $inheritanceType
            # Add the ACE to the ACL, then set the ACL to save the changes
            $acl.AddAccessRule($ace)
            Set-Acl -AclObject $acl "ad:CN=$vco,$ObjectPath"
            Write-Verbose "Granted 'Full Control' to $ClusterName on Virtual cluster object $vco"
        }
        catch {
            Write-Error -Exception $_.Exception -Message "Error granting access to cluster object"
        }
    }

    #disable computer accounts
    if (!($doNotDisableAccounts.isPresent)) {
        foreach ($c in $Computer) {
            try {
                Set-ADComputer -Identity $c -Enabled $false
                Write-Verbose "Disabled computer account $c in $ObjectPath"
            }
            catch [Microsoft.ActiveDirectory.Management.ADIdentityAlreadyExistsException] {
                Write-Warning "Computer object $c was already found... skipping"
            }
            catch {
                Write-Error -Exception $_.Exception -Message "Error disabling computer object"
            }
        }
    }
    Write-Output "Created Active Directory objects"
}

if ($action -eq 'delete') {
    #delete computers
    if (!($doNotDeleteComputerAccounts.isPresent)) {
        foreach ($c in $Computer) {
            try {
                Remove-ADObject -Identity "CN=$c,$ObjectPath" -Confirm:$False -Recursive
                Write-Verbose "Deleted $c computer object"
            }
            catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                Write-Warning "Computer $c was not found"
            }
            catch {
                Write-Error -Exception $_.Exception -Message "Error deleting computer objects"
            }
        }
    }
    #delete cluster name
    try {
        Remove-ADObject -Identity "CN=$ClusterName,$ObjectPath" -Confirm:$False
        Write-Verbose "Deleted $ClusterName computer object"
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Warning "Cluster Object $ClusterName was not found"
    }
    catch {
        Write-Error -Exception $_.Exception -Message "Error deleting cluster object"
    }

    #delete virtual cluster objects
    foreach ($vco in $VirtualClusterObject) {
        try {
            Remove-ADObject -Identity "CN=$vco,$ObjectPath" -Confirm:$False -Recursive
            Write-Verbose "Deleted $vco virtual cluster object"
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            Write-Warning "Virtual cluster object $vco was not found"
        }
        catch {
            Write-Error -Exception $_.Exception -Message "Error deleting virtual cluster object"
        }
    }

    Write-Output "Deleted Active Directory objects"
}
