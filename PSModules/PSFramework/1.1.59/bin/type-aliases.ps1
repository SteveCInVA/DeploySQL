﻿# Define our type aliases
$TypeAliasTable = @{
	PSFComputer		     = "PSFramework.Parameter.ComputerParameter"
	PSFComputerParameter = "PSFramework.Parameter.ComputerParameter"
	PSFDateTime		     = "PSFramework.Parameter.DateTimeParameter"
	PSFDateTimeParameter = "PSFramework.Parameter.DateTimeParameter"
	PSFEncoding		     = "PSFramework.Parameter.EncodingParameter"
	PSFEncodingParameter = "PSFramework.Parameter.EncodingParameter"
	psfrgx			     = "PSFramework.Utility.RegexHelper"
	PSFSize			     = "PSFramework.Utility.Size"
	PSFTimeSpan		     = "PSFramework.Parameter.TimeSpanParameter"
	PSFTimeSpanParameter = "PSFramework.Parameter.TimeSpanParameter"
	PSFValidatePattern   = "PSFramework.Validation.PsfValidatePatternAttribute"
	PSFValidateScript    = "PSFramework.Validation.PsfValidateScriptAttribute"
	PSFValidateSet	     = "PSFramework.Validation.PsfValidateSetAttribute"
}

Set-PSFTypeAlias -Mapping $TypeAliasTable