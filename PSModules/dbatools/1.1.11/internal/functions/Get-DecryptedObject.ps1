function Get-DecryptedObject {
    <#
            .SYNOPSIS
                Internal function.

                This function is heavily based on Antti Rantasaari's script at http://goo.gl/wpqSib
                Antti Rantasaari 2014, NetSPI
                License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause
    #>
    param (
        [Parameter(Mandatory)]
        [Microsoft.SqlServer.Management.Smo.Server]$SqlInstance,
        [Parameter(Mandatory)]
        [ValidateSet("LinkedServer", "Credential")]
        [string]$Type,
        [switch]$EnableException
    )

    $server = $SqlInstance
    $sourceName = $server.Name

    # Query Service Master Key from the database - remove padding from the key
    # key_id 102 eq service master key, thumbprint 3 means encrypted with machinekey
    Write-Message -Level Verbose -Message "Querying service master key"
    $sql = "SELECT substring(crypt_property,9,len(crypt_property)-8) as smk FROM sys.key_encryptions WHERE key_id=102 and (thumbprint=0x03 or thumbprint=0x0300000001)"
    try {
        $smkbytes = $server.Query($sql).smk
    } catch {
        Stop-Function -Message "Can't execute query on $sourcename" -Target $server -ErrorRecord $_
        return
    }

    $fullComputerName = Resolve-DbaComputerName -ComputerName $server -Credential $Credential
    $instance = $server.InstanceName
    $serviceInstanceId = $server.ServiceInstanceId

    Write-Message -Level Verbose -Message "Get entropy from the registry - hopefully finds the right SQL server instance"

    try {
        [byte[]]$entropy = Invoke-Command2 -Raw -Credential $Credential -ComputerName $fullComputerName -argumentlist $serviceInstanceId {
            $serviceInstanceId = $args[0]
            $entropy = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$serviceInstanceId\Security\" -ErrorAction Stop).Entropy
            return $entropy
        }
    } catch {
        Stop-Function -Message "Can't access registry keys on $sourceName. Do you have administrative access to the Windows registry on $SqlInstance Otherwise, we're out of ideas." -Target $source
        return
    }

    Write-Message -Level Verbose -Message "Decrypt the service master key"
    try {
        $serviceKey = Invoke-Command2 -Raw -Credential $Credential -ComputerName $fullComputerName -ArgumentList $smkbytes, $Entropy {
            Add-Type -AssemblyName System.Security
            Add-Type -AssemblyName System.Core
            $smkbytes = $args[0]; $Entropy = $args[1]
            $serviceKey = [System.Security.Cryptography.ProtectedData]::Unprotect($smkbytes, $Entropy, 'LocalMachine')
            return $serviceKey
        }
    } catch {
        Stop-Function -Message "Can't unprotect registry data on $sourcename. Do you have administrative access to the Windows registry on $sourcename? Otherwise, we're out of ideas." -Target $source
        return
    }

    # Choose the encryption algorithm based on the SMK length - 3DES for 2008, AES for 2012
    # Choose IV length based on the algorithm
    Write-Message -Level Verbose -Message "Choose the encryption algorithm based on the SMK length - 3DES for 2008, AES for 2012"

    if (($serviceKey.Length -ne 16) -and ($serviceKey.Length -ne 32)) {
        Write-Message -Level Verbose -Message "ServiceKey found: $serviceKey.Length"
        Stop-Function -Message "Unknown key size. Do you have administrative access to the Windows registry on $sourcename? Otherwise, we're out of ideas." -Target $source
        return
    }

    if ($serviceKey.Length -eq 16) {
        $decryptor = New-Object System.Security.Cryptography.TripleDESCryptoServiceProvider
        $ivlen = 8
    } elseif ($serviceKey.Length -eq 32) {
        $decryptor = New-Object System.Security.Cryptography.AESCryptoServiceProvider
        $ivlen = 16
    }

    <#
        Query link server password information from the Db.
        Remove header from pwdhash, extract IV (as iv) and ciphertext (as pass)
        Ignore links with blank credentials (integrated auth ?)
    #>

    Write-Message -Level Verbose -Message "Query link server password information from the Db."

    try {
        if (-not $server.IsClustered) {
            $connString = "Server=ADMIN:$fullComputerName\$instance;Trusted_Connection=True;Pooling=false"
        } else {
            $dacEnabled = $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue

            if ($dacEnabled -eq $false) {
                If ($Pscmdlet.ShouldProcess($server.Name, "Enabling DAC on clustered instance.")) {
                    Write-Message -Level Verbose -Message "DAC must be enabled for clusters, even when accessed from active node. Enabling."
                    $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
                    $server.Configuration.Alter()
                }
            }

            $connString = "Server=ADMIN:$sourceName;Trusted_Connection=True;Pooling=false;"
        }
    } catch {
        Stop-Function -Message "Failure enabling DAC on $sourcename" -Target $source -ErrorRecord $_
    }

    <# NOTE: This query is accessing syslnklgns table. Can only be done via the DAC connection #>

    $sql = switch ($Type) {
        "LinkedServer" {
            "SELECT sysservers.srvname,
                syslnklgns.name,
                substring(syslnklgns.pwdhash,5,$ivlen) iv,
                substring(syslnklgns.pwdhash,$($ivlen + 5),
                len(syslnklgns.pwdhash)-$($ivlen + 4)) pass
            FROM master.sys.syslnklgns
                inner join master.sys.sysservers
                on syslnklgns.srvid=sysservers.srvid
            WHERE len(pwdhash) > 0"
        }
        "Credential" {
            "SELECT QUOTENAME(name) AS name,credential_identity,substring(imageval,5,$ivlen) iv, substring(imageval,$($ivlen + 5),len(imageval)-$($ivlen + 4)) pass from sys.credentials cred inner join sys.sysobjvalues obj on cred.credential_id = obj.objid where valclass=28 and valnum=2"
        }
    }

    Write-Message -Level Debug -Message $sql

    try {
        $results = Invoke-Command2 -ErrorAction Stop -Raw -Credential $Credential -ComputerName $fullComputerName -ArgumentList $connString, $sql {
            $connString = $args[0]
            $sql = $args[1]
            $conn = New-Object System.Data.SqlClient.SQLConnection($connString)
            $cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn)
            $dt = New-Object System.Data.DataTable
            $conn.open()
            $dt.Load($cmd.ExecuteReader())
            $conn.Close()
            $conn.Dispose()
            return $dt
        }
    } catch {
        try {
            $conn.Close()
            $conn.Dispose()
        } catch {
            $null = 1
        }
        Stop-Function -Message "Can't establish local DAC connection on $sourcename." -Target $server -ErrorRecord $_
        return
    }


    if ($server.IsClustered -and $dacEnabled -eq $false) {
        If ($Pscmdlet.ShouldProcess($server.Name, "Disabling DAC on clustered instance.")) {
            try {
                Write-Message -Level Verbose -Message "Setting DAC config back to 0."
                $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $false
                $server.Configuration.Alter()
            } catch {
                Stop-Function -Message "Can't establish local DAC connection on $sourcename" -Target $server -ErrorRecord $_
                return
            }
        }
    }

    Write-Message -Level Verbose -Message "Go through each row in results"
    foreach ($result in $results) {
        # decrypt the password using the service master key and the extracted IV
        $decryptor.Padding = "None"
        $decrypt = $decryptor.Createdecryptor($serviceKey, $result.iv)
        $stream = New-Object System.IO.MemoryStream ( , $result.pass)
        $crypto = New-Object System.Security.Cryptography.CryptoStream $stream, $decrypt, "Write"

        $crypto.Write($result.pass, 0, $result.pass.Length)
        [byte[]]$decrypted = $stream.ToArray()

        # convert decrypted password to unicode
        $encode = New-Object System.Text.UnicodeEncoding

        # Print results - removing the weird padding (8 bytes in the front, some bytes at the end)...
        # Might cause problems but so far seems to work.. may be dependant on SQL server version...
        # If problems arise remove the next three lines..
        $i = 8; foreach ($b in $decrypted) { if ($decrypted[$i] -ne 0 -and $decrypted[$i + 1] -ne 0 -or $i -eq $decrypted.Length) { $i -= 1; break; }; $i += 1; }
        $decrypted = $decrypted[8 .. $i]

        if ($Type -eq "LinkedServer") {
            $name = $result.srvname
            $identity = $result.Name
        } else {
            $name = $result.name
            $identity = $result.credential_identity
        }
        [pscustomobject]@{
            Name     = $name
            Identity = $identity
            Password = $encode.GetString($decrypted)
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUse4vRBXVug9EHdwFpZW6W6nv
# wQigghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFCol/FVQidt9Fd0Pa9+89sBC/HVzMA0GCSqGSIb3DQEBAQUABIIBAG+XyeYb
# tKLspBK6vAOq08kX2l8S/jwzFItzOmvm4eAxYejDkm3kFfFbkbKp3jlNgmZTy9L5
# GfctpYKgQEz4dWIxIYMSM8IuCLf1g8ZxQO9GZgqBWOornZUhzI/0vUVnu0caBRYR
# ersUS6IeA8MgcL9/f6+wCQJZXmMSHKnObFQO8i0ssqxNd9sTl/ErunQ6ayeGC0wJ
# gtwRim45lBJT2e2aHZAKS6o7m0QC0Vs7kZbnCYQtAN44vfFxmR4EcwX+xLXE7dy/
# Dqs0Zow33QCi6Q+6T+OhQzqskJahuWW0f1JMTlBRL8OZ8rrMsasfdGgJKV5se/SQ
# st+Wk3k0mfFGq4ChggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjYxOVowLwYJKoZIhvcNAQkEMSIEICJkDZs/XtDJ+dC1vGng3DqL0SLS
# IZfkIDZDTInJoz3RMA0GCSqGSIb3DQEBAQUABIIBAK+U+8JDQnPOMaUrYVAbZEUZ
# sysSVeKHQmFUA+vPFC9SFCVo1Ji50tLAZJFa33sscZjZgqW1n/H7MfZV02v3uC68
# slbDlH0Fh1ByR8ESa38FVP6k6MpndwWOwqWQyC93oATEL4HfnlU4EmNOI5qTopYA
# Jkazl9jM1XF4Y6qT1F6FJlGIu1lxZhvzaWW14shoPeuuf9mbkGnjDVF5S3kRP8bM
# CfXlkG7uG6Mj9N0hBDI4evy824CVCkWkh/VkXF7whCgu3y3KE+MTgwCzH2/y/fvU
# 7c6JoWWNE8ZjROpFqgsDCI7PMNHhh9L/W6LkoYTciOJRDNtZIXf7G7EZ5F/JnP8=
# SIG # End signature block
