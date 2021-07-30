function New-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Creates a new computer certificate useful for Forcing Encryption

    .DESCRIPTION
        Creates a new computer certificate - self-signed or signed by an Active Directory CA, using the Web Server certificate.

        By default, a key with a length of 1024 and a friendly name of the machines FQDN is generated.

        This command was originally intended to help automate the process so that SSL certificates can be available for enforcing encryption on connections.

        It makes a lot of assumptions - namely, that your account is allowed to auto-enroll and that you have permission to do everything it needs to do ;)

        References:
        https://www.itprotoday.com/sql-server/7-steps-ssl-encryption
        https://azurebi.jppp.org/2016/01/23/using-lets-encrypt-certificates-for-secure-sql-server-connections/
        https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/

        The certificate is generated using AD's webserver SSL template on the client machine and pushed to the remote machine.

    .PARAMETER ComputerName
       The target SQL Server instance or instances. Defaults to localhost. If target is a cluster, you must also specify ClusterInstanceName (see below)

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER CaServer
        Optional - the CA Server where the request will be sent to

    .PARAMETER CaName
        The properly formatted CA name of the corresponding CaServer

    .PARAMETER ClusterInstanceName
        When creating certs for a cluster, use this parameter to create the certificate for the cluster node name. Use ComputerName for each of the nodes.

    .PARAMETER SecurePassword
        Password to encrypt/decrypt private key for export to remote machine

    .PARAMETER FriendlyName
        The FriendlyName listed in the certificate. This defaults to the FQDN of the $ComputerName

    .PARAMETER CertificateTemplate
        The domain's Certificate Template - WebServer by default.

    .PARAMETER KeyLength
        The length of the key - defaults to 1024

    .PARAMETER Store
        Certificate store - defaults to LocalMachine

    .PARAMETER Folder
        Certificate folder - defaults to My (Personal)

    .PARAMETER Dns
        Specify the Dns entries listed in SAN. By default, it will be ComputerName + FQDN, or in the case of clusters, clustername + cluster FQDN.

    .PARAMETER SelfSigned
        Creates a self-signed certificate. All other parameters can still apply except CaServer and CaName because the command does not go and get the certificate signed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: Certificate
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaComputerCertificate

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate

        Creates a computer certificate signed by the local domain CA for the local machine with the keylength of 1024.

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -ComputerName Server1

        Creates a computer certificate signed by the local domain CA _on the local machine_ for server1 with the keylength of 1024.

        The certificate is then copied to the new machine over WinRM and imported.

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -ComputerName sqla, sqlb -ClusterInstanceName sqlcluster -KeyLength 4096

        Creates a computer certificate for sqlcluster, signed by the local domain CA, with the keylength of 4096.

        The certificate is then copied to sqla _and_ sqlb over WinRM and imported.

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -ComputerName Server1 -WhatIf

        Shows what would happen if the command were run

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -SelfSigned

        Creates a self-signed certificate

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string]$CaServer,
        [string]$CaName,
        [string]$ClusterInstanceName,
        [Alias("Password")]
        [securestring]$SecurePassword,
        [string]$FriendlyName = "SQL Server",
        [string]$CertificateTemplate = "WebServer",
        [int]$KeyLength = 1024,
        [string]$Store = "LocalMachine",
        [string]$Folder = "My",
        [string[]]$Dns,
        [switch]$SelfSigned,
        [switch]$EnableException
    )
    begin {
        $englishCodes = 9, 1033, 2057, 3081, 4105, 5129, 6153, 7177, 8201, 9225
        if ($englishCodes -notcontains (Get-DbaCmObject -ClassName Win32_OperatingSystem).OSLanguage) {
            Stop-Function -Message "Currently, this command is only supported in English OS locales. OS Locale detected: $([System.Globalization.CultureInfo]::GetCultureInfo([int](Get-DbaCmObject Win32_OperatingSystem).OSLanguage).DisplayName)`nWe apologize for the inconvenience and look into providing universal language support in future releases."
            return
        }

        if (-not (Test-ElevationRequirement -ComputerName $env:COMPUTERNAME)) {
            return
        }

        function GetHexLength {
            [cmdletbinding()]
            param(
                [int]$strLen
            )
            $hex = [String]::Format("{0:X2}", $strLen)

            if ($strLen -gt 127) { [String]::Format("{0:X2}", 128 + ($hex.Length / 2)) + $hex }
            else { $hex }
        }

        function Get-SanExt {
            [cmdletbinding()]
            param(
                [string[]]$hostName
            )
            # thanks to Lincoln of
            # https://social.technet.microsoft.com/Forums/windows/en-US/f568edfa-7f93-46a4-aab9-a06151592dd9/converting-ascii-to-asn1-der

            $temp = ''
            foreach ($fqdn in $hostName) {
                # convert each character of fqdn to hex
                $hexString = ($fqdn.ToCharArray() | ForEach-Object { [String]::Format("{0:X2}", [int]$_) }) -join ''

                # length of hex fqdn, in hex
                $hexLength = GetHexLength ($hexString.Length / 2)

                # concatenate special code 82, hex length, hex string
                $temp += "82${hexLength}${hexString}"
            }
            # calculate total length of concatenated string, in hex
            $totalHexLength = GetHexLength ($temp.Length / 2)
            # concatenate special code 30, hex length, hex string
            $temp = "30${totalHexLength}${temp}"
            # convert to binary
            $bytes = $(
                for ($i = 0; $i -lt $temp.Length; $i += 2) {
                    [byte]"0x$($temp.SubString($i, 2))"
                }
            )
            # convert to base 64
            $base64 = [Convert]::ToBase64String($bytes)
            # output in proper format
            for ($i = 0; $i -lt $base64.Length; $i += 64) {
                $line = $base64.SubString($i, [Math]::Min(64, $base64.Length - $i))
                if ($i -eq 0) { "2.5.29.17=$line" }
                else { "_continue_=$line" }
            }
        }

        if ((-not $CaServer -or !$CaName) -and !$SelfSigned) {
            try {
                Write-Message -Level Verbose -Message "No CaServer or CaName specified. Performing lookup."
                # hat tip Vadims Podans
                $domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
                $domain = "DC=" + $domain -replace '\.', ", DC="
                $pks = [ADSI]"LDAP://CN=Enrollment Services, CN=Public Key Services, CN=Services, CN=Configuration, $domain"
                $cas = $pks.psBase.Children

                $allCas = @()
                foreach ($ca in $cas) {
                    $allCas += [pscustomobject]@{
                        CA       = $ca | ForEach-Object { $_.Name }
                        Computer = $ca | ForEach-Object { $_.DNSHostName }
                    }
                }
            } catch {
                Stop-Function -Message "Cannot access Active Directory or find the Certificate Authority" -ErrorRecord $_
                return
            }

            if (-not $CaServer) {
                $CaServer = ($allCas | Select-Object -First 1).Computer
                Write-Message -Level Verbose -Message "Root Server: $CaServer"
            }

            if (-not $CaName) {
                $CaName = ($allCas | Select-Object -First 1).CA
                Write-Message -Level Verbose -Message "Root CA name: $CaName"
            }
        }

        $tempDir = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
        $certTemplate = "CertificateTemplate:$CertificateTemplate"
    }

    process {
        if (Test-FunctionInterrupt) { return }

        # uses dos command locally


        foreach ($computer in $ComputerName) {
            $stepCounter = 0

            if (-not $secondaryNode) {

                if ($ClusterInstanceName) {
                    if ($ClusterInstanceName -notmatch "\.") {
                        $fqdn = "$ClusterInstanceName.$env:USERDNSDOMAIN"
                    } else {
                        $fqdn = $ClusterInstanceName
                    }
                } else {
                    $resolved = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -WarningAction SilentlyContinue

                    if (-not $resolved) {
                        $fqdn = "$ComputerName.$env:USERDNSDOMAIN"
                        Write-Message -Level Warning -Message "Server name cannot be resolved. Guessing it's $fqdn"
                    } else {
                        $fqdn = $resolved.fqdn
                    }
                }

                $certDir = "$tempDir\$fqdn"
                $certCfg = "$certDir\request.inf"
                $certCsr = "$certDir\$fqdn.csr"
                $certCrt = "$certDir\$fqdn.crt"
                $certPfx = "$certDir\$fqdn.pfx"
                $tempPfx = "$certDir\temp-$fqdn.pfx"

                if (Test-Path($certDir)) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Deleting files from $certDir"
                    $null = Remove-Item "$certDir\*.*"
                } else {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Creating $certDir"
                    $null = New-Item -Path $certDir -ItemType Directory -Force
                }

                # Make sure output is compat with clusters
                $shortName = $fqdn.Split(".")[0]

                if (-not $dns) {
                    $dns = $shortName, $fqdn
                }

                $san = Get-SanExt $dns
                # Write config file
                Set-Content $certCfg "[Version]"
                Add-Content $certCfg 'Signature="$Windows NT$"'
                Add-Content $certCfg "[NewRequest]"
                Add-Content $certCfg "Subject = ""CN=$fqdn"""
                Add-Content $certCfg "KeySpec = 1"
                Add-Content $certCfg "KeyLength = $KeyLength"
                Add-Content $certCfg "Exportable = TRUE"
                Add-Content $certCfg "MachineKeySet = TRUE"
                Add-Content $certCfg "FriendlyName=""$FriendlyName"""
                Add-Content $certCfg "SMIME = False"
                Add-Content $certCfg "PrivateKeyArchive = FALSE"
                Add-Content $certCfg "UserProtected = FALSE"
                Add-Content $certCfg "UseExistingKeySet = FALSE"
                Add-Content $certCfg "ProviderName = ""Microsoft RSA SChannel Cryptographic Provider"""
                Add-Content $certCfg "ProviderType = 12"
                if ($SelfSigned) {
                    Add-Content $certCfg "RequestType = Cert"
                } else {
                    Add-Content $certCfg "RequestType = PKCS10"
                }
                Add-Content $certCfg "KeyUsage = 0xa0"
                Add-Content $certCfg "[EnhancedKeyUsageExtension]"
                Add-Content $certCfg "OID=1.3.6.1.5.5.7.3.1"
                Add-Content $certCfg "[Extensions]"
                Add-Content $certCfg $san
                Add-Content $certCfg "Critical=2.5.29.17"


                if ($PScmdlet.ShouldProcess("local", "Creating certificate for $computer")) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Running: certreq -new $certCfg $certCsr"
                    $create = certreq -new $certCfg $certCsr
                }

                if ($SelfSigned) {
                    $serial = (($create -Split "Serial Number:" -Split "Subject")[2]).Trim() # D:
                    $storedCert = Get-ChildItem Cert:\LocalMachine\My -Recurse | Where-Object SerialNumber -eq $serial

                    if ($computer.IsLocalHost) {
                        $storedCert | Select-Object * | Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
                    }
                } else {
                    if ($PScmdlet.ShouldProcess("local", "Submitting certificate request for $computer to $CaServer\$CaName")) {
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "certreq -submit -config `"$CaServer\$CaName`" -attrib $certTemplate $certCsr $certCrt $certPfx"
                        $submit = certreq -submit -config ""$CaServer\$CaName"" -attrib $certTemplate $certCsr $certCrt $certPfx
                    }

                    if ($submit -match "ssued") {
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "certreq -accept -machine $certCrt"
                        $null = certreq -accept -machine $certCrt
                        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                        $cert.Import($certCrt, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
                        $storedCert = Get-ChildItem "Cert:\$store\$folder" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
                    } elseif ($submit) {
                        Write-Message -Level Warning -Message "Something went wrong"
                        Write-Message -Level Warning -Message "$create"
                        Write-Message -Level Warning -Message "$submit"
                        Stop-Function -Message "Failure when attempting to create the cert on $computer. Exception: $_" -ErrorRecord $_ -Target $computer -Continue
                    }

                    if ($Computer.IsLocalHost) {
                        $storedCert | Select-Object * | Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
                    }
                }
            }

            if (-not $Computer.IsLocalHost) {

                if (-not $secondaryNode) {
                    if ($PScmdlet.ShouldProcess("local", "Generating pfx and reading from disk")) {
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting PFX with password to $tempPfx"
                        $certdata = $storedCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::PFX, $SecurePassword)
                    }

                    if ($PScmdlet.ShouldProcess("local", "Removing cert from disk but keeping it in memory")) {
                        $storedCert | Remove-Item
                    }

                    if ($ClusterInstanceName) { $secondaryNode = $true }
                }

                $scriptBlock = {
                    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                    $cert.Import($args[0], $args[1], "Exportable,PersistKeySet")

                    $certstore = New-Object System.Security.Cryptography.X509Certificates.X509Store($args[3], $args[2])
                    $certstore.Open('ReadWrite')
                    $certstore.Add($cert)
                    $certstore.Close()
                    Get-ChildItem "Cert:\$($args[2])\$($args[3])" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
                }

                if ($PScmdlet.ShouldProcess("local", "Connecting to $computer to import new cert")) {
                    try {
                        $thumbprint = (Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $certdata, $SecurePassword, $Store, $Folder -ScriptBlock $scriptBlock -ErrorAction Stop).Thumbprint
                        Get-DbaComputerCertificate -ComputerName $computer -Credential $Credential -Thumbprint $thumbprint
                    } catch {
                        Stop-Function -Message "Issue importing new cert on $computer" -ErrorRecord $_ -Target $computer -Continue
                    }
                }
            }
            if ($PScmdlet.ShouldProcess("local", "Removing all files from $certDir")) {
                try {
                    Remove-Item -Force -Recurse $certDir -ErrorAction SilentlyContinue
                } catch {
                    Stop-Function "Isue removing files from $certDir" -Target $certDir -ErrorRecord $_
                }
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUoDfNHyRFV+wmiD7VXkUYJMF4
# iDagghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFPpSbki8hp+SWQYxB9FfipPXOAk9MA0GCSqGSIb3DQEBAQUABIIBAALOwgCV
# RmjuOYQ/CQEgkoS1bJEM/tq51I1+s4kpmCWWVMwHGKCp6c54KH/vVB68HcpvWS4d
# scqZxX7NciNKCDnstk2rl8TRhxG4ryirnYLE5tN0LD9sArwu/P3InQlRgyZk4D44
# QjEsdvHGDJTwW6ZYxrYXRPQwRyt1O2LfW24LfkRZ6F6n+p+XxNBvzphVptyCPV9B
# bkGbpNkfgJAeBgSZQiXdY/+vkMpG6lucv9S7LPIFPacc9f3g623GIfrQ+DUGDPc/
# DO01Z3OI0zHfD7cUx+bS4IHov4BqS1LU4haVgIUZdKVnyndMILcC0Lzw2lG2yMeT
# YE0Pd8xUD4UpPj6hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTk1NFowLwYJKoZIhvcNAQkEMSIEINW/57kdqc0rrk+KUJy5GnHK6MoS
# wDrE9tgTjH/zT0/iMA0GCSqGSIb3DQEBAQUABIIBAB39K2AGq84dM0d8UGebmaFt
# fiUwXZOBwasBGwv1PPoi1dwBZWWhLj7o7BlexW0y03meHqryTsilRr/ph78tgcaF
# x9MV4E6yQeFIJb72qrzeuDOftlh/caABOY6BTNV967H46ZdiHYc9dvjt/9Q3NEqI
# oRYyyo9bA9phrp+lJpJZM8zqFi3yRJFstcU4a/ICG/VcyMIxnSExmgCDAQE3z7Rf
# Y7zL5LhR6/BYgHsw7NNHPt0DbLpXIfTY9RhecUwH/urAN1iMQG7WEYiUhPQVriQ1
# 7byFJX476IdiKclO3Sumi3qK41A9H30U8y7IZfJWWrHE2lFv6qmN0wfn4ab+6sY=
# SIG # End signature block
