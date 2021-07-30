﻿if (-not [PSFramework.Configuration.ConfigurationHost]::ImportFromRegistryDone)
{
	# Read config from all settings
	$config_hash = Read-PsfConfigPersisted -Scope 127
	
	foreach ($value in $config_hash.Values)
	{
		try
		{
			if (-not $value.KeepPersisted) { Set-PSFConfig -FullName $value.FullName -Value $value.Value -EnableException }
			else { Set-PSFConfig -FullName $value.FullName -PersistedValue $value.Value -PersistedType $value.Type -EnableException }
			[PSFramework.Configuration.ConfigurationHost]::Configurations[$value.FullName.ToLower()].PolicySet = $value.Policy
			[PSFramework.Configuration.ConfigurationHost]::Configurations[$value.FullName.ToLower()].PolicyEnforced = $value.Enforced
		}
		catch { }
	}
	
	[PSFramework.Configuration.ConfigurationHost]::ImportFromRegistryDone = $true
}
