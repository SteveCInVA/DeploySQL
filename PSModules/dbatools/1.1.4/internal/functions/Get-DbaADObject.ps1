function Get-DbaADObject {
    <#
    .SYNOPSIS
    Get-DbaADObject tries to facilitate searching AD with dbatools, which ATM can't require AD cmdlets.

    .DESCRIPTION
    As working with multiple domains, forests, ldap filters, partitions, etc is quite hard to grasp, let's try to do "the right thing" here and
    facilitate everybody's work with it. It either returns the exact matched result or None if it isn't found. You can inspect the raw object
    calling GetUnderlyingObject() on the returned object.

    .PARAMETER ADObject
    Pass in both the domain and the login name in Domain\sAMAccountName format (the one everybody is accustomed to)
    You can also pass a UserPrincipalName format (with the correct IdentityType, either with Domain\UserPrincipalName or UserPrincipalName@Domain)
    Beware: the "Domain" part of the UPN *can* be different from the real domain, see "UPN suffixes" (https://msdn.microsoft.com/en-us/library/windows/desktop/aa380525(v=vs.85).aspx)
    It's always best to pass the real domain name in (see the examples)
    For any other format, please beware that the domain part must always be specified (again, for the best result, before the slash)

    .PARAMETER Type
    You *should* always know what you are asking for. Please pass in Computer,Group or User to help speeding up the search

    .PARAMETER IdentityType
    By default objects are searched using sAMAccountName format, here you can pass different representation that need to match the passed in ADObject

    .PARAMETER Credential
    Use this credential to connect to the domain and search for the needed ADObject. If not passed, uses the current process' one.

    .PARAMETER SearchAllDomains
    Search for the object in all domains connected to the current one. If you are unsure what domain the object is coming from,
    using this switch will search through all domains in your forest and also in the ones that are trusted. This is HEAVY, but it can save
    some headaches.

    .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Author: Niphlod, https://github.com/niphlod
    Tags:
    dbatools PowerShell module (https://dbatools.io)
   Copyright: (c) 2018 by dbatools, licensed under MIT
    License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
    Get-DbaADObject -ADObject "contoso\ctrlb" -Type User

    Searches in the contoso domain for a ctrlb user

    .EXAMPLE
    Get-DbaADObject -ADObject "ctrlb@contoso.com" -Type User -IdentityType UserPrincipalName

    Searches in the contoso domain for a ctrlb user using the UserPrincipalName format. Again, beware of the UPN suffixes in elaborate AD structures!

    .EXAMPLE
    Get-DbaADObject -ADObject "contoso\ctrlb@super.contoso.com" -Type User -IdentityType UserPrincipalName

    Searches in the contoso domain for a ctrlb@super.contoso.com user using the UserPrincipalName format. This kind of search is better than the previous one
    because it takes into account possible UPN suffixes

    .EXAMPLE
    Get-DbaADObject -ADObject "ctrlb@super.contoso.com" -Type User -IdentityType UserPrincipalName -SearchAllDomains

    As a last resort, searches in all the current forest for a ctrlb@super.contoso.com user using the UserPrincipalName format

    .EXAMPLE
    Get-DbaADObject -ADObject "contoso\sqlcollaborative" -Type Group

    Searches in the contoso domain for a sqlcollaborative group

    .EXAMPLE
    Get-DbaADObject -ADObject "contoso\SqlInstance2014$" -Type Group

    Searches in the contoso domain for a SqlInstance2014 computer (remember the ending $ for computer objects)

    .EXAMPLE
    Get-DbaADObject -ADObject "contoso\ctrlb" -Type User -EnableException

    Searches in the contoso domain for a ctrlb user, suppressing all error messages and throw exceptions that can be caught instead

    #>
    [CmdletBinding()]
    param (
        [string[]]$ADObject,
        [ValidateSet("User", "Group", "Computer")]
        [string]$Type,

        [ValidateSet("DistinguishedName", "Guid", "Name", "SamAccountName", "Sid", "UserPrincipalName")]
        [string]$IdentityType = "SamAccountName",

        [PSCredential]$Credential,
        [switch]$SearchAllDomains,
        [switch]$EnableException
    )
    begin {
        try {
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        } catch {
            Stop-Function -Message "Failed to load the required module $($_.Exception.Message)" -EnableException $EnableException -InnerErrorRecord $_
            return
        }
        switch ($Type) {
            "User" {
                $searchClass = [System.DirectoryServices.AccountManagement.UserPrincipal]
            }
            "Group" {
                $searchClass = [System.DirectoryServices.AccountManagement.GroupPrincipal]
            }
            "Computer" {
                $searchClass = [System.DirectoryServices.AccountManagement.ComputerPrincipal]
            }
            default {
                $searchClass = [System.DirectoryServices.AccountManagement.Principal]
            }
        }

        function Get-DbaADObjectInternal($Domain, $IdentityType, $obj, $EnableException) {
            try {
                # can we simply resolve the passed domain ? This has the benefit of raising almost instantly if the domain is not valid
                $Context = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext('Domain', $Domain)
                $null = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($Context)
                if ($Credential) {
                    $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', $Domain, $Credential.UserName, $Credential.GetNetworkCredential().Password)
                } else {
                    $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', $Domain)
                }
                $found = $searchClass::FindByIdentity($ctx, $IdentityType, $obj)
                $found
            } catch {
                Stop-Function -Message "Errors trying to connect to the domain $Domain $($_.Exception.Message)" -EnableException $EnableException -InnerErrorRecord $_ -Target $ADObj
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($ADObj in $ADObject) {
            # passing the domain as the first part before the \ wins always in defining the domain to search into
            $Splitted = $ADObj.Split("\")
            if ($Splitted.Length -ne 2) {
                # we can also take the object@domain format
                $Splitted = $ADObj.Split("@")
                if ($Splitted.Length -ne 2) {
                    Stop-Function -Message "You need to pass ADObject either DOMAIN\object or object@domain format" -Continue -EnableException $EnableException
                } else {
                    if ($IdentityType -ne 'UserPrincipalName') {
                        $obj, $Domain = $Splitted
                    } else {
                        # if searching for a UserPrincipalName format without a specific domain passed in before the slash,
                        # we can assume there are no custom UPN suffixes in place
                        $obj, $Domain = $AdObj, $Splitted[1]
                    }
                }
            } else {
                $Domain, $obj = $Splitted
            }
            if ($SearchAllDomains) {
                Write-Message -Message "Searching for $obj under all domains in $IdentityType format" -Level VeryVerbose
                # if we're lucky, we can resolve the domain right away
                try {
                    Get-DbaADObjectInternal -Domain $Domain -IdentityType $IdentityType -obj $obj -EnableException $true
                } catch {
                    # if not, let's build up all domains
                    $ForestObject = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
                    $AllDomains = $ForestObject.Domains.Name
                    foreach ($ForestDomain in $AllDomains) {
                        Write-Message -Message "Searching for $obj under domain $ForestDomain in $IdentityType format" -Level VeryVerbose
                        $found = Get-DbaADObjectInternal -Domain $ForestDomain -IdentityType $IdentityType -obj $obj
                        if ($found) {
                            $found
                            break
                        }
                    }
                    # we are very unlucky, let's search also in all trusted domains
                    $AllTrusted = ($ForestObject.GetAllTrustRelationships().TopLevelNames | Where-Object Status -eq 'Enabled').Name
                    foreach ($ForestDomain in $AllTrusted) {
                        Write-Message -Message "Searching for $obj under domain $ForestDomain in $IdentityType format" -Level VeryVerbose
                        $found = Get-DbaADObjectInternal -Domain $ForestDomain -IdentityType $IdentityType -obj $obj
                        if ($found) {
                            $found
                            break
                        }
                    }
                }
            } else {
                Write-Message -Message "Searching for $obj under domain $domain in $IdentityType format" -Level VeryVerbose
                Get-DbaADObjectInternal -Domain $Domain -IdentityType $IdentityType -obj $obj
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQURpGVi/CHdd80mpIzaAtyGWbP
# ECugghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFERMhjou9xAxRN9hzdf96SlJXhrbMA0GCSqGSIb3DQEBAQUABIIBACLqOy0J
# 9wo51uYIIt9GqQa4NUWNEbbzxIBk5zXZlpocwWahCkyhNQFBAt1ompJSEAhOUJPi
# jw+Hlsb/jdEM+e31M3ow9CMQdFRUz3z9TCpv1hM2FchzGeqVIISR+rGtIw2Sp4Ka
# ZchOtkENU5VXw/X9xlGq+B5AZEf+ZnQ116qPToXTRLlDqmHdg8YLbJf3+o38nrNG
# GWX0jkRc/boRX/EmVCDyupRmjxYKxy5++yAm1F47wEr8wxLF3VYjv7opQzKcqSVx
# VdshHNDaSd/gCw4x5S4PNvvTxxa/soL0z4V2rwc+AqrV5rL4Y0aoxdAMS07k8ZU7
# 1HGgHeFdvVsR+ymhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAzMFowLwYJKoZIhvcNAQkEMSIEIJSbJGgAiIJL5jrnI+OTYwUab1nU
# ZnzztcaOvDVeO3GSMA0GCSqGSIb3DQEBAQUABIIBAHgVkZphqcXvV6xRqsZW4TXN
# AHu+5ZFImIBW9JY2in9ZMA8OIJfz5zzZXJiPNILQe4M0bdUbiWCLZ77UvtA/MzPX
# BcHx8UM1H9nbH3b9Ymcm2xCytLhp3SyL1jBK8KBVUM7vbKwuN/NPbAChQsfcsFzD
# Prs2qer7tnArbr/FD4J+xjIYs9VXLjYwScJgV4slDTMA/Dao7UUvG+VMY+4Ijt3x
# +75OSgd2y2K1yNd04kYQMYhuwupJVAX6b+4ZoV3HsDEEsQJ0zdiInhzADRANGK83
# KrkzFcpZv+A5IZ+y95g5Bhjg6d8dXBpgJpHgo5XWf8sD9JN29fVdTR2EofRjrYs=
# SIG # End signature block
