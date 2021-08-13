function Get-SQLInstanceComponent {
    <#
    .SYNOPSIS
        Retrieves SQL server information from a local or remote servers.
    .DESCRIPTION
        Retrieves SQL server information from a local or remote servers. Pulls all instances from a SQL server and
        detects if in a cluster or not.
    .PARAMETER ComputerName
        Local or remote systems to query for SQL information.
    .NOTES
        Tags: Install, Patching, SP, CU, Instance
        Author: Kirill Kravtsov (@nvarscar) https://nvarscar.wordpress.com/

        Based on https://github.com/adbertram/PSSqlUpdater
        The majority of this function was created by Boe Prox.
    .EXAMPLE
        Get-SQLInstanceComponent -ComputerName SQL01 -Component SSDS
        ComputerName  : BDT005-BT-SQL
        InstanceType  : Database Engine
        InstanceName  : MSSQLSERVER
        InstanceID    : MSSQL11.MSSQLSERVER
        Edition       : Enterprise Edition
        Version       : 11.1.3000.0
        Caption       : SQL Server 2012
        IsCluster     : False
        IsClusterNode : False
        ClusterName   :
        ClusterNodes  : {}
        FullName      : BDT005-BT-SQL
        Description
        -----------
        Retrieves the SQL instance information from SQL01 for component type SSDS (Database Engine).
    .EXAMPLE
        Get-SQLInstanceComponent -ComputerName SQL01
        ComputerName  : BDT005-BT-SQL
        InstanceType  : Analysis Services
        InstanceName  : MSSQLSERVER
        InstanceID    : MSAS11.MSSQLSERVER
        Edition       : Enterprise Edition
        Version       : 11.1.3000.0
        Caption       : SQL Server 2012
        IsCluster     : False
        IsClusterNode : False
        ClusterName   :
        ClusterNodes  : {}
        FullName      : BDT005-BT-SQL
        ComputerName  : BDT005-BT-SQL
        InstanceType  : Reporting Services
        InstanceName  : MSSQLSERVER
        InstanceID    : MSRS11.MSSQLSERVER
        Edition       : Enterprise Edition
        Version       : 11.1.3000.0
        Caption       : SQL Server 2012
        IsCluster     : False
        IsClusterNode : False
        ClusterName   :
        ClusterNodes  : {}
        FullName      : BDT005-BT-SQL
        Description
        -----------
        Retrieves the SQL instance information from SQL01 for all component types (SSAS, SSDS, SSRS).
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Computer', 'DNSHostName', 'IPAddress')]
        [DbaInstanceParameter[]]$ComputerName = $Env:COMPUTERNAME,
        [ValidateSet('SSDS', 'SSAS', 'SSRS')]
        [string[]]$Component = @('SSDS', 'SSAS', 'SSRS'),
        [pscredential]$Credential
    )

    begin {

        $regScript = {
            Param (
                $ComponentObject
            )
            $Component = $ComponentObject.Component
            $componentNameMap = @(
                [pscustomobject]@{
                    ComponentName = 'SSAS';
                    DisplayName   = 'Analysis Services';
                    RegKeyName    = "OLAP";
                },
                [pscustomobject]@{
                    ComponentName = 'SSDS';
                    DisplayName   = 'Database Engine';
                    RegKeyName    = 'SQL';
                },
                [pscustomobject]@{
                    ComponentName = 'SSRS';
                    DisplayName   = 'Reporting Services';
                    RegKeyName    = 'RS';
                }
            );

            function Get-SQLInstanceDetail {
                <#
                    .SYNOPSIS
                        The majority of this function was created by Boe Prox.
                #>
                param
                (
                    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
                    [string[]]$Instance,

                    [Parameter(Mandatory)]
                    [ValidateNotNullOrEmpty()]
                    [Microsoft.Win32.RegistryKey]$RegKey,

                    [Parameter(Mandatory)]
                    [ValidateNotNullOrEmpty()]
                    [Microsoft.Win32.RegistryKey]$reg,

                    [Parameter(Mandatory)]
                    [ValidateNotNullOrEmpty()]
                    [string]$RegPath
                )
                process {
                    #region Process each instance
                    foreach ($sqlInstance in $Instance) {
                        $log = @()
                        $nodes = New-Object System.Collections.ArrayList;
                        $clusterName = $null;
                        $isCluster = $false;
                        $instanceValue = $regKey.GetValue($sqlInstance);
                        $log += "Working with $regPath\$instanceValue on $computer"
                        $instanceReg = $reg.OpenSubKey("$regPath\\$instanceValue");
                        if ($instanceReg.GetSubKeyNames() -contains 'Cluster') {
                            $isCluster = $true;
                            $instanceRegCluster = $instanceReg.OpenSubKey('Cluster');
                            $clusterName = $instanceRegCluster.GetValue('ClusterName');
                            #Write-Message -Level Verbose -Message "Getting cluster node names";
                            $clusterReg = $reg.OpenSubKey("Cluster\\Nodes");
                            $clusterNodes = $clusterReg.GetSubKeyNames();
                            if ($clusterNodes) {
                                foreach ($clusterNode in $clusterNodes) {
                                    $null = $nodes.Add($clusterReg.OpenSubKey($clusterNode).GetValue("NodeName").ToUpper());
                                }
                            }
                        }

                        #region Gather additional information about SQL instance
                        $instanceRegSetup = $instanceReg.OpenSubKey("Setup")

                        #region Get SQL instance directory
                        try {
                            $instanceDir = $instanceRegSetup.GetValue("SqlProgramDir");
                            if (([System.IO.Path]::GetPathRoot($instanceDir) -ne $instanceDir) -and $instanceDir.EndsWith("\")) {
                                $instanceDir = $instanceDir.Substring(0, $instanceDir.Length - 1);
                            }
                        } catch {
                            $instanceDir = $null;
                        }
                        #endregion Get SQL instance directory

                        #region Get SQL edition
                        try {
                            $edition = $instanceRegSetup.GetValue("Edition");
                        } catch {
                            $edition = $null;
                        }
                        #endregion Get SQL edition

                        #region Get resume value
                        try {
                            $resume = [bool][int]$instanceRegSetup.GetValue("Resume");
                        } catch {
                            $resume = $false;
                        }
                        #endregion Get resume value

                        #region Get SQL version
                        $version = $null
                        try {
                            $versionHash = @{
                                '11' = 'SQLServer2012'
                                '12' = 'SQLServer2014'
                                '13' = 'SQLServer2016'
                                '14' = 'SQL2017'
                                '15' = 'SQL2019'
                            }
                            $version = $instanceRegSetup.GetValue("Version");
                            $log += "Found version $version"
                            if ($patchVersion = $instanceRegSetup.GetValue("PatchLevel")) {
                                $log += "Using patch version $patchVersion over $version"
                                $version = $patchVersion
                            }
                            # if patch version is not available - use global reg node to extract the latest patch
                            $majorVersion = $version.Split('.')[0]
                            if (!$patchVersion -and $majorVersion -and $versionHash[$majorVersion]) {
                                $verKey = $reg.OpenSubKey("SOFTWARE\\Microsoft\\Microsoft SQL Server\\$($majorVersion)0\\$($versionHash[$majorVersion])\\CurrentVersion")
                                $version = $verKey.GetValue('Version')
                                $log += "New version from the CurrentVersion key: $version"
                            }
                        } catch {
                            $log += "Failed to read one of the reg keys, found version $version so far"
                        }
                        #endregion Get SQL version

                        #region Get exe version
                        try {
                            # attempt to recover a real version of a sqlservr.exe by getting file properties from a remote machine
                            # not sure how to support SSRS/SSAS, as SSDS is the only one that has binary path in the Setup node
                            if ($binRoot = $instanceRegSetup.GetValue("SQLBinRoot")) {
                                $fileVersion = (Get-Item -Path (Join-Path $binRoot "sqlservr.exe") -ErrorAction Stop).VersionInfo.ProductVersion
                                if ($fileVersion) {
                                    $version = $fileVersion
                                    $log += "New version from the binary file: $version"
                                }
                            }
                        } catch {
                            $log += "Failed to get exe version, leaving $version as is"
                        }
                        #endregion Get exe version

                        #endregion Gather additional information about SQL instance

                        #region Generate return object
                        [pscustomobject]@{
                            ComputerName  = $computer.ToUpper();
                            InstanceName  = $sqlInstance;
                            InstanceID    = $instanceValue;
                            InstanceDir   = $instanceDir;
                            Edition       = $edition;
                            Version       = $version;
                            Caption       = {
                                switch -regex ($version) {
                                    "^11" { "SQL Server 2012"; break }
                                    "^10\.5" { "SQL Server 2008 R2"; break }
                                    "^10" { "SQL Server 2008"; break }
                                    "^9" { "SQL Server 2005"; break }
                                    "^8" { "SQL Server 2000"; break }
                                    default { "Unknown"; }
                                }
                            }.InvokeReturnAsIs();
                            IsCluster     = $isCluster;
                            IsClusterNode = ($nodes -contains $computer);
                            ClusterName   = $clusterName;
                            ClusterNodes  = ($nodes -ne $computer);
                            FullName      = {
                                if ($sqlInstance -eq "MSSQLSERVER") {
                                    $computer.ToUpper();
                                } else {
                                    "$($computer.ToUpper())\$($sqlInstance)";
                                }
                            }.InvokeReturnAsIs();
                            Log           = $log
                            Resume        = $resume
                        }
                        #endregion Generate return object
                    }
                    #endregion Process each instance
                }
            }
            $reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Default')
            $baseKeys = "SOFTWARE\\Microsoft\\Microsoft SQL Server", "SOFTWARE\\Wow6432Node\\Microsoft\\Microsoft SQL Server";
            if ($reg.OpenSubKey($baseKeys[0])) {
                $regPath = $baseKeys[0];
            } elseif ($reg.OpenSubKey($baseKeys[1])) {
                $regPath = $baseKeys[1];
            } else {
                throw "Failed to find any regkeys on $env:computername"
            }

            $computer = $Env:COMPUTERNAME

            $regKey = $reg.OpenSubKey("$regPath");
            if ($regKey.GetSubKeyNames() -contains "Instance Names") {
                foreach ($componentName in $Component) {
                    $componentRegKeyName = $componentNameMap |
                        Where-Object { $_.ComponentName -eq $componentName } |
                        Select-Object -ExpandProperty RegKeyName;
                    $regKey = $reg.OpenSubKey("$regPath\\Instance Names\\{0}" -f $componentRegKeyName);
                    if ($regKey) {
                        foreach ($regValueName in $regKey.GetValueNames()) {
                            if ($componentRegKeyName -eq 'RS' -and $regValueName -eq 'PBIRS') { continue } #filtering out Power BI - not supported
                            if ($componentRegKeyName -eq 'RS' -and $regValueName -eq 'SSRS') { continue }  #filtering out SSRS2017+ - not supported
                            $result = Get-SQLInstanceDetail -RegPath $regPath -Reg $reg -RegKey $regKey -Instance $regValueName;
                            $result | Add-Member -Type NoteProperty -Name InstanceType -Value ($componentNameMap | Where-Object { $_.ComponentName -eq $componentName }).DisplayName -PassThru
                        }
                    }
                }
            } elseif ($regKey.GetValueNames() -contains 'InstalledInstances') {
                $isCluster = $false;
                $regKey.GetValue('InstalledInstances') | ForEach-Object {
                    Get-SQLInstanceDetail -RegPath $regPath -Reg $reg -RegKey $regKey -Instance $_
                };
            } else {
                throw "Failed to find any instance names on $env:computername"
            }
        }
    }
    process {
        foreach ($computer in $ComputerName) {
            $arguments = @{ Component = $Component }
            $results = Invoke-Command2 -ComputerName $computer -ScriptBlock $regScript -Credential $Credential -ErrorAction Stop -Raw -ArgumentList $arguments -RequiredPSVersion 3.0

            # Log is stored in the log property, pile it all into the debug log
            foreach ($logEntry in $results.Log) {
                Write-Message -Level Debug -Message $logEntry
            }
            foreach ($result in $results) {
                # If version is unknown that component should be excluded, otherwise it would fail on conversion. We have no use for versionless components anyways.
                if (-Not $result.Version) {
                    Write-Message -Level Warning -Message "Component $($result.InstanceName) on $($result.ComputerName) has an unknown version and was ommitted from the instance list"
                    continue
                }
                # Replace first decimal of the minor build with a 0, since we're using build numbers here
                # Refer to https://sqlserverbuilds.blogspot.com/
                Write-Message -Level Debug -Message "Converting version $($result.Version) to [version]"
                $newVersion = New-Object -TypeName System.Version -ArgumentList ([string]$result.Version)
                $newVersion = New-Object -TypeName System.Version -ArgumentList ($newVersion.Major , ($newVersion.Minor - $newVersion.Minor % 10), $newVersion.Build)
                Write-Message -Level Debug -Message "Converted version $($result.Version) to $newVersion"
                # Find a proper build reference and replace Version property
                $result.Version = Get-DbaBuild -Build $newVersion -EnableException
                $result | Select-Object -ExcludeProperty Log
            }
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUoA05ugsV39okM+SwS1im8Ei+
# gXugghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFHPRBVU0Y8vziVWbHaoX98I33g5AMA0GCSqGSIb3DQEBAQUABIIBAImCt46W
# EJWFZ1OZTgl81f9ZpvNGPiEzFslfydHBhCkHt01DcesOFTsBY1OsU1SywSMiGZ4a
# Gp0v78slUA7mCb1tlCVYo40l+mgeGE3YnNwCX6VZEObB20AANgsvXGaItx1Orhjk
# +l2NvXVbeu74QvbzTDP69wRR22iQZbL+9sFYF0hsGoBEAdT97oCBM38/LQ7nyzvc
# XXh2ttgVbCbuEpp7Siqfo6M1ic/QZNnlKJK4TCvd+HwhewRzS9LeUkd8qFNUMgCG
# YW7dlbbCLTuHTYjT/UarlVnXyzoXT4rHh+c/wfRNz82BUFNVU9pC1LImABV3N2zS
# QLEFk0SG9uleyzihggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDgxMTA4MjYyMVowLwYJKoZIhvcNAQkEMSIEIB9Z+EpD8DV0ZXgjDwHSwmh+HpQ/
# yyOgviyAmlTISemAMA0GCSqGSIb3DQEBAQUABIIBALu1VNG5Yk8USEpDk+etttf0
# 6Ojppjb+75Fxrz3WgkYpKm4wbFWvVrpeIhURBfcy1/M2fkKakJL9lY0odh1z7zOZ
# 5TUy7TcKsF4YWv6BLjQf4aBCycOoeSZwn2L5hqOkkfkcn7BnImkmAoLdtZBBj92F
# Q72QvL+bIvUK5H66ofLBu+Hjw/L4Zoc2ogAdRQM++oQyTIHEKQAdVqpZmVKLvNIL
# grfwhgYJomTzGcdRbTpbmQcxydjygroZHLcKnuNv/KwNZo90HnpSK7WicKmHsEIM
# OMrWUJgDc6e8UWZGLFR8AqI8ldSL2/7lqTZqmVIZkcb7YHPJF70S32v6N/rq1N0=
# SIG # End signature block
