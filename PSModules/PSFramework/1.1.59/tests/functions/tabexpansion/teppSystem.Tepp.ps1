﻿function Complete
{
	[CmdletBinding()]
	param (
		[string]
		$Expression
	)
	process
	{
		[System.Management.Automation.CommandCompletion]::CompleteInput(
			$Expression,
			$Expression.Length,
			$null
		).CompletionMatches
	}
}

Describe 'Completion tests: Tepp System' {
	#region Define Resources to complete for
	function Get-Alcohol
	{
		[CmdletBinding()]
		Param (
			[string]
			$Type,
			
			[string]
			$Unit = "Pitcher"
		)
		
		Write-Host "Drinking a $Unit of $Type"
	}
	
	# Create scriptblock that collects information and name it
	Register-PSFTeppScriptblock -Name 'alcohol.type' -ScriptBlock { 'Beer', 'Mead', 'Whiskey', 'Wine', 'Vodka', 'Rum (3y)', 'Rum (5y)', 'Rum (7y)' }
	
	# Assign scriptblock to function
	Register-PSFTeppArgumentCompleter -Command Get-Alcohol -Parameter Type -Name 'alcohol.type'
	
	# Create scriptblock that checks what was bound to ' -Type' so far and name it
	Register-PSFTeppScriptblock -Name 'alcohol.unit' -ScriptBlock {
		switch ($fakeBoundParameter.Type)
		{
			'Mead' { 'Mug', 'Horn', 'Barrel' }
			'Wine' { 'Glas', 'Bottle' }
			'Beer' { 'Halbes Maß', 'Maß' }
			default { 'Glas', 'Pitcher' }
		}
	}
	
	# Assign scriptblock to function
	Register-PSFTeppArgumentCompleter -Command Get-Alcohol -Parameter Unit -Name 'alcohol.unit'
	#endregion Define Resources to complete for
	
	It 'can complete a straight completion' {
		Complete 'Get-Alcohol -Type B' | Should -HaveProperty CompletionText -WithValue Beer
	}
	It 'can complete a completion dependent on another parameter value' {
		Complete 'Get-Alcohol -Type Beer -Unit M' | Should -HaveProperty CompletionText -WithValue 'Maß'
	}
}