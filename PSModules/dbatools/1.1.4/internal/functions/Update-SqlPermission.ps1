function Update-SqlPermission {
    <#
        .SYNOPSIS
            Internal function. Updates permission sets, roles, database mappings on server and databases
        .PARAMETER SourceServer
            Source Server
        .PARAMETER SourceLogin
            Source login
        .PARAMETER DestServer
            Destination Server
        .PARAMETER DestLogin
            Destination Login
        .PARAMETER ObjectLevel
            Use Export-DbaUser to update object-level permissions as well
        .PARAMETER EnableException
            Use this switch to disable any kind of verbose messages
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SourceServer,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SourceLogin,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$DestServer,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$DestLogin,
        [switch]$ObjectLevel,
        [switch]$EnableException
    )

    $destination = $DestServer.DomainInstanceName
    $source = $SourceServer.DomainInstanceName
    $loginName = $SourceLogin.Name
    $newLoginName = $DestLogin.Name

    $saname = Get-SaLoginName -SqlInstance $DestServer

    # gotta close because enum repeatedly causes problems with the datareader
    $null = $SourceServer.ConnectionContext.SqlConnectionObject.Close()
    $null = $DestServer.ConnectionContext.SqlConnectionObject.Close()

    # Server Roles: sysadmin, bulklogin, etc
    foreach ($role in $SourceServer.Roles) {
        $roleName = $role.Name
        $destRole = $DestServer.Roles[$roleName]

        if ($null -ne $destRole) {
            try {
                $destRoleMembers = $destRole.EnumMemberNames()
            } catch {
                $destRoleMembers = $destRole.EnumServerRoleMembers()
            }
        }

        try {
            $roleMembers = $role.EnumMemberNames()
        } catch {
            $roleMembers = $role.EnumServerRoleMembers()
        }

        if ($roleMembers -contains $loginName) {
            if ($null -ne $destRole) {
                if ($Pscmdlet.ShouldProcess($destination, "Adding $newLoginName to $roleName server role.")) {
                    if ($loginName -ne $saname) {
                        try {
                            $destRole.AddMember($newLoginName)
                            Write-Message -Level Verbose -Message "Adding $newLoginName to $roleName server role on $destination successfully performed."
                        } catch {
                            Stop-Function -Message "Failed to add $newLoginName to $roleName server role on $destination." -Target $role -ErrorRecord $_
                        }
                    }
                }
            }
        }

        # Remove for Syncs
        if ($roleMembers -notcontains $loginName -and $destRoleMembers -contains $newLoginName -and $null -ne $destRole) {
            if ($Pscmdlet.ShouldProcess($destination, "Adding $loginName to $roleName server role.")) {
                try {
                    $destRole.DropMember($loginName)
                    Write-Message -Level Verbose -Message "Removing $newLoginName from $destRoleName server role on $destination successfully performed."
                } catch {
                    Stop-Function -Message "Failed to remove $newLoginName from $destRoleName server role on $destination." -Target $role -ErrorRecord $_
                }
            }
        }
    }

    $ownedJobs = $SourceServer.JobServer.Jobs | Where-Object OwnerLoginName -eq $loginName
    foreach ($ownedJob in $ownedJobs) {
        if ($null -ne $DestServer.JobServer.Jobs[$ownedJob.Name]) {
            if ($Pscmdlet.ShouldProcess($destination, "Changing of job owner to $newLoginName for $($ownedJob.Name).")) {
                try {
                    $destOwnedJob = $DestServer.JobServer.Jobs | Where-Object { $_.Name -eq $ownedJob.Name }
                    $destOwnedJob.Set_OwnerLoginName($newLoginName)
                    $destOwnedJob.Alter()
                    Write-Message -Level Verbose -Message "Changing job owner to $newLoginName for $($ownedJob.Name) on $destination successfully performed."
                } catch {
                    Stop-Function -Message "Failed to change job owner for $($ownedJob.Name) to $newLoginName on $destination." -Target $ownedJob -ErrorRecord $_
                }
            }
        }
    }

    if ($SourceServer.VersionMajor -ge 9 -and $DestServer.VersionMajor -ge 9) {
        <#
            These operations are only supported by SQL Server 2005 and above.
            Securables: Connect SQL, View any database, Administer Bulk Operations, etc.
        #>

        $null = $sourceServer.ConnectionContext.SqlConnectionObject.Close()
        $null = $destServer.ConnectionContext.SqlConnectionObject.Close()

        $perms = $SourceServer.EnumServerPermissions($loginName)
        foreach ($perm in $perms) {
            $permState = $perm.PermissionState
            if ($permState -eq "GrantWithGrant") {
                $grantWithGrant = $true;
                $permState = "grant"
            } else {
                $grantWithGrant = $false
            }

            $permSet = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.PermissionType)
            if ($Pscmdlet.ShouldProcess($destination, "$permState on $($perm.PermissionType) for $newLoginName.")) {
                try {
                    $DestServer.PSObject.Methods[$permState].Invoke($permSet, $newLoginName, $grantWithGrant)
                    Write-Message -Level Verbose -Message "$permState $($perm.PermissionType) to $newLoginName on $destination successfully performed."
                } catch {
                    Stop-Function -Message "Failed to $permState $($perm.PermissionType) to $newLoginName on $destination." -Target $perm -ErrorRecord $_
                }
            }

            # for Syncs
            $destPerms = $DestServer.EnumServerPermissions($newLoginName)
            foreach ($perm in $destPerms) {
                $permState = $perm.PermissionState
                $sourcePerm = $perms | Where-Object { $_.PermissionType -eq $perm.PermissionType -and $_.PermissionState -eq $permState }

                if ($null -eq $sourcePerm) {
                    if ($Pscmdlet.ShouldProcess($destination, "Revoking $($perm.PermissionType) for $newLoginName.")) {
                        try {
                            $permSet = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.PermissionType)

                            if ($permState -eq "GrantWithGrant") {
                                $grantWithGrant = $true;
                                $permState = "grant"
                            } else {
                                $grantWithGrant = $false
                            }

                            $DestServer.PSObject.Methods["Revoke"].Invoke($permSet, $newLoginName, $false, $grantWithGrant)
                            Write-Message -Level Verbose -Message "Revoking $($perm.PermissionType) for $newLoginName on $destination successfully performed."
                        } catch {
                            Stop-Function -Message "Failed to revoke $($perm.PermissionType) from $newLoginName on $destination." -Target $perm -ErrorRecord $_
                        }
                    }
                }
            }
        }

        # Credential mapping. Credential removal not currently supported for Syncs.
        $loginCredentials = $SourceServer.Credentials | Where-Object { $_.Identity -eq $SourceLogin.Name }
        foreach ($credential in $loginCredentials) {
            if ($null -eq $DestServer.Credentials[$credential.Name]) {
                if ($Pscmdlet.ShouldProcess($destination, "Creating credential $($credential.Name) for $newLoginName.")) {
                    try {
                        $newCred = New-Object Microsoft.SqlServer.Management.Smo.Credential($DestServer, $credential.Name)
                        $newCred.Identity = $newLoginName
                        $newCred.Create()
                        Write-Message -Level Verbose -Message "Creating credential $($credential.Name) for $newLoginName on $destination successfully performed."
                    } catch {
                        Stop-Function -Message "Failed to create credential $($credential.Name) for $newLoginName on $destination." -Target $credential -ErrorRecord $_
                    }
                }
            }
        }
    }

    if ($DestServer.VersionMajor -lt 9) {
        Write-Message -Level Warning -Message "SQL Server 2005 or greater required for database mappings.";
        continue
    }

    # For Sync, if info doesn't exist in EnumDatabaseMappings, then no big deal.
    foreach ($db in $DestLogin.EnumDatabaseMappings()) {
        $dbName = $db.DbName
        $destDb = $DestServer.Databases[$dbName]
        $sourceDb = $SourceServer.Databases[$dbName]
        $newDbUsername = $db.Username;
        # Adjust renamed database usernames for old server
        if ($newDbUsername -eq $newLoginName) { $dbUsername = $loginName } else { $dbUsername = $newDbUsername }
        $dbLogin = $db.LoginName

        if ($null -ne $sourceDb) {
            if (-not $sourceDb.IsAccessible) {
                Write-Message -Level Verbose -Message "Database [$($sourceDb.Name)] is not accessible on $source. Skipping."
                continue
            }
            if (-not $destDb.IsAccessible) {
                Write-Message -Level Verbose -Message "Database [$($sourceDb.Name)] is not accessible on destination. Skipping."
                continue
            }
            if ((Get-DbaAgDatabase -SqlInstance $DestServer -Database $dbName -ErrorAction Ignore -WarningAction SilentlyContinue)) {
                Write-Message -Level Verbose -Message "Database [$dbName] is part of an availability group. Skipping."
                continue
            }
            if ($null -eq $sourceDb.Users[$dbUsername] -and $null -eq $destDb.Users[$newDbUsername]) {
                if ($Pscmdlet.ShouldProcess($destination, "Dropping user $dbUsername from $dbName.")) {
                    try {
                        $destDb.Users[$newDbUsername].Drop()
                        Write-Message -Level Verbose -Message "Dropping user $newDbUsername (login: $dbLogin) from $dbName on destination successfully performed."
                        Write-Message -Level Verbose -Message "Any schema in $dbaName owned by $newDbUsername may still exist."
                    } catch {
                        Stop-Function -Message "Failed to drop $newDbUsername (login: $dbLogin) from $dbName on destination." -Target $db -ErrorRecord $_
                    }
                }
            }

            # Remove user from role. Role removal not currently supported for Syncs.
            # TODO: reassign if dbo, application roles
            foreach ($destRole in $destDb.Roles) {
                $destRoleName = $destRole.Name
                $sourceRole = $sourceDb.Roles[$destRoleName]
                if ($null -eq $sourceRole) {
                    if ($destRole.EnumMembers() -contains $newDbUsername) {
                        if ($newDbUsername -ne "dbo") {
                            if ($Pscmdlet.ShouldProcess($destination, "Dropping user $newDbUsername from $destRoleName database role in $dbName.")) {
                                try {
                                    $destRole.DropMember($newDbUsername)
                                    $destDb.Alter()
                                    Write-Message -Level Verbose -Message "Dropping user $newDbUsername (login: $dbLogin) from $destRoleName database role in $dbName on $destination successfully performed."
                                } catch {
                                    Stop-Function -Message "Failed to remove $newDbUsername (login: $dbLogin) from $destRoleName database role in $dbName on $destination." -Target $destRole -ErrorRecord $_
                                }
                            }
                        }
                    }
                }
            }

            $null = $sourceDb.Parent.ConnectionContext.SqlConnectionObject.Close()
            $null = $destDb.Parent.ConnectionContext.SqlConnectionObject.Close()
            # Remove Connect, Alter Any Assembly, etc
            $destPerms = $destDb.EnumDatabasePermissions($newLoginName)
            $perms = $sourceDb.EnumDatabasePermissions($loginName)
            # for Syncs
            foreach ($perm in $destPerms) {
                $permState = $perm.PermissionState
                $sourcePerm = $perms | Where-Object { $_.PermissionType -eq $perm.PermissionType -and $_.PermissionState -eq $permState }
                if ($null -eq $sourcePerm) {
                    if ($Pscmdlet.ShouldProcess($destination, "Revoking $($perm.PermissionType) from $newLoginName in $dbName.")) {
                        try {
                            $permSet = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.PermissionType)

                            if ($permState -eq "GrantWithGrant") {
                                $grantWithGrant = $true;
                                $permState = "grant"
                            } else {
                                $grantWithGrant = $false
                            }

                            $destDb.PSObject.Methods["Revoke"].Invoke($permSet, $newLoginName, $false, $grantWithGrant)
                            Write-Message -Level Verbose -Message "Revoking $($perm.PermissionType) from $newLoginName in $dbName on $destination successfully performed."
                        } catch {
                            Stop-Function -Message "Failed to revoke $($perm.PermissionType) from $newLoginName in $dbName on $destination." -Target $perm -ErrorRecord $_
                        }
                    }
                }
            }
        }
    }

    # Adding database mappings and securables
    $null = $SourceLogin.Parent.ConnectionContext.SqlConnectionObject.Close()
    $null = $DestServer.ConnectionContext.SqlConnectionObject.Close()

    foreach ($db in $SourceLogin.EnumDatabaseMappings()) {
        $dbName = $db.DbName
        $destDb = $DestServer.Databases[$dbName]
        $sourceDb = $SourceServer.Databases[$dbName]
        $dbUsername = $db.Username;
        # Adjust renamed database usernames for new server
        if ($newLoginName -eq $loginName) { $newDbUsername = $dbUsername } else { $newDbUsername = $newLoginName }

        if ($null -ne $destDb) {
            if (-not $destDb.IsAccessible) {
                Write-Message -Level Verbose -Message "Database [$dbName] is not accessible. Skipping."
                continue
            }

            if ((Get-DbaAgDatabase -SqlInstance $DestServer -Database $dbName -ErrorAction Ignore -WarningAction SilentlyContinue)) {
                Write-Message -Level Verbose -Message "Database [$dbName] is part of an availability group. Skipping."
                continue
            }
            if ($null -eq $destDb.Users[$newDbUsername]) {
                if ($Pscmdlet.ShouldProcess($destination, "Adding $newDbUsername to $dbName.")) {
                    $sql = $SourceServer.Databases[$dbName].Users[$dbUsername].Script() | Out-String
                    try {
                        $destDb.ExecuteNonQuery($sql.Replace("[$dbUsername]", "[$newDbUsername]"))
                        Write-Message -Level Verbose -Message "Adding user $newDbUsername (login: $newLoginName) to $dbName successfully performed."
                    } catch {
                        Stop-Function -Message "Failed to add $newDbUsername (login: $newLoginName) to $dbName on $destination." -Target $db -ErrorRecord $_
                    }
                }
            }

            # Db owner
            if ($sourceDb.Owner -eq $loginName) {
                if ($Pscmdlet.ShouldProcess($destination, "Changing $dbName dbowner to $newLoginName.")) {
                    try {
                        if ($dbName -notin 'master', 'msdb', 'tempdb', 'model') {
                            $result = Set-DbaDbOwner -SqlInstance $DestServer -Database $dbName -TargetLogin $newLoginName -EnableException:$EnableException
                            if ($result.Owner -eq $newLoginName) {
                                Write-Message -Level Verbose -Message "Changed $($destDb.Name) owner to $newLoginName."
                            } else {
                                Write-Message -Level Warning -Message "Failed to update $($destDb.Name) owner to $newLoginName."
                            }
                        }
                    } catch {
                        Stop-Function -Message "Failed to update $($destDb.Name) owner to $newLoginName." -ErrorRecord $_
                    }
                }
            }

            if ($ObjectLevel) {
                if ($dbUsername -ne "dbo") {
                    $scriptOptions = New-DbaScriptingOption
                    $scriptVersion = $destDb.CompatibilityLevel
                    $scriptOptions.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
                    $scriptOptions.AllowSystemObjects = $false
                    $scriptOptions.IncludeDatabaseRoleMemberships = $true
                    $scriptOptions.ContinueScriptingOnError = $false
                    $scriptOptions.IncludeDatabaseContext = $false
                    $scriptOptions.IncludeIfNotExists = $true
                    $userScript = Export-DbaUser -SqlInstance $SourceServer -Database $dbName -User $dbUsername -Passthru -Template -ScriptingOptionsObject $scriptOptions -EnableException:$EnableException
                    $userScript = $userScript.Replace('{templateUser}', $newDbUsername)
                    $destDb.ExecuteNonQuery($userScript)
                }
            } else {
                # Database Roles: db_owner, db_datareader, etc
                foreach ($role in $sourceDb.Roles) {
                    $null = $sourceDb.Parent.ConnectionContext.SqlConnectionObject.Close()
                    $null = $destDb.Parent.ConnectionContext.SqlConnectionObject.Close()
                    if ($role.EnumMembers() -contains $loginName) {
                        $roleName = $role.Name
                        $destDbRole = $destDb.Roles[$roleName]

                        if ($null -ne $destDbRole -and $dbUsername -ne "dbo" -and $destDbRole.EnumMembers() -notcontains $newDbUsername) {
                            if ($Pscmdlet.ShouldProcess($destination, "Adding $newDbUsername to $roleName database role in $dbName.")) {
                                try {
                                    $destDbRole.AddMember($newDbUsername)
                                    $destDb.Alter()
                                    Write-Message -Level Verbose -Message "Adding $newDbUsername to $roleName database role in $dbName on $destination successfully performed."
                                } catch {
                                    Stop-Function -Message "Failed to add $newDbUsername to $roleName database role in $dbName on $destination." -Target $role -ErrorRecord $_
                                }
                            }
                        }
                    }
                }
                # Connect, Alter Any Assembly, etc
                $null = $sourceDb.Parent.ConnectionContext.SqlConnectionObject.Close()
                $perms = $sourceDb.EnumDatabasePermissions($loginName)
                foreach ($perm in $perms) {
                    $permState = $perm.PermissionState
                    if ($permState -eq "GrantWithGrant") {
                        $grantWithGrant = $true;
                        $permState = "grant"
                    } else {
                        $grantWithGrant = $false
                    }
                    $permSet = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.PermissionType)

                    if ($Pscmdlet.ShouldProcess($destination, "$permState on $($perm.PermissionType) for $newDbUsername on $dbName")) {
                        try {
                            $destDb.PSObject.Methods[$permState].Invoke($permSet, $newDbUsername, $grantWithGrant)
                            Write-Message -Level Verbose -Message "$permState on $($perm.PermissionType) to $newDbUsername on $dbName on $destination successfully performed."
                        } catch {
                            Stop-Function -Message "Failed to perform $permState on $($perm.PermissionType) to $newDbUsername on $dbName on $destination." -Target $perm -ErrorRecord $_
                        }
                    }
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQULTrLZ+Z0MKsAglR0wsshJIQl
# +WegghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFPBViTgeau9unpxRRMZ4zAaF6MkxMA0GCSqGSIb3DQEBAQUABIIBAI5yFk81
# t51x36bNNFFMn9GjMuV229xHVaobu+9SKHPC+658ucmVjqbNSijNNvir5EfOnPBJ
# mMLhTDXu8p+wdFhUE8ybXLlZys20goOUEBSKWfc9FTvqjobAPYXYxqZxRSuNitzN
# NzM/sRkZkc36+sQcGquLrsrt/qc0ArxMw/QaDwa29FsCFOcmzOwar1GPfthX3uIf
# OL+52nLQgPU2fGKK4tsOujKNEhgkxhqN/4XCLBe6i42q089E+FS69YaycfTLPtjx
# SDxdKFCtapre8fe7OVyXnrFmHM1Wc4/T4F3cirqkKua3y4jfN14h3hYS60lpS3jC
# d+QJw7fGoZxBPDGhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAzOVowLwYJKoZIhvcNAQkEMSIEIKe9Q30aDfAugWVmYxKbwjlEM//v
# QYo547Hlfq+KOjuDMA0GCSqGSIb3DQEBAQUABIIBAJe+Nxbi6XAH8Av/bxqztr4p
# 1bWYhZw+Ud1MQYOMy6avhQfr8uaT1001vFFL8hfsd2lslxubMkBnsmRhWaS0Z4X9
# 7e6Ex0UGk3Uu5dwdsCX8byenqT1VTXcTgXgSE9wLYoCXIiG8MxWcXlWNHoMTVHkq
# qXBubtDz61tJiK5h62vzRM3Hfxg4ZZAJ5Aqlu4tT791Q8X31e3Q2czKZVpWVbMQn
# ssJJa3iAPKoJ7+xJSVVuzpWGPmdU2XPOB1d+kFAvmYcUn8yFtbtrXriLkwTUVtRH
# SDC2eT8Lej2BjpFOaboFN8u5lWVjVg53hh1QX5DhtH2nlesxbqPRyHFR0P/Qk8I=
# SIG # End signature block
