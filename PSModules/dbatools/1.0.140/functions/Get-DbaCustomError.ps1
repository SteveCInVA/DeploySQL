function Get-DbaCustomError {
    <#
    .SYNOPSIS
        Gets SQL Custom Error Message information for each instance(s) of SQL Server.

    .DESCRIPTION
        The Get-DbaCustomError command gets SQL Custom Error Message information for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Error, CustomError
        Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaCustomError

    .EXAMPLE
        PS C:\> Get-DbaCustomError -SqlInstance localhost

        Returns all Custom Error Message(s) on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaCustomError -SqlInstance localhost, sql2016

        Returns all Custom Error Message(s) for the local and sql2016 SQL Server instances

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($customError in $server.UserDefinedMessages) {
                Add-Member -Force -InputObject $customError -MemberType NoteProperty -Name ComputerName -value $customError.Parent.ComputerName
                Add-Member -Force -InputObject $customError -MemberType NoteProperty -Name InstanceName -value $customError.Parent.ServiceName
                Add-Member -Force -InputObject $customError -MemberType NoteProperty -Name SqlInstance -value $customError.Parent.DomainInstanceName

                Select-DefaultView -InputObject $customError -Property ComputerName, InstanceName, SqlInstance, ID, Text, LanguageID, Language
            }
        }
    }
}