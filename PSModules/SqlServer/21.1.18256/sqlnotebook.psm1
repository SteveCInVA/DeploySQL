#------------------------------------------------------------
# Copyright (c) Microsoft Corporation.  All rights reserved.
#------------------------------------------------------------

Set-StrictMode -Version Latest

function Invoke-SqlNotebook {

    [CmdletBinding(DefaultParameterSetName="ByConnectionParameters")]

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUsePSCredentialType", "Username", Justification="Intentionally allowing User/Password, in addition to a PSCredential parameter.")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "Password", Justification="Intentionally allowing User/Password, in addition to a PSCredential parameter.")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUsernameAndPasswordParams", "", Justification="Intentionally allowing User/Password, in addition to a PSCredential parameter.")]

    # Parameters
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'ByConnectionParameters')]$ServerInstance,
        [Parameter(Mandatory = $false, ParameterSetName = 'ByConnectionParameters')]$Database,
        [Parameter(Mandatory = $false, ParameterSetName = 'ByConnectionParameters')][ValidateNotNullorEmpty()]$Username,
        [Parameter(Mandatory = $false, ParameterSetName = 'ByConnectionParameters')][ValidateNotNullorEmpty()]$Password,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByConnectionString')][ValidateNotNullorEmpty()]$ConnectionString,
        [Parameter(Mandatory = $false, ParameterSetName = 'ByConnectionParameters')][ValidateNotNullorEmpty()][PSCredential]$Credential,
        [Parameter(Mandatory = $true, ParameterSetName='ByInputFile')]
        [Parameter(ParameterSetName = 'ByConnectionParameters')]
        [Parameter(ParameterSetName = 'ByConnectionString')]$InputFile,
        [Parameter(Mandatory = $true, ParameterSetName='ByInputObject')]
        [Parameter(ParameterSetName = 'ByConnectionParameters')]
        [Parameter(ParameterSetName = 'ByConnectionString')]$InputObject,
        [Parameter(Mandatory = $false)][ValidateNotNullorEmpty()]$OutputFile,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByConnectionParameters')][ValidateNotNullorEmpty()][string]$AccessToken,

        [Switch]$Force
    )

    #Checks to see if OutputFile is given
    #If it is, checks to see if extension is there
    function getOutputFile($inputFile,$outputFile) {
        if($outputFile) {
            $extn = [IO.Path]::GetExtension($outputFile)
            if ($extn.Length -eq 0) {
                $outputFile = ($outputFile + ".ipynb")
            }
            $outputFile
        }
        else {
            #If User does not define Output it will use the inputFile file location
            $fileinfo = Get-Item $inputFile

            # Create an output file based on the file path of input and name
            Join-Path $fileinfo.DirectoryName ($fileinfo.BaseName + "_out" + $fileinfo.Extension)
        }
    }

    #Validates InputFile and Converts InputFile to Json Object
    function getFileContents($inputfile) {

        if (-not (Test-Path -Path $inputfile)) {
            Throw New-Object System.IO.FileNotFoundException ($inputfile + " does not exist")
        }

        $fileItem = Get-Item $inputfile

        #Checking if file is a python notebook
        if ($fileItem.Extension -ne ".ipynb") {
            Throw New-Object System.FormatException "Only ipynb files are supported"
        }

        $fileContent = Get-Content $inputfile
        try {
            $fileContentJson = ($fileContent | ConvertFrom-Json)
        }
        catch {
            Throw New-Object System.FormatException "Malformed Json file"
        }
        $fileContentJson
    }

    #Validate SQL Kernel Notebook
    function validateKernelType($fileContentJson) {
        if ($fileContentJson.metadata.kernelspec.name -ne "SQL") {
            Throw New-Object System.NotSupportedException "Kernel type '$($fileContentJson.metadata.kernelspec.name)' not supported."
        }
    }

    #Validate non-existing output file
    #If file exists and $throwifexists, an exception is thrown.
    function validateExistingOutputFile($outputfile, $throwifexists) {
        if ($outputfile -and (Test-Path $outputfile) -and $throwifexists) {
            Throw New-Object System.IO.IOException "The file '$($outputfile)' already exists. Please, specify -Force to overwrite it."
        }
    }

    #Parsing Notebook Data to Notebook Output
    function ParseTableToNotebookOutput {
        param (
            [System.Data.DataTable]
            $DataTable,

            [int]
            $CellExecutionCount
        )
        $TableHTMLText = "<table>"
        $TableSchemaFeilds = @()
        $TableHTMLText += "<tr>"
        foreach ($ColumnName in $DataTable.Columns) {
            $TableSchemaFeilds += @(@{name = $ColumnName.toString() })
            $TableHTMLText += "<th>" + $ColumnName.toString() + "</th>"
        }
        $TableHTMLText += "</tr>"
        $TableSchema = @{ }
        $TableSchema["fields"] = $TableSchemaFeilds

        $TableDataRows = @()
        foreach ($Row in $DataTable) {
            $TableDataRow = [ordered]@{ }
            $TableHTMLText += "<tr>"
            $i = 0
            foreach ($Cell in $Row.ItemArray) {
                $TableDataRow[$i.ToString()] = $Cell.toString()
                $TableHTMLText += "<td>" + $Cell.toString() + "</td>"
                $i++
            }
            $TableHTMLText += "</tr>"
            $TableDataRows += $TableDataRow
        }

        $TableDataResource = @{ }
        $TableDataResource["schema"] = $TableSchema
        $TableDataResource["data"] = $TableDataRows
        $TableData = @{ }
        $TableData["application/vnd.dataresource+json"] = $TableDataResource
        $TableData["text/html"] = $TableHTMLText
        $TableOutput = @{ }
        $TableOutput["output_type"] = "execute_result"
        $TableOutput["data"] = $TableData
        $TableOutput["metadata"] = @{ }
        $TableOutput["execution_count"] = $CellExecutionCount
        return $TableOutput
    }

    #Parsing the Error Messages to Notebook Output
    function ParseQueryErrorToNotebookOutput {
        param (
            $QueryError
        )
        <#
        Following the current syntax of errors in T-SQL notebooks from ADS
        #>
        $ErrorString = "Msg " + $QueryError.Exception.InnerException.Number +
        ", Level " + $QueryError.Exception.InnerException.Class +
        ", State " + $QueryError.Exception.InnerException.State +
        ", Line " + $QueryError.Exception.InnerException.LineNumber +
        "`r`n" + $QueryError.Exception.Message

        $ErrorOutput = @{ }
        $ErrorOutput["output_type"] = "error"
        $ErrorOutput["traceback"] = @()
        $ErrorOutput["evalue"] = $ErrorString
        return $ErrorOutput
    }

    #Parsing Messages to Notebook Output
    function ParseStringToNotebookOutput {
        param (
            [System.String]
            $InputString
        )
        <#
        Parsing the string to notebook cell output.
        It's the standard Jupyter Syntax
        #>
        $StringOutputData = @{ }
        $StringOutputData["text/html"] = $InputString
        $StringOutput = @{ }
        $StringOutput["output_type"] = "display_data"
        $StringOutput["data"] = $StringOutputData
        $StringOutput["metadata"] = @{ }
        return $StringOutput
    }

    #Start of Script
    #Checks to see if InputFile or InputObject was entered

    #Checks to InputFile Type and initializes OutputFile
    if ($InputFile -is [System.String]) {
        $fileInformation = getFileContents($InputFile)
        $fileContent = $fileInformation[0]
        $OutputFile = getOutputFile $InputFile $OutputFile
    } elseif ($InputFile -is [System.IO.FileInfo]) {
        $fileInformation = getFileContents($InputFile.FullName)
        $fileContent = $fileInformation[0]
        $OutputFile = getOutputFile $InputFile $OutputFile
    } else {
        $fileContent = $InputObject
    }

    #Checks InputObject and converts that to appropriate Json object
    if ($InputObject -is [System.String]) {
        $fileContentJson = ($InputObject | ConvertFrom-Json)
        $fileContent = $fileContentJson[0]
    }

    #Validates only SQL Notebooks
    validateKernelType $fileContent

    #Validate that $OutputFile does not exist, or, if it exists a -Force was passed in.
    validateExistingOutputFile $OutputFile (-not $Force)

    #Setting params for Invoke-Sqlcmd
    $DatabaseQueryHashTable = @{ }

    #Checks to see if User entered ConnectionString or individual parameters
    if ($ConnectionString) {
        $DatabaseQueryHashTable["ConnectionString"] = $ConnectionString
    } else {
        if ($ServerInstance) {
            $DatabaseQueryHashTable["ServerInstance"] = $ServerInstance
        }
        if ($Database) {
            $DatabaseQueryHashTable["Database"] = $Database
        }
        #Checks to see if User entered AccessToken, Credential, or individual parameters
        if ($AccessToken) {
            $DatabaseQueryHashTable["AccessToken"] = $AccessToken
        } else {
            if ($Credential) {
                $DatabaseQueryHashTable["Credential"] = $Credential
            } else {
                if ($Username) {
                    $DatabaseQueryHashTable["Username"] = $Username
                }
                if ($Password) {
                    $DatabaseQueryHashTable["Password"] = $Password
                }
            }
        }
    }

    #Setting additional parameters for Invoke-SQLCMD to get
    #all the information from Notebook execution to output
    $DatabaseQueryHashTable["Verbose"] = $true
    $DatabaseQueryHashTable["ErrorVariable"] = "SqlQueryError"
    $DatabaseQueryHashTable["OutputAs"] = "DataTables"

    #The first code cell number
    $cellExecutionCount = 1
    #Iterate through Notebook Cells
    $fileContent.cells | Where-Object {
        # Ignoring Markdown or raw cells
        $_.cell_type -ne "markdown" -and $_.cell_type -ne "raw" -and $_.source -ne ""
    } | ForEach-Object {
        $NotebookCellOutputs = @()

        # Getting the source T-SQL from the cell
        # Note that the cell's source field can be
        # an array (or strings) or a scalar (string).
        # If an array, elements are properly terminated with CR/LF.
        $DatabaseQueryHashTable["Query"] = $_.source -join ''

        # Executing the T-SQL Query and storing the result and the time taken to execute
        $SqlQueryExecutionTime = Measure-Command {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "SqlQueryResult", Justification="Suppressing false warning.")]
            $SqlQueryResult = @( Invoke-Sqlcmd @DatabaseQueryHashTable -ErrorAction SilentlyContinue 4>&1)
        }

        # Setting the Notebook Cell Execution Count to increase count of each code cell
        # Note: handle the case where the 'execution_count' property is missing.
        if (-not ($_ | Get-Member execution_count)) {
            $_ | Add-Member -Name execution_count -Value $null -MemberType NoteProperty
        }
        $_.execution_count = $cellExecutionCount++

        $NotebookCellTableOutputs = @()

        <#
        Iterating over the results by Invoke-Sqlcmd
        There are 2 types of errors:
        1. Verbose Output: Print Statements:
            These needs to be added to the beginning of the cell outputs
        2. Datatables from the database
            These needs to be added to the end of cell outputs
        #>
        $SqlQueryResult | ForEach-Object {
            if ($_ -is [System.Management.Automation.VerboseRecord]) {
                # Adding the print statments to the cell outputs
                $NotebookCellOutputs += $(ParseStringToNotebookOutput($_.Message))
            } elseif ($_ -is [System.Data.DataTable]) {
                # Storing the print Tables into an array to be added later to the cell output
                $NotebookCellTableOutputs += $(ParseTableToNotebookOutput $_  $CellExecutionCount)
            } elseif ($_ -is [System.Data.DataRow]) {
                # Storing the print row into an array to be added later to the cell output
                $NotebookCellTableOutputs += $(ParseTableToNotebookOutput $_.Table  $CellExecutionCount)
            }
        }

        if ($SqlQueryError) {
            # Adding the parsed query error from Invoke-Sqlcmd
            $NotebookCellOutputs += $(ParseQueryErrorToNotebookOutput($SqlQueryError))
        }

        if ($SqlQueryExecutionTime) {
            # Adding the parsed execution time from Measure-Command
            $NotebookCellExcutionTimeString = "Total execution time: " + $SqlQueryExecutionTime.ToString()
            $NotebookCellOutputs += $(ParseStringToNotebookOutput($NotebookCellExcutionTimeString))
        }

        # Adding the data tables
        $NotebookCellOutputs += $NotebookCellTableOutputs

        # In the unlikely case the 'outputs' property is missing from the JSON
        # object, we add it.
        if (-not ($_ | Get-Member outputs)) {
            $_ | Add-Member -Name outputs -Value $null -MemberType NoteProperty
        }
        $_.outputs = $NotebookCellOutputs
    }

    # This will update the Output file according to the executed output of the notebook
    if ($OutputFile) {
        ($fileContent | ConvertTo-Json -Depth 100 ) | Out-File  -Encoding Ascii -FilePath $OutputFile
        Get-Item $OutputFile
    }
    else {
        $fileContent | ConvertTo-Json -Depth 100
    }
}

# SIG # Begin signature block
# MIIjrwYJKoZIhvcNAQcCoIIjoDCCI5wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDa0g1ksj3mus05
# CXhKi3QwcyakVU5s4+QzqXPKyPwzyaCCDYEwggX/MIID56ADAgECAhMzAAAB32vw
# LpKnSrTQAAAAAAHfMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjAxMjE1MjEzMTQ1WhcNMjExMjAyMjEzMTQ1WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC2uxlZEACjqfHkuFyoCwfL25ofI9DZWKt4wEj3JBQ48GPt1UsDv834CcoUUPMn
# s/6CtPoaQ4Thy/kbOOg/zJAnrJeiMQqRe2Lsdb/NSI2gXXX9lad1/yPUDOXo4GNw
# PjXq1JZi+HZV91bUr6ZjzePj1g+bepsqd/HC1XScj0fT3aAxLRykJSzExEBmU9eS
# yuOwUuq+CriudQtWGMdJU650v/KmzfM46Y6lo/MCnnpvz3zEL7PMdUdwqj/nYhGG
# 3UVILxX7tAdMbz7LN+6WOIpT1A41rwaoOVnv+8Ua94HwhjZmu1S73yeV7RZZNxoh
# EegJi9YYssXa7UZUUkCCA+KnAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUOPbML8IdkNGtCfMmVPtvI6VZ8+Mw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDYzMDA5MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAnnqH
# tDyYUFaVAkvAK0eqq6nhoL95SZQu3RnpZ7tdQ89QR3++7A+4hrr7V4xxmkB5BObS
# 0YK+MALE02atjwWgPdpYQ68WdLGroJZHkbZdgERG+7tETFl3aKF4KpoSaGOskZXp
# TPnCaMo2PXoAMVMGpsQEQswimZq3IQ3nRQfBlJ0PoMMcN/+Pks8ZTL1BoPYsJpok
# t6cql59q6CypZYIwgyJ892HpttybHKg1ZtQLUlSXccRMlugPgEcNZJagPEgPYni4
# b11snjRAgf0dyQ0zI9aLXqTxWUU5pCIFiPT0b2wsxzRqCtyGqpkGM8P9GazO8eao
# mVItCYBcJSByBx/pS0cSYwBBHAZxJODUqxSXoSGDvmTfqUJXntnWkL4okok1FiCD
# Z4jpyXOQunb6egIXvkgQ7jb2uO26Ow0m8RwleDvhOMrnHsupiOPbozKroSa6paFt
# VSh89abUSooR8QdZciemmoFhcWkEwFg4spzvYNP4nIs193261WyTaRMZoceGun7G
# CT2Rl653uUj+F+g94c63AhzSq4khdL4HlFIP2ePv29smfUnHtGq6yYFDLnT0q/Y+
# Di3jwloF8EWkkHRtSuXlFUbTmwr/lDDgbpZiKhLS7CBTDj32I0L5i532+uHczw82
# oZDmYmYmIUSMbZOgS65h797rj5JJ6OkeEUJoAVwwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIVhDCCFYACAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAd9r8C6Sp0q00AAAAAAB3zAN
# BglghkgBZQMEAgEFAKCB2jAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg6FU+HA74
# YQRLN+aT+ijOjTgRNcojcXwpU2K6sOnHu04wbgYKKwYBBAGCNwIBDDFgMF6gOoA4
# AFMAUQBMACAAUwBlAHIAdgBlAHIAIABNAGEAbgBhAGcAZQBtAGUAbgB0ACAAUwB0
# AHUAZABpAG+hIIAeaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3NxbC8gMA0GCSqG
# SIb3DQEBAQUABIIBACTrYZVO1BdwDfamDvr/MJHe/Z0l7IgRTe4R6Nlh81pZzrjE
# xc3DYLtE1P4RKWARe1YGonwSYee7ugrXk9mukOXlamXR8ChNTvF90No5OWKZIwpq
# huEOuaDWsliu3kbkQF1MXUUq1mXcnedUEq1jjP95jhqoE9OAIYbYUul/in1F79Ke
# YQHDD+p4N3LbitVl65eoj6b3gQGnJluyRSg6cwyEmme5Lz1lv+x3MUk892AON0bu
# vVmmIEmkYGGz8Lj9nnaL0szUSdElmF5vMi8RvDvuGfRT6+AcpmwWcOGV+R514MOL
# toa526uwU7OnGGxzWs2PCGXZNt/VrXK3zmD3MSmhghLiMIIS3gYKKwYBBAGCNwMD
# ATGCEs4wghLKBgkqhkiG9w0BBwKgghK7MIIStwIBAzEPMA0GCWCGSAFlAwQCAQUA
# MIIBUQYLKoZIhvcNAQkQAQSgggFABIIBPDCCATgCAQEGCisGAQQBhFkKAwEwMTAN
# BglghkgBZQMEAgEFAAQgvxtLt8BIfyjDDwH7+y8oE+CoSrWYC2lvQWZOjbZO+5cC
# BmDTZHFLKhgTMjAyMTA3MTMxODMzNTAuMDkxWjAEgAIB9KCB0KSBzTCByjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9z
# b2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046
# N0JGMS1FM0VBLUI4MDgxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNl
# cnZpY2Wggg45MIIE8TCCA9mgAwIBAgITMwAAAVHDUOdZbKrGpwAAAAABUTANBgkq
# hkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMDEx
# MTIxODI2MDRaFw0yMjAyMTExODI2MDRaMIHKMQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVy
# YXRpb25zMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo3QkYxLUUzRUEtQjgwODEl
# MCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCASIwDQYJKoZI
# hvcNAQEBBQADggEPADCCAQoCggEBAJ/Sh++qhK477ziJI1mx6bTJGA45hviRJs4L
# sq/1cY2YGf4oPDJOO46kiT+UcR/7A8qoWLu4z0jvOrImYfLuwwV/S/CPgAfvHzz7
# w+LqCyg9tgaaBZeAfBcOSu0rom728Rje2nS9f81vrFl5Vb6Q4RDyCgyArxHTYxky
# 4ZLX37Y3n4PZbpgTFASdhuP4OGndHQ70TZiojGV13vy5eEIP6D0s1wlBGKEkqmuQ
# /uTEYplXuf2Ey49I1a/IheOVdIU+1R/DiTuGCJnJ2Yaug8NRvsOgAkRnjxZjlqlv
# LRGdd0jJjqria05MMsvM8jbVbbSQF+3YhS20dErzJWyWVitCh3cCAwEAAaOCARsw
# ggEXMB0GA1UdDgQWBBTFd//jaFBikzRoOjjMhOnzdUTqbTAfBgNVHSMEGDAWgBTV
# YzpcijGQ80N7fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3Js
# Lm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNUaW1TdGFQQ0FfMjAx
# MC0wNy0wMS5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1RpbVN0YVBDQV8yMDEwLTA3
# LTAxLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqG
# SIb3DQEBCwUAA4IBAQAr/fXAFYOZ8dEqo7y30M5roDI+XCfTROtHbkh9S6cR2Ipv
# S7N1H4mHe7dCb8hMP60UxCh2851eixS5V/vpRyTBis2Zx7U3tjiOmRxZzYhYbYMl
# rmAya5uykMpDYtRtS27lYnvTHoZqCvoQYmZ563H2UpwUqJK7ztkBFhwtcZ2ecDPN
# lBI6axWDpHIVPukXKAo45iBRn4EszY9TCG3+JXCeRaFdTIOhcBeOQoozlx1V685I
# rDGfabg6RY4xFekwGOiDYDJIS3r/wFaMNLBfDH0M7SSJRWHRRJGeTRfyMs6AtmG/
# YsOGwinQa3Q9wLOpr6BkjYwgupTnc+hHqyStzYRYMIIGcTCCBFmgAwIBAgIKYQmB
# KgAAAAAAAjANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNh
# dGUgQXV0aG9yaXR5IDIwMTAwHhcNMTAwNzAxMjEzNjU1WhcNMjUwNzAxMjE0NjU1
# WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAKkdDbx3EYo6IOz8E5f1+n9plGt0VBDVpQoAgoX77Xxo
# SyxfxcPlYcJ2tz5mK1vwFVMnBDEfQRsalR3OCROOfGEwWbEwRA/xYIiEVEMM1024
# OAizQt2TrNZzMFcmgqNFDdDq9UeBzb8kYDJYYEbyWEeGMoQedGFnkV+BVLHPk0yS
# wcSmXdFhE24oxhr5hoC732H8RsEnHSRnEnIaIYqvS2SJUGKxXf13Hz3wV3WsvYpC
# TUBR0Q+cBj5nf/VmwAOWRH7v0Ev9buWayrGo8noqCjHw2k4GkbaICDXoeByw6ZnN
# POcvRLqn9NxkvaQBwSAJk3jN/LzAyURdXhacAQVPIk0CAwEAAaOCAeYwggHiMBAG
# CSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTVYzpcijGQ80N7fEYbxTNoWoVtVTAZ
# BgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/
# BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8E
# TzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9k
# dWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBM
# MEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRz
# L01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDCBoAYDVR0gAQH/BIGVMIGSMIGP
# BgkrBgEEAYI3LgMwgYEwPQYIKwYBBQUHAgEWMWh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9QS0kvZG9jcy9DUFMvZGVmYXVsdC5odG0wQAYIKwYBBQUHAgIwNB4yIB0A
# TABlAGcAYQBsAF8AUABvAGwAaQBjAHkAXwBTAHQAYQB0AGUAbQBlAG4AdAAuIB0w
# DQYJKoZIhvcNAQELBQADggIBAAfmiFEN4sbgmD+BcQM9naOhIW+z66bM9TG+zwXi
# qf76V20ZMLPCxWbJat/15/B4vceoniXj+bzta1RXCCtRgkQS+7lTjMz0YBKKdsxA
# QEGb3FwX/1z5Xhc1mCRWS3TvQhDIr79/xn/yN31aPxzymXlKkVIArzgPF/UveYFl
# 2am1a+THzvbKegBvSzBEJCI8z+0DpZaPWSm8tv0E4XCfMkon/VWvL/625Y4zu2Jf
# mttXQOnxzplmkIz/amJ/3cVKC5Em4jnsGUpxY517IW3DnKOiPPp/fZZqkHimbdLh
# nPkd/DjYlPTGpQqWhqS9nhquBEKDuLWAmyI4ILUl5WTs9/S/fmNZJQ96LjlXdqJx
# qgaKD4kWumGnEcua2A5HmoDF0M2n0O99g/DhO3EJ3110mCIIYdqwUB5vvfHhAN/n
# MQekkzr3ZUd46PioSKv33nJ+YWtvd6mBy6cJrDm77MbL2IK0cs0d9LiFAR6A+xuJ
# KlQ5slvayA1VmXqHczsI5pgt6o3gMy4SKfXAL1QnIffIrE7aKLixqduWsqdCosnP
# GUFN4Ib5KpqjEWYw07t0MkvfY3v1mYovG8chr1m1rtxEPJdQcdeh0sVV42neV8HR
# 3jDA/czmTfsNv11P6Z0eGTgvvM9YBS7vDaBQNdrvCScc1bN+NR4Iuto229Nfj950
# iEkSoYICyzCCAjQCAQEwgfihgdCkgc0wgcoxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJh
# dGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjdCRjEtRTNFQS1CODA4MSUw
# IwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
# AhoDFQCgoq9z8T+kQgslTCUgFaDFetcjXqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBBQUAAgUA5JhAbTAiGA8yMDIxMDcx
# NDAwNDAxM1oYDzIwMjEwNzE1MDA0MDEzWjB0MDoGCisGAQQBhFkKBAExLDAqMAoC
# BQDkmEBtAgEAMAcCAQACAhCNMAcCAQACAhKWMAoCBQDkmZHtAgEAMDYGCisGAQQB
# hFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAw
# DQYJKoZIhvcNAQEFBQADgYEAQfja0qqaKc/+pi8FL3lfi+RXMk79ZBJZgjsIXcP0
# f9KX1PZSR/XuL8QBXwnJRM6U/t8Jln3ZE8nkk6x4CRx2krv3FxA3wWG7fdhnikK6
# fhqfRtLWs/SzjMTNWp6pD+K5djxb1W73wfs6I82n/7zGPeEdKuOh2/tKzFkRS01X
# HuQxggMNMIIDCQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAIT
# MwAAAVHDUOdZbKrGpwAAAAABUTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcN
# AQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCCKimgDNfdeP25VCgJq
# 1QVJ/YohNgSjOH00uJ4nRlBCxTCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0E
# IC7NXJmI+NbBWQcAphb7/UnD+bbrlIcbL/7dAfVxeuVBMIGYMIGApH4wfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAFRw1DnWWyqxqcAAAAAAVEwIgQg
# uecP2OxJASTdbMZEFWqWo7aNQf3LnhhQh0PWo7pM0x8wDQYJKoZIhvcNAQELBQAE
# ggEAN6anqrDZZrrF9ubGlV1Q8Cc3MVFf7e67XURbQk2f37o6oLoBUc2fxtl64Ujp
# DjZnuSnv0DgMq1CHuR5M5SMsqROJFgvimpVbyzaJNXtsYsiQUbmlRIPi7Jn60Avb
# ShddnJB73VNiM0UwVTm3gYk+arUSCaIunZvzkf7XDTr3z3KnydLf2FZMxRj5LcdW
# WkZmv6sY7gZiM9xRlNgQchCWnHpoNmIZX69wM6KJ2UuafqKlVBf2+s+RSkcd1Cle
# RgiY9JDZtnmoCIpGAf4Rwtvs38lByUokht4nAgmdACvbF96zsCSi+CZswJfidolF
# Z7t1EL6P0xP3q7+P7IQd+QLc3w==
# SIG # End signature block
