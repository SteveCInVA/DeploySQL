
function Stop-Function {
    <#
    .SYNOPSIS
        Function that interrupts a function.

    .DESCRIPTION
        Function that interrupts a function.

        This function is a utility function used by other functions to reduce error catching overhead.
        It is designed to allow gracefully terminating a function with a warning by default and also allow opt-in into terminating errors.
        It also allows simple integration into loops.

        Note:
        When calling this function with the intent to terminate the calling function in non-EnableException mode too, you need to add a return below the call.

    .PARAMETER Message
        A message to pass along, explaining just what the error was.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Category
        What category does this termination belong to?
        Mandatory so long as no inner exception is passed.

    .PARAMETER ErrorRecord
        An option to include an inner exception in the error record (and in the exception thrown, if one is thrown).
        Use this, whenever you call Stop-Function in a catch block.

        Note:
        Pass the full error record, not just the exception.

    .PARAMETER Tag
        Tags to add to the message written.
        This allows filtering and grouping by category of message, targeting specific messages.

    .PARAMETER FunctionName
        The name of the function to crash.
        This parameter is very optional, since it automatically selects the name of the calling function.
        The function name is used as part of the errorid.
        That in turn allows easily figuring out, which exception belonged to which function when checking out the $error variable.

    .PARAMETER File
        The file in which Stop-Function was called.
        Will be automatically set, but can be overridden when necessary.

    .PARAMETER Line
        The line on which Stop-Function was called.
        Will be automatically set, but can be overridden when necessary.

    .PARAMETER Target
        The object that was processed when the error was thrown.
        For example, if you were trying to process a Database Server object when the processing failed, add the object here.
        This object will be in the error record (which will be written, even in non-EnableException mode, just won't show it).
        If you specify such an object, it becomes simple to actually figure out, just where things failed at.

    .PARAMETER Exception
        Allows specifying an inner exception as input object. This will be passed on to the logging and used for messages.
        When specifying both ErrorRecord AND Exception, Exception wins, but ErrorRecord is still used for record metadata.

    .PARAMETER OverrideExceptionMessage
        Disables automatic appending of exception messages.
        Use in cases where you already have a speaking message interpretation and do not need the original message.

    .PARAMETER Continue
        This will cause the function to call continue while not running silently.
        Useful when mass-processing items where an error shouldn't break the loop.

    .PARAMETER SilentlyContinue
        This will cause the function to call continue while running silently.
        Useful when mass-processing items where an error shouldn't break the loop.

    .PARAMETER ContinueLabel
        When specifying a label in combination with "-Continue" or "-SilentlyContinue", this function will call continue with this specified label.
        Helpful when trying to continue on an upper level named loop.

    .EXAMPLE
        Stop-Function -Message "Foo failed bar." -EnableException $EnableException -ErrorRecord $_
        return

        Depending on whether $EnableException is true or false it will:
        - Throw a bloody terminating error. Game over.
        - Write a nice warning about how Foo failed bar, then terminate the function. The return on the next line will then end the calling function.

    .EXAMPLE
        Stop-Function -Message "Foo failed bar." -EnableException $EnableException -Category InvalidOperation -Target $foo -Continue

        Depending on whether $silent is true or false it will:
        - Throw a bloody terminating error. Game over.
        - Write a nice warning about how Foo failed bar, then call continue to process the next item in the loop.
        In both cases, the error record added to $error will have the content of $foo added, the better to figure out what went wrong.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(DefaultParameterSetName = 'Plain')]
    param (
        [Parameter(Mandatory)]
        [string]
        $Message,

        [bool]
        $EnableException = $EnableException,

        [Parameter(ParameterSetName = 'Plain')]
        [Parameter(ParameterSetName = 'Exception')]
        [System.Management.Automation.ErrorCategory]
        $Category = ([System.Management.Automation.ErrorCategory]::NotSpecified),

        [Parameter(ParameterSetName = 'Exception')]
        [Alias('InnerErrorRecord')]
        [System.Management.Automation.ErrorRecord[]]
        $ErrorRecord,

        [string[]]
        $Tag,

        [string]
        $FunctionName = ((Get-PSCallStack)[0].Command),

        [string]
        $File,

        [int]
        $Line,

        [object]
        $Target,

        [System.Exception]
        $Exception,

        [switch]
        $OverrideExceptionMessage,

        [switch]
        $Continue,

        [switch]
        $SilentlyContinue,

        [string]
        $ContinueLabel
    )

    #region Initialize information on the calling command
    $callStack = (Get-PSCallStack)[1]
    $ModuleName = "dbatools"
    if (-not $FunctionName) {
        $FunctionName = $callStack.Command
    }
    if (-not $File) {
        $File = $callStack.Position.File
    }
    if (-not $Line) {
        $Line = $callStack.Position.StartLineNumber
    }

    if ($Target -and $FunctionName -match "Connect-.*Instance") {
        $instance = $Target
        $isconnstring = ([DbaInstanceParameter]$instance).IsConnectionString
        if ($isconnstring) {
            $instance = Hide-ConnectionString $instance
        }
    }
    #endregion Initialize information on the calling command

    #region Apply Transforms
    #region Target Transform
    if ($null -ne $Target) {
        $Target = Convert-DbaMessageTarget -Target $Target -FunctionName $FunctionName -ModuleName $ModuleName
    }
    #endregion Target Transform

    #region Exception Transforms
    if ($Exception) {
        $Exception = Convert-DbaMessageException -Exception $Exception -FunctionName $FunctionName -ModuleName $ModuleName
    } elseif ($ErrorRecord) {
        $int = 0
        while ($int -lt $ErrorRecord.Length) {
            $tempException = Convert-DbaMessageException -Exception $ErrorRecord[$int].Exception -FunctionName $FunctionName -ModuleName $ModuleName
            if ($tempException -ne $ErrorRecord[$int].Exception) {
                $ErrorRecord[$int] = New-Object System.Management.Automation.ErrorRecord($tempException, $ErrorRecord[$int].FullyQualifiedErrorId, $ErrorRecord[$int].CategoryInfo.Category, $ErrorRecord[$int].TargetObject)
            }
            $int++
        }
    }
    #endregion Exception Transforms
    #endregion Apply Transforms

    #region Message Handling
    $records = @()

    if ($ErrorRecord -or $Exception) {
        if ($ErrorRecord) {
            foreach ($record in $ErrorRecord) {
                $msg = Get-ErrorMessage -Record $record
                if ($instance) {
                    $msg = "Error connecting to [$instance]: $msg"
                }
                if (-not $Exception) {
                    $newException = New-Object System.Exception($msg, $record.Exception)
                } else {
                    $newException = $Exception
                }

                if ($record.CategoryInfo.Category) {
                    $Category = $record.CategoryInfo.Category
                }

                $records += New-Object System.Management.Automation.ErrorRecord($newException, "$($ModuleName)_$FunctionName", $Category, $Target)
            }
        } else {
            $records += New-Object System.Management.Automation.ErrorRecord($Exception, "$($ModuleName)_$FunctionName", $Category, $Target)
        }

        # Manage Debugging
        if ($EnableException) {
            Write-Message -Level Warning -Message $Message -EnableException $EnableException -FunctionName $FunctionName -Target $Target -ErrorRecord $records -Tag $Tag -ModuleName $ModuleName -OverrideExceptionMessage:$OverrideExceptionMessage -File $File -Line $Line 3>$null
        } else {
            Write-Message -Level Warning -Message $Message -EnableException $EnableException -FunctionName $FunctionName -Target $Target -ErrorRecord $records -Tag $Tag -ModuleName $ModuleName -OverrideExceptionMessage:$OverrideExceptionMessage -File $File -Line $Line
        }
    } else {
        $exception = New-Object System.Exception($Message)
        $records += New-Object System.Management.Automation.ErrorRecord($Exception, "dbatools_$FunctionName", $Category, $Target)

        # Manage Debugging
        if ($EnableException) {
            Write-Message -Level Warning -Message $Message -EnableException $EnableException -FunctionName $FunctionName -Target $Target -ErrorRecord $records -Tag $Tag -ModuleName $ModuleName -OverrideExceptionMessage:$true -File $File -Line $Line 3>$null
        } else {
            Write-Message -Level Warning -Message $Message -EnableException $EnableException -FunctionName $FunctionName -Target $Target -ErrorRecord $records -Tag $Tag -ModuleName $ModuleName -OverrideExceptionMessage:$true -File $File -Line $Line }
    }
    #endregion Message Handling

    #region EnableException Mode
    if ($EnableException) {
        if ($SilentlyContinue) {
            foreach ($record in $records) {
                Write-Error -Message $record -Category $Category -TargetObject $Target -Exception $record.Exception -ErrorId "dbatools_$FunctionName" -ErrorAction Continue
            }
            if ($ContinueLabel) {
                continue $ContinueLabel
            } else {
                continue
            }
        }

        # Extra insurance that it'll stop
        Set-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -Scope 1 -Value $true

        throw $records[0]
    }
    #endregion EnableException Mode

    #region Non-EnableException Mode
    else {
        # This ensures that the error is stored in the $error variable AND has its Stacktrace (simply adding the record would lack the stacktrace)
        foreach ($record in $records) {
            $null = Write-Error -Message $record -Category $Category -TargetObject $Target -Exception $record.Exception -ErrorId "dbatools_$FunctionName" -ErrorAction Continue 2>&1
        }

        if ($Continue) {
            if ($ContinueLabel) {
                continue $ContinueLabel
            } else {
                continue
            }
        } else {
            # Make sure the function knows it should be stopping
            Set-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -Scope 1 -Value $true

            return
        }
    }
    #endregion Non-EnableException Mode
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU8MS4ebtZNFYJ8MLDeEcH2jMn
# F2igghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
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
# MRYEFPV1Kg46O5myd8K6jf6P+j7kbUnLMA0GCSqGSIb3DQEBAQUABIIBADx+et6i
# iqlyEYguAG2AGOuFs76Efk9Fs1xCVCmTXjsPv7ACf6WFFDhJXUc2Sg+4u2JTYXgi
# IX7AxeqpsRCoRgMe2kX7zpS+Zc2pOpclyHsFqWhC4+1y1ldmEALIGdYE3Wgv4IQq
# K815LauSVR21Cn6MArY4nQHtNd0XCCMFcU4xkFqgB/aBnbL5DW9Z0OuFJ6ZHpzQW
# xkej2/k358YZeaO7QfSyTrN8Etls27gG6A3yiXZJ6+LFBjC0aTEt4FL3PUPrzBhR
# GkkfQ0LxQ07vkBPe8EXkOEl+9RhpfHyrlKeKq9BGpLhXQevLifAWxxt4z1OXQMNZ
# lQkTA1qWXSQSonehggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAyNVowLwYJKoZIhvcNAQkEMSIEIFRLc4ts+BjB7QlQBfcVe0bgooEZ
# ZUsBKbU4BhsO8q2lMA0GCSqGSIb3DQEBAQUABIIBADoMeC4AvILiJruqMqPn14yt
# rlqs1bWKqKdyczKDT6OoJx3MG5d7U//vUabGKx2PeMaBFNlfwCktYapJcBFjOA+f
# g8L6o4ghbjINYrUZs8otTpeWrvFVgg6ff5YxQN7R7IiagBwjUCVCxs6OhhsuwAk6
# JywbG081/Ha4y+TkxBR/sFpyHtrymt1tdozmKEu3hW63IQIfrHFf6jA5iT/zM5k6
# M1yf9uxxBLWJKxLVnCv28C6em7YZN/IZ/VpXhtNU9rwbMT0XTtOS2A5tD/U8J+a/
# s5vXk0NqlhmeWDAGjPUxC6LbLZje3Qf2E30WYia/ZYK4X5b0yro09iwav1csEh8=
# SIG # End signature block
