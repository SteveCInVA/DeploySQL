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
    This function gets all Key properties defined in the resource schema file.

    .PARAMETER Name
    This is the SQL database.

    .PARAMETER RecoveryModel
    This is the RecoveryModel of the SQL database.

    .PARAMETER ServerName
    This is a the SQL Server for the database. Default value is $env:COMPUTERNAME.

    .PARAMETER InstanceName
    This is a the SQL instance for the database.
#>
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Full', 'Simple', 'BulkLogged')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $RecoveryModel,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $InstanceName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name
    )

    Write-Verbose -Message (
        $script:localizedData.GetRecoveryModel -f $Name, $InstanceName
    )

    $sqlServerObject = Connect-SQL -ServerName $ServerName -InstanceName $InstanceName
    if ($sqlServerObject)
    {
        $sqlDatabaseObject = $sqlServerObject.Databases[$Name]
        if ($sqlDatabaseObject)
        {
            $sqlDatabaseRecoveryModel = $sqlDatabaseObject.RecoveryModel

            Write-Verbose -Message (
                $script:localizedData.CurrentRecoveryModel -f $sqlDatabaseRecoveryModel, $Name
            )
        }
        else
        {
            $errorMessage = $script:localizedData.DatabaseNotFound -f $Name
            New-InvalidResultException -Message $errorMessage
        }
    }

    return @{
        Name          = $Name
        RecoveryModel = $sqlDatabaseRecoveryModel
        ServerName    = $ServerName
        InstanceName  = $InstanceName
    }
}

<#
    .SYNOPSIS
    This function gets all Key properties defined in the resource schema file.

    .PARAMETER Name
    This is the SQL database.

    .PARAMETER RecoveryModel
    This is the RecoveryModel of the SQL database.

    .PARAMETER ServerName
    This is a the SQL Server for the database. Default value is $env:COMPUTERNAME.

    .PARAMETER InstanceName
    This is a the SQL instance for the database.
#>
function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Full', 'Simple', 'BulkLogged')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $RecoveryModel,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $InstanceName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name
    )

    $sqlServerObject = Connect-SQL -ServerName $ServerName -InstanceName $InstanceName
    if ($sqlServerObject)
    {
        Write-Verbose -Message (
            $script:localizedData.SetRecoveryModel -f $Name
        )

        $sqlDatabaseObject = $sqlServerObject.Databases[$Name]
        if ($sqlDatabaseObject)
        {
            if ($sqlDatabaseObject.RecoveryModel -ne $RecoveryModel)
            {
                $sqlDatabaseObject.RecoveryModel = $RecoveryModel
                $sqlDatabaseObject.Alter()

                Write-Verbose -Message (
                    $script:localizedData.ChangeRecoveryModel -f $Name, $RecoveryModel
                )
            }
        }
        else
        {
            $errorMessage = $script:localizedData.DatabaseNotFound -f $Name
            New-InvalidResultException -Message $errorMessage
        }
    }
}

<#
    .SYNOPSIS
    This function gets all Key properties defined in the resource schema file.

    .PARAMETER Name
    This is the SQL database.

    .PARAMETER RecoveryModel
    This is the RecoveryModel of the SQL database.

    .PARAMETER ServerName
    This is a the SQL Server for the database. Default value is $env:COMPUTERNAME.

    .PARAMETER InstanceName
    This is a the SQL instance for the database.
#>
function Test-TargetResource
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('SqlServerDsc.AnalyzerRules\Measure-CommandsNeededToLoadSMO', '', Justification='The command Connect-Sql is called when Get-TargetResource is called')]
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Full', 'Simple', 'BulkLogged')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $RecoveryModel,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $InstanceName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name
    )

    Write-Verbose -Message (
        $script:localizedData.TestingConfiguration -f $Name, $InstanceName
    )

    $currentValues = Get-TargetResource @PSBoundParameters

    return Test-DscParameterState -CurrentValues $currentValues `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck @('Name', 'RecoveryModel') `
        -TurnOffTypeChecking
}

Export-ModuleMember -Function *-TargetResource
