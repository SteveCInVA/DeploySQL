function Move-DbaDbFile {
    <#
    .SYNOPSIS
        Moves database files from one local drive or folder to another.

    .DESCRIPTION
        Moves database files from one local drive or folder to another.
        It will put database offline, update metadata and set it online again.
        It can also be used to move database files on an AG secondary.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database to be moved.

    .PARAMETER FileToMove
        Pass a hashtable that contains a list of database files and their destination path.
        Key and value should be the logical name and then the path (e.g. 'db1_log' = 'D:\mssql\logs')

    .PARAMETER FileType
        Define the file type to move; accepted values: Data, Log or Both.
        Default value: Both
        Exclusive, cannot be used in conjunction with FileToMove.

    .PARAMETER FileDestination
        Destination directory of the database file(s).

    .PARAMETER DeleteAfterMove
        Remove the source database file(s) after the successful move operation.

    .PARAMETER FileStructureOnly
        Return a hashtable of the Database file structure.
        Modifying the hashtable it can then be utilized with the FileToMove parameter

    .PARAMETER Force
        Database(s) is set offline as part of the move process, this will utilize WITH ROLLBACK IMMEDIATE and rollback any open transaction running against the database(s).

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Move, File
        Author: Cláudio Silva (@claudioessilva), claudioeesilva.eu

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Move-DbaDbFile

    .EXAMPLE
        PS C:\> Move-DbaDbFile -SqlInstance sql2017 -Database dbatools -FileType Data -FileDestination "D:\DATA2"

        Copy all data files of dbatools database on sql2017 instance to the "D:\DATA2" path.
        Before it puts database offline and after copy each file will update database metadata and it ends by set the database back online

    .EXAMPLE
        PS C:\> $fileToMove=@{
        >> 'dbatools'='D:\DATA3'
        >> 'dbatools_log'='D:\LOG2'
        >> }
        PS C:\> Move-DbaDbFile -SqlInstance sql2019 -Database dbatools -FileToMove $fileToMove

        Declares a hashtable that says for each logical file the new path.
        Copy each dbatools database file referenced on the hashtable on the sql2019 instance from the current location to the new mentioned location (D:\DATA3 and D:\LOG2 paths).
        Before it puts database offline and after copy each file will update database metadata and it ends by set the database back online

    .EXAMPLE
        PS C:\> Move-DbaDbFile -SqlInstance sql2017 -Database dbatools -FileStructureOnly

        Shows the current database file structure (without filenames). Example: 'dbatools'='D:\Data'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Database,
        [parameter(ParameterSetName = "All")]
        [ValidateSet('Data', 'Log', 'Both')]
        [string]$FileType,
        [parameter(ParameterSetName = "All")]
        [string]$FileDestination,
        [parameter(ParameterSetName = "Detailed")]
        [hashtable]$FileToMove,
        [parameter(ParameterSetName = "All")]
        [parameter(ParameterSetName = "Detailed")]
        [switch]$DeleteAfterMove,
        [parameter(ParameterSetName = "FileStructure")]
        [switch]$FileStructureOnly,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ((Test-Bound -ParameterName FileType) -and (-not(Test-Bound -ParameterName FileDestination))) {
            Stop-Function -Category InvalidArgument -Message "FileDestination parameter is missing. Quitting."
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if ((-not $FileType) -and (-not $FileToMove) -and (-not $FileStructureOnly) ) {
            Stop-Function -Message "You must specify at least one of -FileType or -FileToMove or -FileStructureOnly to continue"
            return
        }

        if ($Database -in @("master", "model", "msdb", "tempdb")) {
            Stop-Function -Message "System database detected as input. The command does not support moving system databases. Quitting."
            return
        }

        try {
            try {
                $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue
            }

            switch ($FileType) {
                'Data' { $fileTypeFilter = 0 }
                'Log' { $fileTypeFilter = 1 }
                'Both' { $fileTypeFilter = -1 }
                default { $fileTypeFilter = -1 }
            }

            $dbStatus = (Get-DbaDbState -SqlInstance $server -Database $Database).Status
            if ($dbStatus -ne 'ONLINE') {
                Write-Message -Level Verbose -Message "Database $Database is already Offline. Getting file strucutre from sys.master_files."
                if ($fileTypeFilter -eq -1) {
                    $DataFiles = Get-DbaDbPhysicalFile -SqlInstance $server | Where-Object Name -eq $Database | Select-Object LogicalName, PhysicalName
                } else {
                    $DataFiles = Get-DbaDbPhysicalFile -SqlInstance $server | Where-Object { $_.Name -eq $Database -and $_.Type -eq $fileTypeFilter } | Select-Object LogicalName, PhysicalName
                }
            } else {
                if ($fileTypeFilter -eq -1) {
                    $DataFiles = Get-DbaDbFile -SqlInstance $server -Database $Database | Select-Object LogicalName, PhysicalName
                } else {
                    $DataFiles = Get-DbaDbFile -SqlInstance $server -Database $Database | Where-Object Type -eq $fileTypeFilter | Select-Object LogicalName, PhysicalName
                }
            }

            if (@($DataFiles).Count -gt 0) {

                if ($FileStructureOnly) {
                    $fileStructure = "`$fileToMove=@{`n"
                    foreach ($file in $DataFiles) {
                        $fileStructure += "`t'$($file.LogicalName)'='$(Split-Path -Path $file.PhysicalName -Parent)'`n"
                    }
                    $fileStructure += "}"
                    Write-Output $fileStructure
                    return
                }

                if ($FileDestination) {
                    $DataFilesToMove = $DataFiles | Select-Object -ExpandProperty LogicalName
                } else {
                    $DataFilesToMove = $FileToMove.Keys
                }

                if ($dbStatus -ne "Offline") {
                    if ($PSCmdlet.ShouldProcess($database, "Setting database $Database offline")) {
                        try {
                            $SetState = Set-DbaDbState -SqlInstance $server -Database $Database -Offline -Force:$Force
                            if ($SetState.Status -ne 'Offline') {
                                Write-Message -Level Warning -Message "Setting database Offline failed!"
                            } else {
                                Write-Message -Level Verbose -Message "Database $Database was set to Offline status."
                            }
                        } catch {
                            Stop-Function -Message "Setting database Offline failed! : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                        }
                    }
                }

                $locally = $false
                if ([DbaValidate]::IsLocalhost($server.ComputerName)) {
                    # locally ran so we can just use Start-BitsTransfer
                    $ComputerName = $server.ComputerName
                    $locally = $true
                } else {
                    # let's start checking if we can access .ComputerName
                    $testPS = $false
                    if ($SqlCredential) {
                        # why does Test-PSRemoting require a Credential param ? this is ugly...
                        $testPS = Test-PSRemoting -ComputerName $server.ComputerName -Credential $SqlCredential -ErrorAction Stop
                    } else {
                        $testPS = Test-PSRemoting -ComputerName $server.ComputerName -ErrorAction Stop
                    }
                    if (-not ($testPS)) {
                        # let's try to resolve it to a more qualified name, without "cutting" knowledge about the domain (only $server.Name possibly holds the complete info)
                        $Resolved = (Resolve-DbaNetworkName -ComputerName $server.Name).FullComputerName
                        if ($SqlCredential) {
                            $testPS = Test-PSRemoting -ComputerName $Resolved -Credential $SqlCredential -ErrorAction Stop
                        } else {
                            $testPS = Test-PSRemoting -ComputerName $Resolved -ErrorAction Stop
                        }
                        if ($testPS) {
                            $ComputerName = $Resolved
                        }
                    } else {
                        $ComputerName = $server.ComputerName
                    }
                }

                # if we don't have remote access ($ComputerName is null) we can fallback to admin shares if they're available
                if ($null -eq $ComputerName) {
                    $ComputerName = $server.ComputerName
                }

                # Test if defined paths are accesible by the instance
                $testPathResults = @()
                if ($FileDestination) {
                    if (-not (Test-DbaPath -SqlInstance $server -Path $FileDestination)) {
                        $testPathResults += $FileDestination
                    }
                } else {
                    foreach ($filePath in $FileToMove.Keys) {
                        if (-not (Test-DbaPath -SqlInstance $server -Path $FileToMove[$filePath])) {
                            $testPathResults += $FileToMove[$filePath]
                        }
                    }
                }
                if (@($testPathResults).Count -gt 0) {
                    Stop-Function -Message "The path(s):`r`n $($testPathResults -join [Environment]::NewLine)`r`n is/are not accessible by the instance. Confirm if it/they exists."
                    return
                }

                foreach ($LogicalName in $DataFilesToMove) {
                    $physicalName = $DataFiles | Where-Object LogicalName -eq $LogicalName | Select-Object -ExpandProperty PhysicalName

                    if ($FileDestination) {
                        $destinationPath = $FileDestination
                    } else {
                        $destinationPath = $FileToMove[$LogicalName]
                    }
                    $fileName = [IO.Path]::GetFileName($physicalName)
                    $destination = "$destinationPath\$fileName"

                    if ($physicalName -ne $destination) {
                        if ($locally) {
                            if ($PSCmdlet.ShouldProcess($database, "Copying file $physicalName to $destination using Bits locally on $ComputerName")) {
                                try {
                                    Start-BitsTransfer -Source $physicalName -Destination $destination -ErrorAction Stop
                                } catch {
                                    try {
                                        Write-Message -Level Warning -Message "WARN: Could not copy file using Bits transfer. $_"
                                        Write-Message -Level Verbose -Message "Trying with Copy-Item"
                                        Copy-Item -Path $physicalName -Destination $destination -ErrorAction Stop

                                    } catch {
                                        $failed = $true

                                        Write-Message -Level Important -Message "ERROR: Could not copy file. $_"
                                    }
                                }
                            }
                        } else {
                            # Use Remoting PS to run the command on the server
                            try {
                                if ($PSCmdlet.ShouldProcess($database, "Copying file $physicalName to $destination using remote PS on $ComputerName")) {
                                    $scriptBlock = {
                                        $physicalName = $args[0]
                                        $destination = $args[1]

                                        # Version 1 will yield - "The remote use of BITS is not supported." when using Remoting PS
                                        if ((Get-Command -Name Start-BitsTransfer).Version.Major -gt 1) {
                                            Write-Verbose "Try copying using Start-BitsTransfer."
                                            Start-BitsTransfer -Source $physicalName -Destination $destination -ErrorAction Stop
                                        } else {
                                            Write-Verbose "Can't use Bits. Using Copy-Item instead"
                                            Copy-Item -Path $physicalName -Destination $destination -ErrorAction Stop
                                        }

                                        Get-Acl -Path $physicalName | Set-Acl $destination
                                    }
                                    Invoke-Command2 -ComputerName $ComputerName -Credential $SqlCredential -ScriptBlock $scriptBlock -ArgumentList $physicalName, $destination
                                }
                            } catch {
                                # Try using UNC paths
                                try {
                                    $physicalNameUNC = Join-AdminUnc -ServerName $ComputerName -Filepath $physicalName
                                    $destinationUNC = Join-AdminUnc -ServerName $ComputerName -Filepath $destination

                                    if ($PSCmdlet.ShouldProcess($database, "Copying file $physicalNameUNC to $destinationUNC using UNC path for $ComputerName")) {

                                        try {
                                            Write-Message -Level Verbose -Message "Try copying using Start-BitsTransfer with UNC paths."
                                            Start-BitsTransfer -Source $physicalNameUNC -Destination $destinationUNC -ErrorAction Stop
                                        } catch {
                                            Write-Message -Level Warning -Message "Did not work using Start-BitsTransfer. ERROR: $_"
                                            Write-Message -Level Verbose -Message "Trying using Copy-Item with UNC paths instead."
                                            Copy-Item -Path $physicalNameUNC -Destination $destinationUNC -ErrorAction Stop
                                        }

                                        # Force the copy of the file's ACL
                                        Get-Acl -Path $physicalNameUNC | Set-Acl $destinationUNC

                                        Write-Message -Level Verbose -Message "File $fileName was copied successfully"
                                    }
                                } catch {
                                    $failed = $true

                                    Write-Message -Level Important -Message "ERROR: Could not copy file. $_"
                                }
                            }

                            Write-Message -Level Verbose -Message "File $fileName was copied successfully"
                        }

                        if (-not $failed) {
                            $query = "ALTER DATABASE [$Database] MODIFY FILE (name=$LogicalName, filename='$destination'); "

                            if ($PSCmdlet.ShouldProcess($Database, "Executing ALTER DATABASE query - $query")) {
                                # Change database file path
                                $server.Databases["master"].Query($query)
                            }

                            if ($DeleteAfterMove) {
                                try {
                                    if ($PSCmdlet.ShouldProcess($database, "Deleting source file $physicalName")) {
                                        if ($locally) {
                                            Remove-Item -Path $physicalName -ErrorAction Stop
                                        } else {
                                            $scriptBlock = {
                                                $source = $args[0]
                                                Remove-Item -Path $source -ErrorAction Stop
                                            }
                                            Invoke-Command2 -ComputerName $ComputerName -Credential $SqlCredential -ScriptBlock $scriptBlock -ArgumentList $physicalName
                                        }
                                    }
                                } catch {
                                    [PSCustomObject]@{
                                        Instance             = $SqlInstance
                                        Database             = $Database
                                        LogicalName          = $LogicalName
                                        Source               = $physicalName
                                        Destination          = $destination
                                        Result               = "Success"
                                        DatabaseFileMetadata = "Updated"
                                        SourceFileDeleted    = $false
                                    }

                                    Stop-Function -Message "ERROR:" -ErrorRecord $_
                                }
                            }

                            [PSCustomObject]@{
                                Instance             = $SqlInstance
                                Database             = $Database
                                LogicalName          = $LogicalName
                                Source               = $physicalName
                                Destination          = $destination
                                Result               = "Success"
                                DatabaseFileMetadata = "Updated"
                                SourceFileDeleted    = $true
                            }
                        } else {
                            [PSCustomObject]@{
                                Instance             = $SqlInstance
                                Database             = $Database
                                LogicalName          = $LogicalName
                                Source               = $physicalName
                                Destination          = $destination
                                Result               = "Failed"
                                DatabaseFileMetadata = "N/A"
                                SourceFileDeleted    = "N/A"
                            }
                        }
                    } else {
                        Write-Message -Level Verbose -Message "File $fileName already exists on $destination. Skipping."
                        [PSCustomObject]@{
                            Instance             = $SqlInstance
                            Database             = $Database
                            LogicalName          = $LogicalName
                            Source               = $physicalName
                            Destination          = $destination
                            Result               = "Already exists. Skipping"
                            DatabaseFileMetadata = "N/A"
                            SourceFileDeleted    = "N/A"
                        }
                    }
                }

                if ($PSCmdlet.ShouldProcess($Database, "Setting database Online")) {
                    try {
                        $SetState = Set-DbaDbState -SqlInstance $server -Database $Database -Online -ErrorVariable dbstate
                        if ($SetState.Status -ne 'Online') {
                            Stop-Function -Message "$($SetState.Notes)! : $($dbstate.Exception.InnerException.InnerException.InnerException.InnerException)."
                        } else {
                            Write-Message -Level Verbose -Message "Database is online!"
                        }
                    } catch {
                        Stop-Function -Message "Setting database online failed! : $($_.Exception.InnerException.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                    }
                }
            } else {
                Write-Message -Level Warning -Message "We could not get any files for database $Database!"
            }
        } catch {
            Stop-Function -Message "ERROR:" -ErrorRecord $_
        }
    }
}

# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUqrH+OaYj00Fx19dng43Evsdl
# z9GgghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgVGltZXN0YW1waW5nIENBMB4XDTIxMDEwMTAwMDAwMFoXDTMxMDEw
# NjAwMDAwMFowSDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMu
# MSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyMTCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAMLmYYRnxYr1DQikRcpja1HXOhFCvQp1dU2UtAxQ
# tSYQ/h3Ib5FrDJbnGlxI70Tlv5thzRWRYlq4/2cLnGP9NmqB+in43Stwhd4CGPN4
# bbx9+cdtCT2+anaH6Yq9+IRdHnbJ5MZ2djpT0dHTWjaPxqPhLxs6t2HWc+xObTOK
# fF1FLUuxUOZBOjdWhtyTI433UCXoZObd048vV7WHIOsOjizVI9r0TXhG4wODMSlK
# XAwxikqMiMX3MFr5FK8VX2xDSQn9JiNT9o1j6BqrW7EdMMKbaYK02/xWVLwfoYer
# vnpbCiAvSwnJlaeNsvrWY4tOpXIc7p96AXP4Gdb+DUmEvQECAwEAAaOCAbgwggG0
# MA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsG
# AQUFBwMIMEEGA1UdIAQ6MDgwNgYJYIZIAYb9bAcBMCkwJwYIKwYBBQUHAgEWG2h0
# dHA6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAfBgNVHSMEGDAWgBT0tuEgHf4prtLk
# YaWyoiWyyBc1bjAdBgNVHQ4EFgQUNkSGjqS6sGa+vCgtHUQ23eNqerwwcQYDVR0f
# BGowaDAyoDCgLoYsaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJl
# ZC10cy5jcmwwMqAwoC6GLGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFz
# c3VyZWQtdHMuY3JsMIGFBggrBgEFBQcBAQR5MHcwJAYIKwYBBQUHMAGGGGh0dHA6
# Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBPBggrBgEFBQcwAoZDaHR0cDovL2NhY2VydHMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJRFRpbWVzdGFtcGluZ0NB
# LmNydDANBgkqhkiG9w0BAQsFAAOCAQEASBzctemaI7znGucgDo5nRv1CclF0CiNH
# o6uS0iXEcFm+FKDlJ4GlTRQVGQd58NEEw4bZO73+RAJmTe1ppA/2uHDPYuj1UUp4
# eTZ6J7fz51Kfk6ftQ55757TdQSKJ+4eiRgNO/PT+t2R3Y18jUmmDgvoaU+2QzI2h
# F3MN9PNlOXBL85zWenvaDLw9MtAby/Vh/HUIAHa8gQ74wOFcz8QRcucbZEnYIpp1
# FUL1LTI4gdr0YKK6tFL7XOBhJCVPst/JKahzQ1HavWPWH1ub9y4bTxMd90oNcX6X
# t/Q/hOvB46NJofrOp79Wz7pZdmGJX36ntI5nePk2mOHLKNpbh6aKLzCCBRowggQC
# oAMCAQICEAMFu4YhsKFjX7/erhIE520wDQYJKoZIhvcNAQELBQAwcjELMAkGA1UE
# BhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2lj
# ZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUg
# U2lnbmluZyBDQTAeFw0yMDA1MTIwMDAwMDBaFw0yMzA2MDgxMjAwMDBaMFcxCzAJ
# BgNVBAYTAlVTMREwDwYDVQQIEwhWaXJnaW5pYTEPMA0GA1UEBxMGVmllbm5hMREw
# DwYDVQQKEwhkYmF0b29sczERMA8GA1UEAxMIZGJhdG9vbHMwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQC8v2N7q+O/vggBtpjmteofFo140k73JXQ5sOD6
# QLzjgija+scoYPxTmFSImnqtjfZFWmucAWsDiMVVro/6yGjsXmJJUA7oD5BlMdAK
# fuiq4558YBOjjc0Bp3NbY5ZGujdCmsw9lqHRAVil6P1ZpAv3D/TyVVq6AjDsJY+x
# rRL9iMc8YpD5tiAj+SsRSuT5qwPuW83ByRHqkaJ5YDJ/R82ZKh69AFNXoJ3xCJR+
# P7+pa8tbdSgRf25w4ZfYPy9InEvsnIRVZMeDjjuGvqr0/Mar73UI79z0NYW80yN/
# 7VzlrvV8RnniHWY2ib9ehZligp5aEqdV2/XFVPV4SKaJs8R9AgMBAAGjggHFMIIB
# wTAfBgNVHSMEGDAWgBRaxLl7KgqjpepxA8Bg+S32ZXUOWDAdBgNVHQ4EFgQU8MCg
# +7YDgENO+wnX3d96scvjniIwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsG
# AQUFBwMDMHcGA1UdHwRwMG4wNaAzoDGGL2h0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNv
# bS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMDWgM6Axhi9odHRwOi8vY3JsNC5kaWdp
# Y2VydC5jb20vc2hhMi1hc3N1cmVkLWNzLWcxLmNybDBMBgNVHSAERTBDMDcGCWCG
# SAGG/WwDATAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20v
# Q1BTMAgGBmeBDAEEATCBhAYIKwYBBQUHAQEEeDB2MCQGCCsGAQUFBzABhhhodHRw
# Oi8vb2NzcC5kaWdpY2VydC5jb20wTgYIKwYBBQUHMAKGQmh0dHA6Ly9jYWNlcnRz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNIQTJBc3N1cmVkSURDb2RlU2lnbmluZ0NB
# LmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4IBAQCPzflwlQwf1jak
# EqymPOc0nBxiY7F4FwcmL7IrTLhub6Pjg4ZYfiC79Akz5aNlqO+TJ0kqglkfnOsc
# jfKQzzDwcZthLVZl83igzCLnWMo8Zk/D2d4ZLY9esFwqPNvuuVDrHvgh7H6DJ/zP
# Vm5EOK0sljT0UQ6HQEwtouH5S8nrqCGZ8jKM/+DeJlm+rCAGGf7TV85uqsAn5JqD
# En/bXE1AlyG1Q5YiXFGS5Sf0qS4Nisw7vRrZ6Qc4NwBty4cAYjzDPDixorWI8+FV
# OUWKMdL7tV8i393/XykwsccCstBCp7VnSZN+4vgzjEJQql5uQfysjcW9rrb/qixp
# csPTKYRHMIIFMDCCBBigAwIBAgIQBAkYG1/Vu2Z1U0O1b5VQCDANBgkqhkiG9w0B
# AQsFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMTMxMDIyMTIwMDAwWhcNMjgxMDIyMTIwMDAwWjByMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQg
# Q29kZSBTaWduaW5nIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
# +NOzHH8OEa9ndwfTCzFJGc/Q+0WZsTrbRPV/5aid2zLXcep2nQUut4/6kkPApfmJ
# 1DcZ17aq8JyGpdglrA55KDp+6dFn08b7KSfH03sjlOSRI5aQd4L5oYQjZhJUM1B0
# sSgmuyRpwsJS8hRniolF1C2ho+mILCCVrhxKhwjfDPXiTWAYvqrEsq5wMWYzcT6s
# cKKrzn/pfMuSoeU7MRzP6vIK5Fe7SrXpdOYr/mzLfnQ5Ng2Q7+S1TqSp6moKq4Tz
# rGdOtcT3jNEgJSPrCGQ+UpbB8g8S9MWOD8Gi6CxR93O8vYWxYoNzQYIH5DiLanMg
# 0A9kczyen6Yzqf0Z3yWT0QIDAQABo4IBzTCCAckwEgYDVR0TAQH/BAgwBgEB/wIB
# ADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwMweQYIKwYBBQUH
# AQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYI
# KwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFz
# c3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmw0
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaG
# NGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RD
# QS5jcmwwTwYDVR0gBEgwRjA4BgpghkgBhv1sAAIEMCowKAYIKwYBBQUHAgEWHGh0
# dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwCgYIYIZIAYb9bAMwHQYDVR0OBBYE
# FFrEuXsqCqOl6nEDwGD5LfZldQ5YMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6en
# IZ3zbcgPMA0GCSqGSIb3DQEBCwUAA4IBAQA+7A1aJLPzItEVyCx8JSl2qB1dHC06
# GsTvMGHXfgtg/cM9D8Svi/3vKt8gVTew4fbRknUPUbRupY5a4l4kgU4QpO4/cY5j
# DhNLrddfRHnzNhQGivecRk5c/5CxGwcOkRX7uq+1UcKNJK4kxscnKqEpKBo6cSgC
# PC6Ro8AlEeKcFEehemhor5unXCBc2XGxDI+7qPjFEmifz0DLQESlE/DmZAwlCEIy
# sjaKJAL+L3J+HNdJRZboWR3p+nRka7LrZkPas7CM1ekN3fYBIM6ZMWM9CBoYs4Gb
# T8aTEAb8B4H6i9r5gkn3Ym6hU/oSlBiFLpKR6mhsRDKyZqHnGKSaZFHvMIIFMTCC
# BBmgAwIBAgIQCqEl1tYyG35B5AXaNpfCFTANBgkqhkiG9w0BAQsFADBlMQswCQYD
# VQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGln
# aWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0Ew
# HhcNMTYwMTA3MTIwMDAwWhcNMzEwMTA3MTIwMDAwWjByMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5n
# IENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvdAy7kvNj3/dqbqC
# mcU5VChXtiNKxA4HRTNREH3Q+X1NaH7ntqD0jbOI5Je/YyGQmL8TvFfTw+F+CNZq
# FAA49y4eO+7MpvYyWf5fZT/gm+vjRkcGGlV+Cyd+wKL1oODeIj8O/36V+/OjuiI+
# GKwR5PCZA207hXwJ0+5dyJoLVOOoCXFr4M8iEA91z3FyTgqt30A6XLdR4aF5FMZN
# JCMwXbzsPGBqrC8HzP3w6kfZiFBe/WZuVmEnKYmEUeaC50ZQ/ZQqLKfkdT66mA+E
# f58xFNat1fJky3seBdCEGXIX8RcG7z3N1k3vBkL9olMqT4UdxB08r8/arBD13ays
# 6Vb/kwIDAQABo4IBzjCCAcowHQYDVR0OBBYEFPS24SAd/imu0uRhpbKiJbLIFzVu
# MB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHkGCCsG
# AQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29t
# MEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRBc3N1cmVkSURSb290Q0EuY3J0MIGBBgNVHR8EejB4MDqgOKA2hjRodHRwOi8v
# Y3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMDqg
# OKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURS
# b290Q0EuY3JsMFAGA1UdIARJMEcwOAYKYIZIAYb9bAACBDAqMCgGCCsGAQUFBwIB
# FhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAsGCWCGSAGG/WwHATANBgkq
# hkiG9w0BAQsFAAOCAQEAcZUS6VGHVmnN793afKpjerN4zwY3QITvS4S/ys8DAv3F
# p8MOIEIsr3fzKx8MIVoqtwU0HWqumfgnoma/Capg33akOpMP+LLR2HwZYuhegiUe
# xLoceywh4tZbLBQ1QwRostt1AuByx5jWPGTlH0gQGF+JOGFNYkYkh2OMkVIsrymJ
# 5Xgf1gsUpYDXEkdws3XVk4WTfraSZ/tTYYmo9WuWwPRYaQ18yAGxuSh1t5ljhSKM
# Ycp5lH5Z/IwP42+1ASa2bKXuh1Eh5Fhgm7oMLSttosR+u8QlK0cCCHxJrhO24XxC
# QijGGFbPQTS2Zl22dHv1VjMiLyI2skuiSpXY9aaOUjGCBFwwggRYAgEBMIGGMHIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJ
# RCBDb2RlIFNpZ25pbmcgQ0ECEAMFu4YhsKFjX7/erhIE520wCQYFKw4DAhoFAKB4
# MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQB
# gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkE
# MRYEFC8m2leEp+1wNPpJYRoT6O5UG0GaMA0GCSqGSIb3DQEBAQUABIIBADfEHobI
# nbe47wk3/VPoQPNQOWR9gWutIxJ6NjTRxygAAhzsS9DRS8h5oWBFvifPuVjy1MRK
# 1GOvKFH6SckzSBjCjdN4cNm7CfjSRdpbdGxHrPQCpYHArG+yoDb59pLiz4EZATyr
# jXB60Tp1xjQWkPzNA7MdZRh5qh5WRxOMEQlm4dLqIoYTXBPCuVohA4vpL0kiyADK
# v9SWHPdMMjL+1mqE/epXferHu+7RKvEQ4NfZTUodJZ+f71BejqVbfP64ihnnJH1y
# aFYQbIRZCZqsQWOWiyjsjdzkwvj1Z4jQGoMX3E/9Bj5NDDWLl3AsLpomDLSyHmKs
# PKjhfv/9EHigAUOhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk1M1owLwYJKoZIhvcNAQkEMSIEILzTDgr4MBgO+XmSSuJEtowPhZ/F
# Ljm8WriNJfNbbXMgMA0GCSqGSIb3DQEBAQUABIIBAFtaedBQyQixJoUNYSsvSrox
# xSviwwbhsWqcX1kkOyypmfx8tYW6U4F98cExNDmp/dIsQ7iTXocxlzi47A2rMADi
# qDmruZ4ohYUmbqY6ADEI7iQLYfJpbKGTZi7jvI+23QaUdFPmDG/OykU95aA3hlVK
# BSdeOYhVy3GMAr/arnTmBcaLGbkPaqRy8yJlTjiYoiG64VVLlOMbymliBO7kfBKX
# qxT5fx56au2he7imUOjs94r07WLrpGtY9n4Yen/esGFwx3AaU1yCoASJMbS94j7P
# tpnaJ80T9WGeAF9DRYIzC03XOhd2rv0mlHwgyU4mW2B9wLnVL/K1ejLBhimgYZs=
# SIG # End signature block
