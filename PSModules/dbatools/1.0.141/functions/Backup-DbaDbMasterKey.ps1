function Backup-DbaDbMasterKey {
    <#
    .SYNOPSIS
        Backs up specified database master key.

    .DESCRIPTION
        Backs up specified database master key.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Backup master key from specific database(s).

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server.

    .PARAMETER Path
        The directory to export the key. If no path is specified, the default backup directory for the instance will be used.

    .PARAMETER Credential
        Pass a credential object for the password

    .PARAMETER SecurePassword
        The password to encrypt the exported key. This must be a SecureString.

    .PARAMETER InputObject
        Database object piped in from Get-DbaDatabase

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Database
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Backup-DbaDbMasterKey

    .EXAMPLE
        PS C:\> Backup-DbaDbMasterKey -SqlInstance server1\sql2016
        ```
        ComputerName : SERVER1
        InstanceName : SQL2016
        SqlInstance  : SERVER1\SQL2016
        Database     : master
        Filename     : E:\MSSQL13.SQL2016\MSSQL\Backup\server1$sql2016-master-20170614162311.key
        Status       : Success
        ```

        Prompts for export password, then logs into server1\sql2016 with Windows credentials then backs up all database keys to the default backup directory.

    .EXAMPLE
        PS C:\> Backup-DbaDbMasterKey -SqlInstance Server1 -Database db1 -Path \\nas\sqlbackups\keys

        Logs into sql2016 with Windows credentials then backs up db1's keys to the \\nas\sqlbackups\keys directory.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [Alias("Password")]
        [Security.SecureString]$SecurePassword,
        [string]$Path,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Credential) {
            $SecurePassword = $Credential.Password
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            if (Test-Bound -ParameterName Path -Not) {
                $Path = $server.BackupDirectory
            }

            if (-not $Path) {
                Stop-Function -Message "Path discovery failed. Please explicitly specify -Path" -Target $server -Continue
            }

            if (!(Test-DbaPath -SqlInstance $server -Path $Path)) {
                Stop-Function -Message "$instance cannot access $Path" -Target $server -ErrorRecord $_ -Continue
            }

            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                continue
            }

            $masterkey = $db.MasterKey

            if (!$masterkey) {
                Write-Message -Message "No master key exists in the $db database on $instance" -Target $db -Level Verbose
                continue
            }

            # If you pass a password param, then you will not be prompted for each database, but it wouldn't be a good idea to build in insecurity
            if (-not $SecurePassword -and -not $Credential) {
                $SecurePassword = Read-Host -AsSecureString -Prompt "You must enter Service Key password for $instance"
                $SecurePassword2 = Read-Host -AsSecureString -Prompt "Type the password again"

                if (([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($SecurePassword))) -ne ([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($SecurePassword2)))) {
                    Stop-Function -Message "Passwords do not match" -Continue
                }
            }

            $time = (Get-Date -Format yyyMMddHHmmss)
            $dbName = $db.name
            $Path = $Path.TrimEnd("\")
            $fileinstance = $instance.ToString().Replace('\', '$')
            $filename = "$Path\$fileinstance-$dbName-$time.key"

            if ($Pscmdlet.ShouldProcess($instance, "Backing up master key to $filename")) {
                try {
                    $masterkey.Export($filename, [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($SecurePassword)))
                    $status = "Success"
                } catch {
                    $status = "Failure"
                    Write-Message -Level Warning -Message "Backup failure: $($_.Exception.InnerException)"
                }

                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Database -value $dbName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Filename -value $filename
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Status -value $status

                Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, Database, 'Filename as Path', Status
            }
        }
    }
}