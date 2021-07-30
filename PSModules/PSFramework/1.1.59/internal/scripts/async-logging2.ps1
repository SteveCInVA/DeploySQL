﻿$scriptBlock = {
	try
	{
		$script:___ScriptName = 'PSFramework.Logging'
		
		Import-Module (Join-Path ([PSFramework.PSFCore.PSFCoreHost]::ModuleRoot) 'PSFramework.psd1')
		
		while ($true)
		{
			# This portion is critical to gracefully closing the script
			if ([PSFramework.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLower()].State -notlike "Running")
			{
				break
			}
			
			#region Manage Begin Event
			foreach ($___provider in [PSFramework.Logging.ProviderHost]::GetEnabled())
			{
				if (-not $___provider.Initialized)
				{
					[PSFramework.Logging.ProviderHost]::LoggingState = 'Initializing'
					try
					{
						$ExecutionContext.InvokeCommand.InvokeScript($false, ([System.Management.Automation.ScriptBlock]::Create($___provider.BeginEvent)), $null, $null)
						$___provider.Initialized = $true
					}
					catch { $___provider.Errors.Push($_) }
				}
			}
			[PSFramework.Logging.ProviderHost]::LoggingState = 'Ready'
			#endregion Manage Begin Event
			
			#region Start Event
			foreach ($___provider in [PSFramework.Logging.ProviderHost]::GetInitialized())
			{
				try { $ExecutionContext.InvokeCommand.InvokeScript($false, ([System.Management.Automation.ScriptBlock]::Create($___provider.StartEvent)), $null, $null) }
				catch { $___provider.Errors.Push($_) }
			}
			#endregion Start Event
			
			#region Message Event
			while ([PSFramework.Message.LogHost]::OutQueueLog.Count -gt 0)
			{
				$Entry = $null
				[PSFramework.Message.LogHost]::OutQueueLog.TryDequeue([ref]$Entry)
				if ($Entry)
				{
					[PSFramework.Logging.ProviderHost]::LoggingState = 'Writing'
					foreach ($___provider in [PSFramework.Logging.ProviderHost]::GetInitialized())
					{
						if ($___provider.MessageApplies($Entry))
						{
							try { $ExecutionContext.InvokeCommand.InvokeScript($false, ([System.Management.Automation.ScriptBlock]::Create($___provider.MessageEvent)), $null, $Entry) }
							catch { $___provider.Errors.Push($_) }
						}
					}
				}
			}
			#endregion Message Event
			
			#region Error Event
			while ([PSFramework.Message.LogHost]::OutQueueError.Count -gt 0)
			{
				$Record = $null
				[PSFramework.Message.LogHost]::OutQueueError.TryDequeue([ref]$Record)
				
				if ($Record)
				{
					[PSFramework.Logging.ProviderHost]::LoggingState = 'Writing'
					foreach ($___provider in [PSFramework.Logging.ProviderHost]::GetInitialized())
					{
						if ($___provider.MessageApplies($Record))
						{
							try { $ExecutionContext.InvokeCommand.InvokeScript($false, ([System.Management.Automation.ScriptBlock]::Create($___provider.ErrorEvent)), $null, $Record) }
							catch { $___provider.Errors.Push($_) }
						}
					}
				}
			}
			#endregion Error Event
			
			#region End Event
			foreach ($___provider in [PSFramework.Logging.ProviderHost]::GetInitialized())
			{
				try { $ExecutionContext.InvokeCommand.InvokeScript($false, ([System.Management.Automation.ScriptBlock]::Create($___provider.EndEvent)), $null, $null) }
				catch { $___provider.Errors.Push($_) }
			}
			#endregion End Event
			
			[PSFramework.Logging.ProviderHost]::LoggingState = 'Ready'
			Start-Sleep -Milliseconds 100
		}
	}
	catch
	{
		$wasBroken = $true
	}
	finally
	{
		#region Flush log on exit
		if (([PSFramework.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLower()].State -like "Running") -and (-not [PSFramework.Configuration.ConfigurationHost]::Configurations["psframework.logging.disablelogflush"].Value))
		{
			#region Start Event
			foreach ($___provider in [PSFramework.Logging.ProviderHost]::GetInitialized())
			{
				try { $ExecutionContext.InvokeCommand.InvokeScript($false, ([System.Management.Automation.ScriptBlock]::Create($___provider.StartEvent)), $null, $null) }
				catch { $___provider.Errors.Push($_) }
			}
			#endregion Start Event
			
			#region Message Event
			while ([PSFramework.Message.LogHost]::OutQueueLog.Count -gt 0)
			{
				$Entry = $null
				[PSFramework.Message.LogHost]::OutQueueLog.TryDequeue([ref]$Entry)
				if ($Entry)
				{
					[PSFramework.Logging.ProviderHost]::LoggingState = 'Writing'
					foreach ($___provider in [PSFramework.Logging.ProviderHost]::GetInitialized())
					{
						if ($___provider.MessageApplies($Entry))
						{
							try { $ExecutionContext.InvokeCommand.InvokeScript($false, ([System.Management.Automation.ScriptBlock]::Create($___provider.MessageEvent)), $null, $Entry) }
							catch { $___provider.Errors.Push($_) }
						}
					}
				}
			}
			#endregion Message Event
			
			#region Error Event
			while ([PSFramework.Message.LogHost]::OutQueueError.Count -gt 0)
			{
				$Record = $null
				[PSFramework.Message.LogHost]::OutQueueError.TryDequeue([ref]$Record)
				
				if ($Record)
				{
					[PSFramework.Logging.ProviderHost]::LoggingState = 'Writing'
					foreach ($___provider in [PSFramework.Logging.ProviderHost]::GetInitialized())
					{
						if ($___provider.MessageApplies($Record))
						{
							try { $ExecutionContext.InvokeCommand.InvokeScript($false, ([System.Management.Automation.ScriptBlock]::Create($___provider.MessageEvent)), $null, $Record) }
							catch { $___provider.Errors.Push($_) }
						}
					}
				}
			}
			#endregion Error Event
			
			#region End Event
			foreach ($___provider in [PSFramework.Logging.ProviderHost]::GetInitialized())
			{
				try { $ExecutionContext.InvokeCommand.InvokeScript($false, ([System.Management.Automation.ScriptBlock]::Create($___provider.EndEvent)), $null, $null) }
				catch { $___provider.Errors.Push($_) }
			}
			#endregion End Event
		}
		#endregion Flush log on exit
		
		#region Final Event
		foreach ($___provider in [PSFramework.Logging.ProviderHost]::GetInitialized())
		{
			try { $ExecutionContext.InvokeCommand.InvokeScript($false, ([System.Management.Automation.ScriptBlock]::Create($___provider.FinalEvent)), $null, $null) }
			catch { $___provider.Errors.Push($_) }
		}
		
		foreach ($___provider in [PSFramework.Logging.ProviderHost]::GetInitialized())
		{
			$___provider.Initialized = $false
		}
		#endregion Final Event
		
		if ($wasBroken) { [PSFramework.Logging.ProviderHost]::LoggingState = 'Broken' }
		else { [PSFramework.Logging.ProviderHost]::LoggingState = 'Stopped' }
		
		[PSFramework.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLower()].SignalStopped()
	}
}

Register-PSFRunspace -ScriptBlock $scriptBlock -Name 'PSFramework.Logging' -NoMessage
Start-PSFRunspace -Name 'PSFramework.Logging' -NoMessage