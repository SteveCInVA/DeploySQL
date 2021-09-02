function CopyFiles {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestPath
    )

    write-verbose "Copy files from $SourcePath to $DestPath..."
    try{
        xcopy "$SourcePath" "$DestPath" /s /e /d /f /y > $null
    }
    catch
    {
        Write-warning $_.Exception.Message
    }
    Write-Verbose "Copy files completed."

}