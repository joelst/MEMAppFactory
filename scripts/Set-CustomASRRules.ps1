<#
    Set-CustomASRRules.ps1

    Applies all ASR Rule Ids provided in the RuleIds parameter
    As-is no warranties, please test before using in production. 
    Please provide suggestions and updates via GitHub.

Joel Stidley
https://github.com/joelst

Reference: https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/attack-surface-reduction-rules-reference
    - Block Persistance through WMI event subscription GUID: e6db77e5-3df2-4cf1-b95a-636979351e5b
    - Block abuse of exploited vulnerable signed drivers GUID: 56a863a9-875e-4185-98a7-b882c64b5ce5
    - Block executable files from running unless they meet a prevalence, age, or trusted list criterion. GUID: 01443614-cd74-433a-b99e-2ecdc07bfc25
    - Block abuse of exploited vulnerable signed drivers GUID: 56a863a9-875e-4185-98a7-b882c64b5ce5
    - Use advanced protection against ransomware GUID: c1db55ab-c21a-4637-bb3f-a12568109d35
    - Block all Office apps from creating child processes: d4f940ab-401b-4efc-aadc-ad5f3c50688a
    - Block Adobe Reader from creating child proceses: 7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c
    - Block credential stealing from the Windows local security authority subsystem: 9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2
    - Block executable content from email client and webmail be9ba2d9-53ea-4cdc-84e5-9b1eeee46550
    - Block execution of potentially obfuscated scripts 5beb7efe-fd9a-4556-801d-275e5ffc04cc
    - Block JavaScript or VBScript from launching downloaded executable content d3e037e1-3eb8-44c8-a917-57927947596d
    - Block Office applications from creating executable content 3b576869-a4ec-4529-8536-b80a7769e899
    - Block Office applications from injecting code into other processes 75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84
    - Block Office communication application from creating child processes 26190899-1602-49e8-8b27-eb1d0a1ce869
    - Block process creations originating from PSExec and WMI commands d1e49aac-8f56-4280-b9ba-993a6d77406c
    - Block untrusted and unsigned processes that run from USB b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4
    - Block Win32 API calls from Office macros 92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b
#> 
[CmdletBinding()]
param (
    # string array of all rule Ids to apply
    [Parameter()]
    [array]$RuleIds = @("e6db77e5-3df2-4cf1-b95a-636979351e5b", "d1e49aac-8f56-4280-b9ba-993a6d77406c", "01443614-cd74-433a-b99e-2ecdc07bfc25", "56a863a9-875e-4185-98a7-b882c64b5ce5", "c1db55ab-c21a-4637-bb3f-a12568109d35", "d4f940ab-401b-4efc-aadc-ad5f3c50688a", "7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c", "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2", "be9ba2d9-53ea-4cdc-84e5-9b1eeee46550", "5beb7efe-fd9a-4556-801d-275e5ffc04cc", "d3e037e1-3eb8-44c8-a917-57927947596d", "3b576869-a4ec-4529-8536-b80a7769e899", "26190899-1602-49e8-8b27-eb1d0a1ce869", "b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4", "92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b"),
    # Type of action. Can be Enabled, AuditMode, Warn, Disabled
    [Parameter()]
    [string]
    [ValidateSet("Enabled", "Disabled", "AuditMode", "Warn")]
    $ActionType = "Enabled",
    # Switch to force overwriting existing rules with the rules provided in RuleIds
    [Parameter()]
    [switch]$Overwrite
)

function Set-RegInfo {
    [CmdletBinding()]
    param (
        $RegistryPath,
        $Name,
        $Value,
        $Type
    )
    
# Create the key if it does not exist
    If (-NOT (Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
    }  
    # Now set the value
    $null = New-ItemProperty -Path $RegistryPath -Name $Name -Value $Value -PropertyType $Type -Force
}

[string]$rules = ""
[string]$actions = ""

if ($Overwrite.IsPresent -eq $false) {
    # Get the existing rules, so we don't overwrite any
    $existingRuleIds = (Get-MpPreference).AttackSurfaceReductionRules_Ids
    $RuleIds +=  $existingRuleIds

}

$RuleIds = $RuleIds | Sort-Object -Unique 

Foreach ($ruleId in $RuleIds) {
    $rules += ",$ruleId"
    $actions += ",$ActionType"

$rules = $rules.TrimStart(",")
$actions = $actions.TrimStart(",")

Add-MpPreference -AttackSurfaceReductionRules_Ids $rules -AttackSurfaceReductionRules_Actions $actions

# Enable Potentially unwanted application protection
Set-MpPreference -PUAProtection Enabled

# Set other registry keys
# Disable bridge
Set-RegInfo -RegistryPath "HKLM\SOFTWARE\Policies\Microsoft\Windows\Network Connections" -Name "NC_AllowNetBridge_NLA" -Value 0 -Type "REG_DWORD"
# Disable always install with elevated privileges
Set-RegInfo -RegistryPath "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name "AlwaysInstallElevated" -Value 0 -Type "REG_DWORD"
#Disable Javascript on Adobe DC
Set-RegInfo -RegistryPath "HKLM\SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown\r" -Name "bDisableJavaScript" -Value 1 -Type "REG_DWORD"