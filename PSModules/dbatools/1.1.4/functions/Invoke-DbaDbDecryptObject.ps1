function Invoke-DbaDbDecryptObject {
    <#
    .SYNOPSIS
        Invoke-DbaDbDecryptObject returns the decrypted version of an object

    .DESCRIPTION
        SQL Server provides an option to encrypt the code used in various types of objects.
        If the original code is no longer available for an encrypted object it won't be possible to view the definition.
        With this command the dedicated admin connection (DAC) can be used to search for the object and decrypt it.

        The command will output the results to the console by default.
        There is an option to export all the results to a folder creating .sql files.

        To connect to a remote SQL instance the remote dedicated administrator connection option will need to be configured.
        The binary versions of the objects can only be retrieved using a DAC connection.
        You can check the remote DAC connection with:
        'Get-DbaSpConfigure -SqlInstance [yourinstance] -ConfigName RemoteDacConnectionsEnabled'
        It should say 1 in the ConfiguredValue.

        The local DAC connection is enabled by default.

        To change the configurations you can use the Set-DbaSpConfigure command:
        'Set-DbaSpConfigure -SqlInstance [yourinstance] -ConfigName RemoteDacConnectionsEnabled -Value 1'
        In some cases you may need to reboot the instance.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Database to search for the object.

    .PARAMETER ObjectName
        The name of the object to search for in the database.

    .PARAMETER EncodingType
        The encoding type used to decrypt and encrypt values.

    .PARAMETER ExportDestination
        Location to output the decrypted object definitions.
        The destination will use the instance name, database name and object type i.e.: C:\temp\decrypt\SQLDB1\DB1\StoredProcedure

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Encryption, Decrypt, Database
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbDecryptObject

    .EXAMPLE
        PS C:\> Invoke-DbaDbDecryptObject -SqlInstance SQLDB1 -Database DB1 -ObjectName Function1

        Decrypt object "Function1" in DB1 of instance SQLDB1 and output the data to the user.

    .EXAMPLE
        PS C:\> Invoke-DbaDbDecryptObject -SqlInstance SQLDB1 -Database DB1 -ObjectName Function1 -ExportDestination C:\temp\decrypt

        Decrypt object "Function1" in DB1 of instance SQLDB1 and output the data to the folder "C:\temp\decrypt".

    .EXAMPLE
        PS C:\> Invoke-DbaDbDecryptObject -SqlInstance SQLDB1 -Database DB1 -ExportDestination C:\temp\decrypt

        Decrypt all objects in DB1 of instance SQLDB1 and output the data to the folder "C:\temp\decrypt"

    .EXAMPLE
        PS C:\> Invoke-DbaDbDecryptObject -SqlInstance SQLDB1 -Database DB1 -ObjectName Function1, Function2

        Decrypt objects "Function1" and "Function2" and output the data to the user.

    .EXAMPLE
        PS C:\> "SQLDB1" | Invoke-DbaDbDecryptObject -Database DB1 -ObjectName Function1, Function2

        Decrypt objects "Function1" and "Function2" and output the data to the user using a pipeline for the instance.

    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [object[]]$Database,
        [string[]]$ObjectName,
        [ValidateSet('ASCII', 'UTF8')]
        [string]$EncodingType = 'ASCII',
        [string]$ExportDestination,
        [switch]$EnableException
    )

    begin {

        function Invoke-DecryptData() {
            param(
                [parameter(Mandatory)]
                [byte[]]$Secret,
                [parameter(Mandatory)]
                [byte[]]$KnownPlain,
                [parameter(Mandatory)]
                [byte[]]$KnownSecret
            )

            # Declare pointers
            [int]$i = 0

            # Loop through each of the characters and apply an XOR to decrypt the data
            $result = $(

                # Loop through the byte string
                while ($i -lt $Secret.Length) {

                    # Compare the byte string character to the key character using XOR
                    if ($i -lt $Secret.Length) {
                        $Secret[$i] -bxor $KnownPlain[$i] -bxor $KnownSecret[$i]
                    }

                    # Increment the byte string indicator
                    $i += 2

                } # end while loop

            ) # end data value

            # Get the string value from the data
            $decryptedData = $Encoding.GetString($result)

            # Return the decrypted data
            return $decryptedData
        }

        # Create array list to hold the results
        $objectCollection = New-Object System.Collections.ArrayList

        # Set the encoding
        if ($EncodingType -eq 'ASCII') {
            $encoding = [System.Text.Encoding]::ASCII
        } elseif ($EncodingType -eq 'UTF8') {
            $encoding = [System.Text.Encoding]::UTF8
        }

        # Check the export parameter
        if ($ExportDestination -and -not (Test-Path $ExportDestination)) {
            try {
                # Create the new destination
                New-Item -Path $ExportDestination -ItemType Directory -Force | Out-Null
            } catch {
                Stop-Function -Message "Couldn't create destination folder $ExportDestination" -ErrorRecord $_ -Target $instance -Continue
            }
        }

    }

    process {

        if (Test-FunctionInterrupt) { return }

        # Loop through all the instances
        foreach ($instance in $SqlInstance) {

            # Check the configuration of the intance to see if the DAC is enabled
            $config = Get-DbaSpConfigure -SqlInstance $instance -SqlCredential $SqlCredential -ConfigName RemoteDacConnectionsEnabled
            if ($config.ConfiguredValue -ne 1) {
                Stop-Function -Message "DAC is not enabled for instance $instance.`nPlease use 'Set-DbaSpConfigure -SqlInstance $instance -SqlCredential <credential> -ConfigName RemoteDacConnectionsEnabled -Value 1' to configure the instance to allow DAC connections" -Target $instance -Continue
            }

            # Try to connect to instance
            try {
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server "ADMIN:$instance"

                # credential usage
                if ($null -ne $SqlCredential) {
                    $context = $server.ConnectionContext
                    $context.LoginSecure = $false  # this allows for SQL auth to be done
                    $context.Login = $SqlCredential.UserName
                    $context.SecurePassword = $SqlCredential.Password
                }
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Get all the databases that compare to the database parameter
            $databaseCollection = $server.Databases | Where-Object { $_.Name -in $Database }

            # Use the table's schema for the trigger's schema. The schema name is not returned as a property for triggers (except in the URN).
            $triggerSchema = @{label = "Schema"; expression = { $_.Parent.Schema } }

            # Loop through each of databases
            foreach ($db in $databaseCollection) {

                $triggers = @($db.Tables | Where-Object { $_.IsSystemObject -eq $false } | ForEach-Object { $_.Triggers })

                # Get the objects
                if ($ObjectName) {
                    $storedProcedures = @($db.StoredProcedures | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { 'StoredProcedure' } }, @{N = "SubType"; E = { '' } })
                    $functions = @($db.UserDefinedFunctions | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { "UserDefinedFunction" } }, @{N = "SubType"; E = { $_.FunctionType.ToString().Trim() } })
                    $views = @($db.Views | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { 'View' } }, @{N = "SubType"; E = { '' } })
                    $triggers = @($triggers | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, $triggerSchema, Parent, @{N = "ObjectType"; E = { 'Trigger' } }, @{N = "SubType"; E = { '' } })
                } else {
                    # Get all encrypted objects
                    $storedProcedures = @($db.StoredProcedures | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { 'StoredProcedure' } }, @{N = "SubType"; E = { '' } })
                    $functions = @($db.UserDefinedFunctions | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { "UserDefinedFunction" } }, @{N = "SubType"; E = { $_.FunctionType.ToString().Trim() } })
                    $views = @($db.Views | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { 'View' } }, @{N = "SubType"; E = { '' } })
                    $triggers = @($triggers | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, $triggerSchema, Parent, @{N = "ObjectType"; E = { 'Trigger' } }, @{N = "SubType"; E = { '' } })
                }

                # Check if there are any objects
                if ($storedProcedures.Count -ge 1) {
                    $objectCollection += $storedProcedures
                }
                if ($functions.Count -ge 1) {
                    $objectCollection += $functions
                }
                if ($views.Count -ge 1) {
                    $objectCollection += $views
                }
                if ($triggers.Count -ge 1) {
                    $objectCollection += $triggers
                }
                # Loop through all the objects
                foreach ($object in $objectCollection) {

                    # Setup the query to get the secret. Include the schema name to find the object. Exclude null values in sys.sysobjvalues for triggers.
                    $querySecret = "SELECT imageval AS Value FROM sys.sysobjvalues WHERE objid = OBJECT_ID('$($object.Schema).$($object.Name)') AND imageval IS NOT NULL"

                    # Get the result of the secret query
                    try {
                        $secret = $server.Databases[$db.Name].Query($querySecret)
                    } catch {
                        Stop-Function -Message "Couldn't retrieve secret from $instance" -ErrorRecord $_ -Target $instance -Continue
                    }

                    # Check if at least a value came back
                    if ($secret) {

                        # Setup a known plain command and get the binary version of it
                        switch ($object.ObjectType) {

                            'StoredProcedure' {
                                $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER PROCEDURE [$($object.Schema)].[$($object.Name)] WITH ENCRYPTION AS RETURN 0;"
                            }
                            'UserDefinedFunction' {

                                switch ($object.SubType) {
                                    'Inline' {
                                        $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION [$($object.Schema)].[$($object.Name)]() RETURNS TABLE WITH ENCRYPTION AS RETURN SELECT 0 i;"
                                    }
                                    'Scalar' {
                                        $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION [$($object.Schema)].[$($object.Name)]() RETURNS INT WITH ENCRYPTION AS BEGIN RETURN 0 END;"
                                    }
                                    'Table' {
                                        $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION [$($object.Schema)].[$($object.Name)]() RETURNS @r TABLE(i INT) WITH ENCRYPTION AS BEGIN RETURN END;"
                                    }
                                }
                            }
                            'View' {
                                $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER VIEW [$($object.Schema)].[$($object.Name)] WITH ENCRYPTION AS SELECT NULL AS [Value];"
                            }
                            'Trigger' {
                                $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER TRIGGER [$($object.Schema)].[$($object.Name)] ON $($object.Parent) WITH ENCRYPTION AFTER INSERT AS RAISERROR (''Invoke-DbaDbDecryptObject'', 16, 10);"
                            }
                        }

                        # Convert the known plain into binary
                        if ($queryKnownPlain) {
                            try {
                                $knownPlain = $encoding.GetBytes(($queryKnownPlain))
                            } catch {
                                Stop-Function -Message "Couldn't convert the known plain to binary" -ErrorRecord $_ -Target $instance -Continue
                            }
                        } else {
                            Stop-Function -Message "Something went wrong setting up the known plain" -ErrorRecord $_ -Target $instance -Continue
                        }

                        # Setup the query to change the object in SQL Server and roll it back getting the encrypted version
                        # Exclude null values in sys.sysobjvalues for triggers and include the full schema and object name.
                        $queryKnownSecret = "
                            BEGIN TRANSACTION;
                                EXEC ('$queryKnownPlain');
                                SELECT imageval AS Value
                                FROM sys.sysobjvalues
                                WHERE objid = OBJECT_ID('$($object.Schema).$($object.Name)')
                                AND imageval IS NOT NULL;
                            ROLLBACK;
                        "

                        # Get the result for the known encrypted
                        try {
                            $knownSecret = $server.Databases[$db.Name].Query($queryKnownSecret)
                        } catch {
                            Stop-Function -Message "Couldn't retrieve known secret from $instance" -ErrorRecord $_ -Target $instance -Continue
                        }

                        # Get the result
                        $result = Invoke-DecryptData -Secret $secret.value -KnownPlain $knownPlain -KnownSecret $knownSecret.value

                        # Check if the results need to be exported
                        $filePath = $null
                        if ($ExportDestination) {
                            # make up the file name
                            $filename = "$($object.Schema).$($object.Name).sql"

                            # Check the export destination
                            if ($ExportDestination.EndsWith("\")) {
                                $destinationFolder = "$ExportDestination$instance\$($db.Name)\$($object.ObjectType)\"
                            } else {
                                $destinationFolder = "$ExportDestination\$instance\$($db.Name)\$($object.ObjectType)\"
                            }

                            # Check if the destination folder exists
                            if (-not (Test-Path $destinationFolder)) {
                                try {
                                    # Create the new destination
                                    New-Item -Path $destinationFolder -ItemType Directory -Force:$Force | Out-Null
                                } catch {
                                    Stop-Function -Message "Couldn't create destination folder $destinationFolder" -ErrorRecord $_ -Target $instance -Continue
                                }
                            }

                            # Combine the destination folder and the file name to get the path
                            $filePath = $destinationFolder + $filename

                            # Export the result
                            try {
                                $result | Out-File -FilePath $filePath -Force
                            } catch {
                                Stop-Function -Message "Couldn't export the results of $($object.Name) to $filePath" -ErrorRecord $_ -Target $instance -Continue
                            }

                        }

                        # Add the results to the custom object
                        [PSCustomObject]@{
                            ComputerName = $instance.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.Name
                            Type         = $object.ObjectType
                            Schema       = $object.Schema
                            Name         = $object.Name
                            FullName     = "$($object.Schema).$($object.Name)"
                            Script       = $result
                            OutputFile   = $filePath
                        }
                    }
                }
            }
        }
    }
    end {
        Write-Message -Message "Finished decrypting data" -Level Verbose
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUTcYSX8fj9KdtYEps15ljg4Cn
# 8zygghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFMvnhfPfDk/fQnAt67P+4HQeIJPOMA0GCSqGSIb3DQEBAQUABIIBAJWb6AzQ
# FeKcAyQLiiAcpxX6ptjwmMOEkNBBtx1eYGZnCCXUsEuo8Sg7IYRWbwSjWpw8GYSo
# T1sAOy1A4w3AlEGSrJLiEYiLMTMQKJBXG7WjjVAiMvbQXnsZLld5hrVlIdOYrkhI
# vG46oe7HxwbQkDWGyjg915zAK7X22IqN/ujeMD3FT1l4YNhTw3tcDRhYLNt+D9/I
# nAqysvDtNEXz41mYZfZpUJHJ6YwSb2QBHWTDqTwJ3e9i3RqDk38otc3S7va9clYE
# KSAnDlj6w3OXg/oO5s8ZrSWatQLgls8AfVHsP2DBgnYNLE6ZrejBbhr/t109V899
# kRcYOJLkdqpBXjGhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk1MFowLwYJKoZIhvcNAQkEMSIEIKUKJ3irAZJmt73cmrtjcxtsQwkY
# lUS7i7IZN0f14+dgMA0GCSqGSIb3DQEBAQUABIIBAFLful1XV4lhCgyIfhFn+i5d
# nfENwXZGzcKe9ZhXGZcI9EMHZKShznUO+Vy0uOud342RczjMoSssuvR+ORhou/TU
# 8PuHHBUDljW4426FL7HEQMhZ1NhNesAuiGB2nu6JemgoGnDS03N/q7a5tsr3PFmk
# dLkB3IZYcbojZCYO7Mge23LBJ4qGM96CAR/4rbrHxqIQNHBu+nlR9O5a8Jq8VvZJ
# q+inJXhDGMFx6UthPkA/UijULfC46ZQHD37/oXqTuRYsAnqpL7rCCfsqJjFBPwIU
# 8BNSQ5HV/kDmO9mpgRPuc8YJO37ICK23w8FShbCezbmhqH88kUhL6bDkJLemrBk=
# SIG # End signature block
