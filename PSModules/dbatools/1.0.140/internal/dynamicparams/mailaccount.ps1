#region Initialize Cache
if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["mailaccount"]) {
    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["mailaccount"] = @{ }
}
#endregion Initialize Cache

#region Tepp Data return
$ScriptBlock = {
    param (
        $commandName,

        $parameterName,

        $wordToComplete,

        $commandAst,

        $fakeBoundParameter
    )


    $server = $fakeBoundParameter['SqlInstance']

    if (-not $server) {
        $server = $fakeBoundParameter['Source']
    }

    if (-not $server) {
        $server = $fakeBoundParameter['ComputerName']
    }

    if (-not $server) { return }

    try {
        [DbaInstanceParameter]$parServer = $server | Select-Object -First 1
    } catch {
        return
    }

    if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["mailaccount"][$parServer.FullSmoName.ToLowerInvariant()]) {
        foreach ($name in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["mailaccount"][$parServer.FullSmoName.ToLowerInvariant()] | Where-DbaObject -Like "$wordToComplete*")) {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        return
    }

    try {
        $serverObject = Connect-SqlInstance -SqlInstance $parServer -SqlCredential $fakeBoundParameter['SqlCredential'] -ErrorAction Stop
        foreach ($name in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["mailaccount"][$parServer.FullSmoName.ToLowerInvariant()] | Where-DbaObject -Like "$wordToComplete*")) {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        return
    } catch {
        return
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name MailAccount
#endregion Tepp Data return

#region Update Cache
$ScriptBlock = {

    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["mailaccount"][$FullSmoName] = $server.Mail.Accounts.Name
}
Register-DbaTeppInstanceCacheBuilder -ScriptBlock $ScriptBlock
#endregion Update Cache