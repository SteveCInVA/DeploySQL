function Get-DbaBuild {
    <#
    .SYNOPSIS
        Returns SQL Server Build infos on a SQL instance

    .DESCRIPTION
        Returns info about the specific build of a SQL instance, including the SP, the CU and the reference KB, wherever possible.
        It also includes End Of Support dates as specified on Microsoft Life Cycle Policy

    .PARAMETER Build
        Instead of connecting to a real instance, pass a string identifying the build to get the info back.

    .PARAMETER Kb
        Get a KB information based on its number. Supported format: KBXXXXXX, or simply XXXXXX.

    .PARAMETER MajorVersion
        Get a KB information based on SQL Server version. Can be refined further by -ServicePack and -CumulativeUpdate parameters.
        Examples: SQL2008 | 2008R2 | 2016

    .PARAMETER ServicePack
        Get a KB information based on SQL Server Service Pack version. Can be refined further by -CumulativeUpdate parameter.
        Examples: SP0 | 2 | RTM

    .PARAMETER CumulativeUpdate
        Get a KB information based on SQL Server Cumulative Update version.
         Examples: CU0 | CU13 | CU0

    .PARAMETER SqlInstance
        Target any number of instances, in order to return their build state.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Update
        Adding this switch will look online for the most up to date reference, optionally replacing the local one.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SqlBuild
        Author: Simone Bizzotto (@niphold) | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaBuild

    .EXAMPLE
        PS C:\> Get-DbaBuild -Build "12.00.4502"

        Returns information about a build identified by  "12.00.4502" (which is SQL 2014 with SP1 and CU11)

    .EXAMPLE
        PS C:\> Get-DbaBuild -Build "12.00.4502" -Update

        Returns information about a build trying to fetch the most up to date index online. When the online version is newer, the local one gets overwritten

    .EXAMPLE
        PS C:\> Get-DbaBuild -Build "12.0.4502","10.50.4260"

        Returns information builds identified by these versions strings

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a | Get-DbaBuild

        Integrate with other cmdlets to have builds checked for all your registered servers on sqlserver2014a

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(DefaultParameterSetName = 'Build')]
    param (
        [version[]]
        $Build,

        [string[]]
        $Kb,

        [ValidateNotNullOrEmpty()]
        [string]
        $MajorVersion,

        [ValidateNotNullOrEmpty()]
        [string]
        [Alias('SP')]
        $ServicePack = 'RTM',

        [string]
        [Alias('CU')]
        $CumulativeUpdate,

        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]
        $SqlInstance,

        [PsCredential]
        $SqlCredential,

        [switch]
        $Update,

        [switch]$EnableException
    )

    begin {

        #region verifying parameters
        $isPipelineSqlInstance = $PSCmdlet.MyInvocation.ExpectingInput
        $ComplianceSpec = @()
        $ComplianceSpecExclusiveParams = @('Build', 'Kb', @( 'MajorVersion', 'ServicePack', 'CumulativeUpdate'), 'SqlInstance')
        foreach ($exclParamGroup in $ComplianceSpecExclusiveParams) {
            foreach ($exclParam in $exclParamGroup) {
                if ($exclParam -eq 'SqlInstance') {
                    if ($isPipelineSqlInstance -or (Test-Bound -ParameterName 'SqlInstance')) {
                        $ComplianceSpec += $exclParam
                    }
                } else {
                    if (Test-Bound -ParameterName $exclParam) {
                        $ComplianceSpec += $exclParam
                        break
                    }
                }
            }
        }
        if ($ComplianceSpec.Length -eq 0 -and (Test-Bound -Not -ParameterName 'Update') -and (-not($isPipelineSqlInstance))) {
            Stop-Function -Category InvalidArgument -Message "You need to choose at least one parameter."
            return
        }
        if ($ComplianceSpec.Length -gt 1) {
            Stop-Function -Category InvalidArgument -Message "$($ComplianceSpec -join ', ') are mutually exclusive. Please choose one or the other. Quitting."
            return
        }
        if (((Test-Bound -ParameterName 'ServicePack') -or (Test-Bound -ParameterName 'CumulativeUpdate')) -and (Test-Bound -Not -ParameterName 'MajorVersion')) {
            Stop-Function -Category InvalidArgument -Message "-MajorVersion is required when specifying SP or CU."
            return
        }
        if ($MajorVersion) {
            if ($MajorVersion -match '^(SQL)?(\d{4}(R2)?)$') {
                $MajorVersion = $Matches[2]
            } else {
                Stop-Function -Message "Incorrect SQL Server version format: use SQL2XXX or just 2XXXX - SQL2012, SQL2008R2"
                return
            }
            if (!$ServicePack) {
                $ServicePack = 'RTM'
            }
            if ($ServicePack -match '^(SP)?\s*(\d+)$') {
                if ($Matches[2] -eq '0') {
                    $ServicePack = 'RTM'
                } else {
                    $ServicePack = 'SP' + $Matches[2]
                }
            } elseif ($ServicePack -notmatch '^RTM$') {
                Stop-Function -Message "Incorrect SQL Server service pack format: use SPX, X or RTM, where X is a service pack number"
                return
            }
            if ($CumulativeUpdate) {
                if ($CumulativeUpdate -match '^(CU)?\s*(\d+)$') {
                    if ($Matches[2] -eq '0') {
                        $CumulativeUpdate = ''
                    } else {
                        $CumulativeUpdate = 'CU' + $Matches[2]
                    }
                } else {
                    Stop-Function -Message "Incorrect SQL Server cumulative update format: use CUX or X, where X is a cumulative update number"
                    return
                }
            }
        }
        #endregion verifying parameters

        #region Helper functions
        function Get-DbaBuildReferenceIndex {
            [CmdletBinding()]
            param (
                [string]
                $Moduledirectory,

                [bool]
                $Update,

                [bool]
                $EnableException
            )

            $orig_idxfile = Resolve-Path "$Moduledirectory\bin\dbatools-buildref-index.json"
            $DbatoolsData = Get-DbatoolsConfigValue -Name 'Path.DbatoolsData'
            $writable_idxfile = Join-Path $DbatoolsData "dbatools-buildref-index.json"

            if (-not (Test-Path $orig_idxfile)) {
                Write-Message -Level Warning -Message "Unable to read local SQL build reference file. Please check your module integrity or reinstall dbatools."
            }

            if ((-not (Test-Path $orig_idxfile)) -and (-not (Test-Path $writable_idxfile))) {
                throw "Build reference file not found, please check module health."
            }

            # If no writable copy exists, create one and return the module original
            if (-not (Test-Path $writable_idxfile)) {
                Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
                $result = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
            }

            # Else, if both exist, update the writeable if necessary and return the current version
            elseif (Test-Path $orig_idxfile) {
                $module_content = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
                $data_content = Get-Content $writable_idxfile -Raw | ConvertFrom-Json

                $module_time = Get-Date $module_content.LastUpdated
                $data_time = Get-Date $data_content.LastUpdated

                if ($module_time -gt $data_time) {
                    Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
                    $result = $module_content
                } else {
                    $result = $data_content
                }
                # If Update is passed, try to fetch from online resource and store into the writeable
                if ($Update) {
                    Update-DbaBuildReference -EnableException -ErrorAction Stop
                }
            }

            # Else if the module version of the file no longer exists, but the writable version exists, return the writable version
            else {
                $result = Get-Content $writable_idxfile -Raw | ConvertFrom-Json
            }

            $LastUpdated = Get-Date -Date $result.LastUpdated
            if ($LastUpdated -lt (Get-Date).AddDays(-45)) {
                Write-Message -Level Warning -Message "Index is stale, last update on: $(Get-Date -Date $LastUpdated -Format s), try the -Update parameter to fetch the most up to date index"
            }

            $result.Data | Select-Object @{ Name = "VersionObject"; Expression = { [version]$_.Version } }, *
        }


        function Resolve-DbaBuild {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            [CmdletBinding()]
            [OutputType([System.Collections.Hashtable])]
            param (
                [Parameter(Mandatory, ParameterSetName = 'Build')]
                [version]
                $Build,

                [Parameter(Mandatory, ParameterSetName = 'KB')]
                [string]
                $Kb,

                [Parameter(Mandatory, ParameterSetName = 'HFLevel')]
                [string]
                $MajorVersion,

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('SP')]
                $ServicePack = 'RTM',

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('CU')]
                $CumulativeUpdate,

                $Data,

                [bool]
                $EnableException
            )

            if ($Build) {
                Write-Message -Level Verbose -Message "Looking for $Build"

                $IdxVersion = $Data | Where-Object Version -like "$($Build.Major).$($Build.Minor).*"
            } elseif ($Kb) {
                Write-Message -Level Verbose -Message "Looking for KB $Kb"
                if ($Kb -match '^(KB)?(\d+)$') {
                    $currentKb = $Matches[2]
                    $kbVersion = $Data | Where-Object KBList -contains $currentKb
                    $IdxVersion = $Data | Where-Object Version -like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
                } else {
                    Stop-Function -Message "Wrong KB name $kb"
                    return
                }
            } elseif ($MajorVersion) {
                Write-Message -Level Verbose -Message "Looking for SQL $MajorVersion SP $ServicePack CU $CumulativeUpdate"
                $kbVersion = $Data | Where-Object Name -eq $MajorVersion
                $IdxVersion = $Data | Where-Object Version -like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
            }

            $Detected = @{ }
            $Detected.MatchType = 'Approximate'
            $idxCount = $IdxVersion | Measure-Object | Select-Object -ExpandProperty Count
            Write-Message -Level Verbose -Message "We have $idxCount builds in store for this Release"
            If ($idxCount -eq 0) {
                Write-Message -Level Warning -Message "No info in store for this Release"
                $Detected.Warning = "No info in store for this Release"
            } else {
                $LastVer = $IdxVersion[0]
            }
            foreach ($el in $IdxVersion) {
                if ($null -ne $el.Name) {
                    $Detected.Name = $el.Name
                }
                if ($Build -and $el.VersionObject -gt $Build) {
                    $Detected.MatchType = 'Approximate'
                    $Detected.Warning = "$Build not found, closest build we have is $($LastVer.Version)"
                    break
                }
                $LastVer = $el
                $Detected.BuildLevel = $el.VersionObject
                if ($null -ne $el.SP) {
                    $Detected.SP = $el.SP
                    $Detected.CU = $null
                }
                if ($null -ne $el.CU) {
                    $Detected.CU = $el.CU
                }
                if ($null -ne $el.SupportedUntil) {
                    $Detected.SupportedUntil = (Get-Date -date $el.SupportedUntil)
                }
                $Detected.Build = $el.Version
                $Detected.KB = $el.KBList
                if (($Build -and $el.Version -eq $Build) -or ($Kb -and $el.KBList -eq $currentKb)) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                } elseif ($MajorVersion -and $Detected.SP -contains $ServicePack -and (!$CumulativeUpdate -or ($el.CU -and $el.CU -eq $CumulativeUpdate))) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                }
            }
            return $Detected
        }
        #endregion Helper functions

        $moduledirectory = $script:PSModuleRoot

        try {
            $IdxRef = Get-DbaBuildReferenceIndex -Moduledirectory $moduledirectory -Update $Update -EnableException $EnableException
        } catch {
            Stop-Function -Message "Error loading SQL build reference" -ErrorRecord $_
            return
        }
    }
    process {

        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            #region Ensure the connection is established
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $null = $server.Version.ToString()
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            #endregion Ensure the connection is established

            $Detected = Resolve-DbaBuild -Build $server.Version -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $server.DomainInstanceName
                Build          = $server.Version
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                BuildLevel     = $Detected.BuildLevel
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            }
        }

        foreach ($buildstr in $Build) {
            $Detected = Resolve-DbaBuild -Build $buildstr -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $null
                Build          = $buildstr
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                BuildLevel     = $Detected.BuildLevel
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            } | Select-DefaultView -ExcludeProperty SqlInstance
        }

        foreach ($kbItem in $Kb) {
            $Detected = Resolve-DbaBuild -Kb $kbItem -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $null
                Build          = $Detected.Build
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                BuildLevel     = $Detected.BuildLevel
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            } | Select-DefaultView -ExcludeProperty SqlInstance
        }

        if ($MajorVersion) {
            $Detected = Resolve-DbaBuild -MajorVersion $MajorVersion -ServicePack $ServicePack -CumulativeUpdate $CumulativeUpdate -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $null
                Build          = $Detected.Build
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                BuildLevel     = $Detected.BuildLevel
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            } | Select-DefaultView -ExcludeProperty SqlInstance
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUMlUgEamX1qtTmbfwpvTmmjMd
# nrigghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFHHgn9hyCR4GKqriUutWxq0uZtmHMA0GCSqGSIb3DQEBAQUABIIBAAWhSYC4
# 7nSbotxpgVVLBz6RpHj5utiaFtWE7zTtaQk2guumN6pswk4BtFfShzbZ9Aw7HKT9
# WCl+IEcDE5CzY3ygG2SGc2LqIhIOdbm3RoJNh8LlTR6D3kLyf4qLKNIEPqUk05XV
# ZyZOW/hG3gfca5olpJkP8di0e81nAQKmbH4tideHnRFSd0S/6n1T3HkBGhFVSMu2
# s2RNP02YQM/YEEt0Sm+jIIy+LbZft7kneXY0cw+s3fGSVD37ZsEhb+ScTXZPmzhA
# ZcvL9l81RF6gtdwYbmJ43Nu+zIK2BskibkEHd2uRjXJUBxhLZ2bFWItk+R8UFw7P
# OO+bPKF21XVbXUWhggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA3NTkyNlowLwYJKoZIhvcNAQkEMSIEIOaflbX7tIjV+y+UAqKkTwBHsOab
# fVscTJcwsXubpUx9MA0GCSqGSIb3DQEBAQUABIIBAK3Zqg4bnxd++MEIo+GgqKby
# jDv8rUsoZHrM+OMgRUwRs8RWIh/YBlwG2qywR+4j4A5f05sCZroJrdJg7V1WgE9m
# lTJE2U2XgZDCdMYrc9dcRH9wpNBI1W/UzDw8QHv4s9s+7tS1NI+r3ugtMw+WTtVh
# mooNPL6kzMDSqllKcPE7P69p6hkRE3hJ9IezczD7ck6W5NTNeQIGHmJRsk16s3vM
# 3MGlzeppnW99U4jIpqfDjDkp1dJoPcak9IWJuFmjeHuQ032DB8sk8p2TEKrZuvHq
# fKImJzwbo9LW3YOhii1GxB3cEhMVVtT7xqaHwPk2McQWzRZMpkAKX8ataNMGwW4=
# SIG # End signature block
