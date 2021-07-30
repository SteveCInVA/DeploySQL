<#
    DEPRECATION NOTICE:

    THIS RESOURCE IS DEPRECATED!

    Changes to this resource will no longer be merged. Instead please use the
    resource SqlDatabase.
#>

$script:sqlServerDscHelperModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Modules\SqlServerDsc.Common'
$script:resourceHelperModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Modules\DscResource.Common'

Import-Module -Name $script:sqlServerDscHelperModulePath
Import-Module -Name $script:resourceHelperModulePath

$script:localizedData = Get-LocalizedData -DefaultUICulture 'en-US'

<#
    .SYNOPSIS
    This function gets the owner of the desired sql database.

    .PARAMETER DatabaseName
    The name of database to be configured.

    .PARAMETER Name
    The name of the login that will become a owner of the desired sql database.

    .PARAMETER ServerName
    The host name of the SQL Server to be configured.

    .PARAMETER InstanceName
    The name of the SQL instance to be configured.
#>
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DatabaseName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $InstanceName
    )

    Write-Verbose -Message (
        $script:localizedData.GetCurrentDatabaseOwner -f $DatabaseName, $InstanceName
    )

    try
    {
        $sqlServerObject = Connect-SQL -ServerName $ServerName -InstanceName $InstanceName
        if ($sqlServerObject)
        {
            # Check database exists
            if ( -not ($sqlDatabaseObject = $sqlServerObject.Databases[$DatabaseName]) )
            {
                $errorMessage = $script:localizedData.DatabaseNotFound -f $DatabaseName
                New-ObjectNotFoundException -Message $errorMessage
            }

            $sqlDatabaseOwner = $sqlDatabaseObject.Owner

            Write-Verbose -Message (
                $script:localizedData.CurrentDatabaseOwner -f $DatabaseName, $sqlDatabaseOwner
            )
        }
    }
    catch
    {
        $errorMessage = $script:localizedData.FailedToGetOwnerDatabase -f $DatabaseName
        New-InvalidOperationException -Message $errorMessage -ErrorRecord $_
    }

    $returnValue = @{
        DatabaseName = $DatabaseName
        Name         = $sqlDatabaseOwner
        ServerName   = $ServerName
        InstanceName = $InstanceName
    }

    $returnValue
}

<#
    .SYNOPSIS
    This function sets the owner of the desired sql database.

    .PARAMETER DatabaseName
    The name of database to be configured.

    .PARAMETER Name
    The name of the login that will become a owner of the desired sql database.

    .PARAMETER ServerName
    The host name of the SQL Server to be configured.

    .PARAMETER InstanceName
    The name of the SQL instance to be configured.
#>
function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DatabaseName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $InstanceName
    )

    $sqlServerObject = Connect-SQL -ServerName $ServerName -InstanceName $InstanceName
    if ($sqlServerObject)
    {
        # Check database exists
        if ( -not ($sqlDatabaseObject = $sqlServerObject.Databases[$DatabaseName]) )
        {
            $errorMessage = $script:localizedData.DatabaseNotFound -f $DatabaseName
            New-ObjectNotFoundException -Message $errorMessage
        }

        # Check login exists
        if ( -not ($sqlServerObject.Logins[$Name]) )
        {
            $errorMessage = $script:localizedData.LoginNotFound -f $Name
            New-ObjectNotFoundException -Message $errorMessage
        }

        Write-Verbose -Message (
            $script:localizedData.SetDatabaseOwner -f $DatabaseName, $InstanceName
        )

        try
        {
            $sqlDatabaseObject.SetOwner($Name)

            Write-Verbose -Message (
                $script:localizedData.NewOwner -f $Name
            )
        }
        catch
        {
            $errorMessage = $script:localizedData.FailedToSetOwnerDatabase -f $DatabaseName
            New-InvalidOperationException -Message $errorMessage -ErrorRecord $_
        }
    }
}

<#
    .SYNOPSIS
    This function tests the owner of the desired sql database.

    .PARAMETER DatabaseName
    The name of database to be configured.

    .PARAMETER Name
    The name of the login that will become a owner of the desired sql database.

    .PARAMETER ServerName
    The host name of the SQL Server to be configured.

    .PARAMETER InstanceName
    The name of the SQL instance to be configured.
#>
function Test-TargetResource
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('SqlServerDsc.AnalyzerRules\Measure-CommandsNeededToLoadSMO', '', Justification='The command Connect-Sql is called when Get-TargetResource is called')]
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DatabaseName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $InstanceName
    )

    Write-Verbose -Message (
        $script:localizedData.TestingConfiguration -f $DatabaseName, $InstanceName
    )

    $currentValues = Get-TargetResource @PSBoundParameters
    return Test-DscParameterState -CurrentValues $CurrentValues `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck @('Name', 'DatabaseName') `
        -TurnOffTypeChecking
}

Export-ModuleMember -Function *-TargetResource
