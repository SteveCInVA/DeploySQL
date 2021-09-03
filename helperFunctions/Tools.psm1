function CopyFiles {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestPath
    )

    Write-Verbose "Copy files from $SourcePath to $DestPath..."
    try {
        xcopy "$SourcePath" "$DestPath" /s /e /d /f /y > $null
        Write-Verbose "Copy files completed."
    }
    catch {
        Write-Warning $_.Exception.Message
    }
}