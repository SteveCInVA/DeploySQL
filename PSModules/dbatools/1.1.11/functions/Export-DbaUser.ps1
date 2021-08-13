function Export-DbaUser {
    <#
    .SYNOPSIS
        Exports users creation and its permissions to a T-SQL file or host.

    .DESCRIPTION
        Exports users creation and its permissions to a T-SQL file or host. Export includes user, create and add to role(s), database level permissions, object level permissions.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server 2000 and above supported.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all InputObject will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER User
        Export only the specified database user(s). If not specified will export all users from the database(s)

    .PARAMETER DestinationVersion
        To say to which version the script should be generated. If not specified will use database compatibility level

    .PARAMETER Encoding
        Specifies the file encoding. The default is UTF8.

        Valid values are:
        -- ASCII: Uses the encoding for the ASCII (7-bit) character set.
        -- BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.
        -- Byte: Encodes a set of characters into a sequence of bytes.
        -- String: Uses the encoding type for a string.
        -- Unicode: Encodes in UTF-16 format using the little-endian byte order.
        -- UTF7: Encodes in UTF-7 format.
        -- UTF8: Encodes in UTF-8 format.
        -- Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER InputObject
        Allows database objects to be piped in from Get-DbaDatabase

    .PARAMETER NoClobber
        Do not overwrite file

    .PARAMETER Append
        Append to file

    .PARAMETER Passthru
        Output script to console, useful with | clip

    .PARAMETER Template
        Script user as a templated string that contains tokens {templateUser} and {templateLogin} instead of username and login

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER ScriptingOptionsObject
        A Microsoft.SqlServer.Management.Smo.ScriptingOptions object with the options that you want to use to generate the t-sql script.
        You can use the NEw-DbaScriptingOption to generate it.

    .PARAMETER ExcludeGoBatchSeparator
        If specified, will NOT script the 'GO' batch separator.

    .NOTES
        Tags: User, Export
        Author: Claudio Silva (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaUser

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sql2005 -FilePath C:\temp\sql2005-users.sql

        Exports SQL for the users in server "sql2005" and writes them to the file "C:\temp\sql2005-users.sql"

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2014a $scred -FilePath C:\temp\users.sql -Append

        Authenticates to sqlserver2014a using SQL Authentication. Exports all users to C:\temp\users.sql, and appends to the file if it exists. If not, the file will be created.

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2014a -User User1, User2 -FilePath C:\temp\users.sql

        Exports ONLY users User1 and User2 from sqlserver2014a to the file C:\temp\users.sql

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2014a -User User1, User2 -Path C:\temp

        Exports ONLY users User1 and User2 from sqlserver2014a to the folder C:\temp. One file per user will be generated

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -User User1 -FilePath C:\temp\users.sql -DestinationVersion SQLServer2016

        Exports user User1 from sqlserver2008 to the file C:\temp\users.sql with syntax to run on SQL Server 2016

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -Database db1,db2 -FilePath C:\temp\users.sql

        Exports ONLY users from db1 and db2 database on sqlserver2008 server, to the C:\temp\users.sql file.

    .EXAMPLE
        PS C:\> $options = New-DbaScriptingOption
        PS C:\> $options.ScriptDrops = $false
        PS C:\> $options.WithDependencies = $true
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -Database db1,db2 -FilePath C:\temp\users.sql -ScriptingOptionsObject $options

        Exports ONLY users from db1 and db2 database on sqlserver2008 server, to the C:\temp\users.sql file.
        It will not script drops but will script dependencies.

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -Database db1,db2 -FilePath C:\temp\users.sql -ExcludeGoBatchSeparator

        Exports ONLY users from db1 and db2 database on sqlserver2008 server, to the C:\temp\users.sql file without the 'GO' batch separator.

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -Database db1 -User user1 -Template -PassThru

        Exports user1 from database db1, replacing loginname and username with {templateLogin} and {templateUser} correspondingly.


    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    [OutputType([String])]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$User,
        [ValidateSet('SQLServer2000', 'SQLServer2005', 'SQLServer2008/2008R2', 'SQLServer2012', 'SQLServer2014', 'SQLServer2016', 'SQLServer2017', 'SQLServer2019')]
        [string]$DestinationVersion,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [Alias("NoOverwrite")]
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$Passthru,
        [switch]$Template,
        [switch]$EnableException,
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject = $null,
        [switch]$ExcludeGoBatchSeparator
    )

    begin {
        $null = Test-ExportDirectory -Path $Path

        $outsql = $script:pathcollection = $instanceArray = @()
        $GenerateFilePerUser = $false

        $versions = @{
            'SQLServer2000'        = 'Version80'
            'SQLServer2005'        = 'Version90'
            'SQLServer2008/2008R2' = 'Version100'
            'SQLServer2012'        = 'Version110'
            'SQLServer2014'        = 'Version120'
            'SQLServer2016'        = 'Version130'
            'SQLServer2017'        = 'Version140'
            'SQLServer2019'        = 'Version150'
        }

        $versionName = @{
            'Version80'  = 'SQLServer2000'
            'Version90'  = 'SQLServer2005'
            'Version100' = 'SQLServer2008/2008R2'
            'Version110' = 'SQLServer2012'
            'Version120' = 'SQLServer2014'
            'Version130' = 'SQLServer2016'
            'Version140' = 'SQLServer2017'
            'Version150' = 'SQLServer2019'
        }

        $eol = [System.Environment]::NewLine

    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        # To keep the filenames generated and re-use (append) if needed
        $usersProcessed = @{ }

        foreach ($db in $InputObject) {

            if ([string]::IsNullOrEmpty($destinationVersion)) {
                #Get compatibility level for scripting the objects
                $scriptVersion = $db.CompatibilityLevel
            } else {
                $scriptVersion = $versions[$destinationVersion]
            }
            $versionNameDesc = $versionName[$scriptVersion.ToString()]

            #If not passed create new ScriptingOption. Otherwise use the one that was passed
            if ($null -eq $ScriptingOptionsObject) {
                $ScriptingOptionsObject = New-DbaScriptingOption
                $ScriptingOptionsObject.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
                $ScriptingOptionsObject.AllowSystemObjects = $false
                $ScriptingOptionsObject.IncludeDatabaseRoleMemberships = $true
                $ScriptingOptionsObject.ContinueScriptingOnError = $false
                $ScriptingOptionsObject.IncludeDatabaseContext = $false
                $ScriptingOptionsObject.IncludeIfNotExists = $true
            }

            Write-Message -Level Verbose -Message "Validating users on database $db"

            if ($User) {
                $users = $db.Users | Where-Object { $User -contains $_.Name -and $_.IsSystemObject -eq $false -and $_.Name -notlike "##*" }
            } else {
                $users = $db.Users
            }

            # Generate the file path
            if (Test-Bound -ParameterName FilePath -Not) {
                $GenerateFilePerUser = $true
            } else {
                # Generate a new file name with passed/default path
                $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $db.Parent.Name -Unique
            }

            # Store roles between users so if we hit the same one we don't create it again
            $roles = @()
            $stepCounter = 0
            foreach ($dbuser in $users) {

                if ($GenerateFilePerUser) {
                    if ($null -eq $usersProcessed[$dbuser.Name]) {
                        # If user and not specific output file, create file name without database name.
                        $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $("$($db.Parent.Name)-$($dbuser.Name)") -Unique
                        $usersProcessed[$dbuser.Name] = $FilePath
                    } else {
                        $Append = $true
                        $FilePath = $usersProcessed[$dbuser.Name]
                    }
                }

                Write-ProgressHelper -TotalSteps $users.Count -Activity "Exporting from $($db.Name)" -StepNumber ($stepCounter++) -Message "Generating script ($FilePath) for user $dbuser"

                #setting database
                if (((Test-Bound ScriptingOptionsObject) -and $ScriptingOptionsObject.IncludeDatabaseContext) -or - (Test-Bound ScriptingOptionsObject -Not)) {
                    $useDatabase = "USE [" + $db.Name + "]"
                }

                try {
                    #Fixed Roles #Dependency Issue. Create Role, before add to role.
                    foreach ($rolePermission in ($db.Roles | Where-Object { $_.IsFixedRole -eq $false })) {
                        foreach ($rolePermissionScript in $rolePermission.Script($ScriptingOptionsObject)) {
                            if ($rolePermission.ToString() -notin $roles) {
                                $roles += , $rolePermission.ToString()
                                $outsql += "$($rolePermissionScript.ToString())"
                            }

                        }
                    }

                    #Database Create User(s) and add to Role(s)
                    foreach ($dbUserPermissionScript in $dbuser.Script($ScriptingOptionsObject)) {
                        if ($dbuserPermissionScript.Contains("sp_addrolemember")) {
                            $execute = "EXEC "
                        } else {
                            $execute = ""
                        }
                        $permissionScript = $dbUserPermissionScript.ToString()
                        if ($Template) {
                            $escapedUsername = [regex]::Escape($dbuser.Name)
                            $permissionScript = $permissionScript -replace "\`[$escapedUsername\`]", '[{templateUser}]'
                            $permissionScript = $permissionScript -replace "'$escapedUsername'", "'{templateUser}'"
                            if ($dbuser.Login) {
                                $escapedLogin = [regex]::Escape($dbuser.Login)
                                $permissionScript = $permissionScript -replace "\`[$escapedLogin\`]", '[{templateLogin}]'
                                $permissionScript = $permissionScript -replace "'$escapedLogin'", "'{templateLogin}'"
                            }

                        }
                        $outsql += "$execute$($permissionScript)"
                    }

                    #Database Permissions
                    foreach ($databasePermission in $db.EnumDatabasePermissions() | Where-Object { @("sa", "dbo", "information_schema", "sys") -notcontains $_.Grantee -and $_.Grantee -notlike "##*" -and ($dbuser.Name -contains $_.Grantee) }) {
                        if ($databasePermission.PermissionState -eq "GrantWithGrant") {
                            $withGrant = " WITH GRANT OPTION"
                            $grantDatabasePermission = 'GRANT'
                        } else {
                            $withGrant = " "
                            $grantDatabasePermission = $databasePermission.PermissionState.ToString().ToUpper()
                        }
                        if ($Template) {
                            $grantee = "{templateUser}"
                        } else {
                            $grantee = $databasePermission.Grantee
                        }

                        $outsql += "$($grantDatabasePermission) $($databasePermission.PermissionType) TO [$grantee]$withGrant AS [$($databasePermission.Grantor)];"
                    }

                    #Database Object Permissions
                    # NB: This is a bit of a mess for a couple of reasons
                    # 1. $db.EnumObjectPermissions() doesn't enumerate all object types
                    # 2. Some (x)Collection types can have EnumObjectPermissions() called
                    #    on them directly (e.g. AssemblyCollection); others can't (e.g.
                    #    ApplicationRoleCollection). Those that can't we iterate the
                    #    collection explicitly and add each object's permission.

                    $perms = New-Object System.Collections.ArrayList

                    $null = $perms.AddRange($db.EnumObjectPermissions($dbuser.Name))

                    foreach ($item in $db.ApplicationRoles) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.Assemblies) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.Certificates) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.DatabaseRoles) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.FullTextCatalogs) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.FullTextStopLists) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.SearchPropertyLists) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.MessageTypes) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.RemoteServiceBindings) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.Routes) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.ServiceContracts) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.Services) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    if ($scriptVersion -ne "Version80") {
                        foreach ($item in $db.AsymmetricKeys) {
                            $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                        }
                    }

                    foreach ($item in $db.SymmetricKeys) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.XmlSchemaCollections) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($objectPermission in $perms | Where-Object { @("sa", "dbo", "information_schema", "sys") -notcontains $_.Grantee -and $_.Grantee -notlike "##*" -and $_.Grantee -eq $dbuser.Name }) {
                        switch ($objectPermission.ObjectClass) {
                            'ApplicationRole' {
                                $object = 'APPLICATION ROLE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'AsymmetricKey' {
                                $object = 'ASYMMETRIC KEY::[{0}]' -f $objectPermission.ObjectName
                            }
                            'Certificate' {
                                $object = 'CERTIFICATE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'DatabaseRole' {
                                $object = 'ROLE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'FullTextCatalog' {
                                $object = 'FULLTEXT CATALOG::[{0}]' -f $objectPermission.ObjectName
                            }
                            'FullTextStopList' {
                                $object = 'FULLTEXT STOPLIST::[{0}]' -f $objectPermission.ObjectName
                            }
                            'MessageType' {
                                $object = 'Message Type::[{0}]' -f $objectPermission.ObjectName
                            }
                            'ObjectOrColumn' {
                                if ($scriptVersion -ne "Version80") {
                                    $object = 'OBJECT::[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
                                    if ($null -ne $objectPermission.ColumnName) {
                                        $object += '([{0}])' -f $objectPermission.ColumnName
                                    }
                                }
                                #At SQL Server 2000 OBJECT did not exists
                                else {
                                    $object = '[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
                                }
                            }
                            'RemoteServiceBinding' {
                                $object = 'REMOTE SERVICE BINDING::[{0}]' -f $objectPermission.ObjectName
                            }
                            'Schema' {
                                $object = 'SCHEMA::[{0}]' -f $objectPermission.ObjectName
                            }
                            'SearchPropertyList' {
                                $object = 'SEARCH PROPERTY LIST::[{0}]' -f $objectPermission.ObjectName
                            }
                            'Service' {
                                $object = 'SERVICE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'ServiceContract' {
                                $object = 'CONTRACT::[{0}]' -f $objectPermission.ObjectName
                            }
                            'ServiceRoute' {
                                $object = 'ROUTE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'SqlAssembly' {
                                $object = 'ASSEMBLY::[{0}]' -f $objectPermission.ObjectName
                            }
                            'SymmetricKey' {
                                $object = 'SYMMETRIC KEY::[{0}]' -f $objectPermission.ObjectName
                            }
                            'User' {
                                $object = 'USER::[{0}]' -f $objectPermission.ObjectName
                            }
                            'UserDefinedType' {
                                $object = 'TYPE::[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
                            }
                            'XmlNamespace' {
                                $object = 'XML SCHEMA COLLECTION::[{0}]' -f $objectPermission.ObjectName
                            }
                        }

                        if ($objectPermission.PermissionState -eq "GrantWithGrant") {
                            $withGrant = " WITH GRANT OPTION"
                            $grantObjectPermission = 'GRANT'
                        } else {
                            $withGrant = " "
                            $grantObjectPermission = $objectPermission.PermissionState.ToString().ToUpper()
                        }
                        if ($Template) {
                            $grantee = "{templateUser}"
                        } else {
                            $grantee = $databasePermission.Grantee
                        }

                        $outsql += "$grantObjectPermission $($objectPermission.PermissionType) ON $object TO [$grantee]$withGrant AS [$($objectPermission.Grantor)];"
                    }

                } catch {
                    Stop-Function -Message "This user may be using functionality from $($versionName[$db.CompatibilityLevel.ToString()]) that does not exist on the destination version ($versionNameDesc)." -Continue -InnerErrorRecord $_ -Target $db
                }

                if (@($outsql.Count) -gt 0) {
                    if ($ExcludeGoBatchSeparator) {
                        $sql = "$useDatabase $outsql"
                    } else {
                        if ($useDatabase) {
                            $sql = "$useDatabase$($eol)GO$eol" + ($outsql -join "$($eol)GO$eol")
                        } else {
                            $sql = $outsql -join "$($eol)GO$eol"
                        }
                        #add the final GO
                        $sql += "$($eol)GO"
                    }
                }

                if (-not $Passthru) {
                    # If generate a file per user, clean the collection to populate with next one
                    if ($GenerateFilePerUser) {
                        if (-not [string]::IsNullOrEmpty($sql)) {
                            $sql | Out-File -Encoding:$Encoding -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
                            Get-ChildItem -Path $FilePath
                        }
                    } else {
                        $dbUserInstance = $dbuser.Parent.Parent.Name

                        if ($instanceArray -notcontains $($dbUserInstance)) {
                            $sql | Out-File -Encoding:$Encoding -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
                            $instanceArray += $dbUserInstance
                        } else {
                            $sql | Out-File -Encoding:$Encoding -FilePath $FilePath -Append
                        }
                    }
                    # Clear variables for next user
                    $outsql = @()
                    $sql = ""
                } else {
                    $sql
                }
            }
        }
        # Just a single file, output path once here
        if (-Not $GenerateFilePerUser -and $FilePath) {
            Get-ChildItem -Path $FilePath
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUsj1Yi+1mU+fIDH6BsCT54hur
# nTugghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFLQiJVkDrm9AxTJ5MKzKzwPq9XYoMA0GCSqGSIb3DQEBAQUABIIBALqRRaKt
# eyL1hxMg4XW/rpykOX9FzLanYBH88HIa1GlRImuNJPR+fswVO9m/qb8kNo3LyPMG
# YHWgwFKAkM9XKQOXZ4aAOHYxGQLxx0dZS5FeB9wYYzH4v41GcbrePqGkoBOTX4JB
# 4xKJb6tyMzraCkogNu3i4k57R/FYh2W9uKP9CSePfYzuvkFVs8wMKjJS9otU3+NC
# Pz9Lrb8nyKOlOzpIHs9IN4IZFcNBMJfnBT0ZR5RBoBqAF7HjQaLbxc6qgUQa7A7O
# UBjmh1r3ycGpvAK3Kae1hJvqMXWs/eG+hLLRH8USO6ZomkOU82Gtmih6hdI5iezd
# t2RXeEvCqFsZzlChggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjUwNVowLwYJKoZIhvcNAQkEMSIEIOazsIpfQeUUaKpc/Rdz3nbENf5s
# FdOJQcHBcT0R7l3dMA0GCSqGSIb3DQEBAQUABIIBAGsrC90VC4Owg7oW/km84hEx
# pIH9CD3L7zmBNfUJSDC1cclqNdSHSkFj4NYcEhmSnNWyYu1yblFP2UP6kR0u0DPb
# HIuLKpuNEwSAEzrq5Uld74BT8ibPXDiAqXtrjq5xnq3Gac9AqMHHTs27p/bIZ8WI
# jvA/nTK7JAhY3Tb2xwkTv0UQGbhZ2F1CA4ueJh0txBoWZzInlC17wtYx9DfNnnCO
# +F4FjBuZ5bc1U0zcB7hxZB1W6heYf5zoDZOj43AIr5DniOOXahN5HxKYbxbPoQa4
# NVI1IkiD6c3AChrW3TXiSvBoE8og3jUwX/qy6E0vMaRTIgFvvj7FMUaO1V+sgqE=
# SIG # End signature block
