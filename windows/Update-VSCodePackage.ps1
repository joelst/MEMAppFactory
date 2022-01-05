#Requires -Modules IntuneWin32App, PSIntuneAuth, AzureAD
<#
    .SYNOPSIS
        Packages the latest Microsoft Visual Studio Code (User Setup) for MEM (Intune) deployment.
        Uploads the mew package into the target Intune tenant.

    .NOTES
        For details on IntuneWin32App go here: https://github.com/MSEndpointMgr/IntuneWin32App/blob/master/README.md
        For details on Evergreen go here: https://stealthpuppy.com/Evergreen
#>
[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False)]
    [System.String] $Path = "D:\MEMApp\",

    [Parameter(Mandatory = $False)]
    [System.String] $PackageOutputPath = "D:\MEMAppOut\",

    [Parameter(Mandatory = $False)]
    [System.String] $ScriptName = "Install-Package.ps1",

    [Parameter(Mandatory = $False)]
    [System.String] $TenantName = "placeholder.onmicrosoft.com",

    [Parameter(Mandatory = $False)]
    [System.Management.Automation.SwitchParameter] $Upload,

    [Parameter(Mandatory = $False)]
    $PackageName = "Visual Studio Code",
    
    [Parameter(Mandatory = $False)]
    $PackageId = "Microsoft.VisualStudioCode",
    
    [Parameter(Mandatory = $False)]
    $ProductCode = "",
    
    [Parameter(Mandatory = $False)]
    [ValidateSet("System","User")]
    $InstallExperience = "User",
    
    [Parameter(Mandatory = $False)]
    $AppPath = "%LocalAppData%\Programs\Microsoft VS Code\",
    
    [Parameter(Mandatory = $False)]
    $AppExecutable = "code.exe",

    $IconSource = "https://www.pngkit.com/png/detail/128-1285214_vscode-visual-studio-code.png"
    
)
    
$Win32Wrapper = "https://raw.githubusercontent.com/microsoft/Microsoft-Win32-Content-Prep-Tool/master/IntuneWinAppUtil.exe"

#Create subfolders for this package
$PackageOutputPath = Join-Path $PackageOutputPath $PackageId
$Path = Join-Path $Path $PackageId
$Global:AccessToken = Connect-MSIntuneGraph -TenantID $TenantName
#region Check if token has expired and if, request a new
Write-Host -ForegroundColor "Cyan" "Checking for existing authentication token for tenant: $TenantName."
If ($Null -ne $Global:AccessToken) {
    $UtcDateTime = (Get-Date).ToUniversalTime()
    [datetime]$Global:TokenExpires = [datetime]$Global:AccessToken.ExpiresOn.DateTime
    $TokenExpireMins = ($Global:TokenExpires - $UtcDateTime).Minutes
    Write-Warning -Message "Current authentication token expires in (minutes): $TokenExpireMins"

    If ($TokenExpireMins -le 2) {
        Write-Host -ForegroundColor "Cyan" "Existing token found but is or will soon expire, requesting a new token."
        
        $Global:AccessToken = Connect-MSIntuneGraph -TenantID $TenantName
        $UtcDateTime = (Get-Date).ToUniversalTime()
        [datetime]$Global:TokenExpires = [datetime]$Global:AccessToken.ExpiresOn.DateTime
        $TokenExpireMins = ($Global:TokenExpires - $UtcDateTime).Minutes
        Write-Warning -Message "Current authentication token expires in (minutes): $TokenExpireMins"
        #$Global:AccessToken = Get-MSIntuneAuthToken -TenantName $TenantName
    }
    else {
        Write-Verbose "Existing authentication token is okay."
    }        
}
else {
    Write-Host -ForegroundColor "Cyan" "Authentication token does not exist, requesting a new token."
    $Global:AccessToken = Connect-MSIntuneGraph -TenantID $TenantName
    #$Global:AccessToken = Get-MSIntuneAuthToken -TenantName $TenantName -PromptBehavior "Auto"
    
}
#endregion

    #region Variables
    Write-Host -ForegroundColor "Cyan" "Getting $PackageName updates via Winget."
    $ProgressPreference = "SilentlyContinue"
    $InformationPreference = "Continue"
    $PackageVersion = ""
    $Publisher = ""
    $PublisherUrl = ""
    $Description = ""
    $InformationURL = ""
    $PrivacyURL = ""
    $packageInfo = winget show $PackageId 
    foreach ($info in $packageInfo)
    {
        try{ 
            $key = ($info -split ": ")[0].Trim()
            $value = ($info -split ": ")[1].Trim()
        }
        catch{
            # just ignore the error
        }
        
        if ($key -eq "Version")
        {
            $PackageVersion = $value
            Write-Verbose "  PackageVersion = $PackageVersion"
        }
        if ($key -eq "Publisher")
        {
            $Publisher = $value
            Write-Verbose "  Publisher = $Publisher"
        }
        if ($key -eq "Publisher Url")
        {
            $PublisherUrl = $value
            Write-Verbose "  PublisherURL = $PublisherUrl"
        }
        if ($key -eq "Description")
        {
            $Description = $value
            Write-Verbose "  Description = $Description"
        }
        if ($key -eq "Homepage")
        {
            if($value -eq "")
            {
                $InformationURL = "https://bing.com/$packageName"
            }
            else{
                $InformationURL = $value
            }
            
            Write-Verbose "  InfomationUrl = $InformationUrl"
        }
        if ($key -eq "Privacy Url")
        {
            if ("" -eq $value) {
                $PrivacyURL = $InformationURL
        }
        else{
            $PrivacyURL = $value
        }
            
            Write-Verbose "  PrivacyUrl = $PrivacyUrl"
        }
        if ($key -eq "Download Url")
        {
            $DownloadUrl = $value
            Write-Verbose "  DownloadUrl = $DownloadUrl"
        }

    }
    
if ($PrivacyURL -eq "")
{
    $PrivacyURL = $InformationURL
    Write-Verbose "  PrivacyUrl = $PrivacyUrl"
}

    # Variables for the package
    $DisplayName = $PackageName ##+ " " + $PackageVersion

    Write-Output "`n  Creating Package: $DisplayName"
    $Executable = Split-Path -Path $DownloadUrl -Leaf

    $InstallCommandLine = ".\$Executable /verysilent /norestart /mergetasks='addcontextmenufiles,addcontextmenufolders,addtopath,associatewithfiles,!desktopicon,!quicklaunchicon,!runcode'"
    $UninstallCommandLine = ".\$Executable /uninstall /verysilent"
    #To_Automate region

#endregion
    Write-Host "    Checking to see if $PackageName $PackageVersion has already been created in MEM..."
    $existingPackages = Get-IntuneWin32App -DisplayName $PackageName | Where-Object {$_.DisplayVersion -eq $PackageVersion} | Select-Object -First 1

    if (-not $existingPackages -eq '')
    {
        Write-Host "        Package already exists, exiting process!"
        exit
    }
    else {
        Write-Host "        Package does not exist, creating package now!"
    }

    # Download installer with winget
    If ($PackageName) {
 
        # Test to make sure the paths we need are available.
        If ((Test-Path $path -ErrorAction SilentlyContinue) -ne $true)
        {
            $null = New-Item -Path $path -ErrorAction SilentlyContinue -ItemType Directory | Out-Null
        }

        If ((Test-Path $PackageOutputPath -ErrorAction SilentlyContinue) -ne $true)
        {
           $null =  New-Item -Path $PackageOutputPath -ErrorAction SilentlyContinue -ItemType Directory | Out-Null
        }

        # Create the package folder
        $PackagePath = Join-Path -Path $Path -ChildPath "Package"
        Write-Host -ForegroundColor "Cyan" "    Package path: $PackagePath"
        If (!(Test-Path -Path $PackagePath)) { New-Item -Path $PackagePath -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" > $Null }
        $PackageOutputPath = Join-Path -Path $PackageOutputPath -ChildPath "Output"
        Write-Host -ForegroundColor "Cyan" "    Output path: $PackageOutputPath"

        #region Download files and setup the package
   
        #region Package the app
        # Download the Package
        # TODO - Check the hash to make sure the file is valid
        Write-Verbose "  Executing: Join-Path -Path $Path -ChildPath (Split-Path -Path $PackagePath -Leaf)"
        $packageFile = Join-Path -Path $Path -ChildPath (Split-Path -Path $DownloadUrl -Leaf)
        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $packageFile -UseBasicParsing
        }
        catch [System.Exception] {
            Write-Error -Message "MEM Win32 Content Prep tool failed with: $($_.Exception.Message)"
            Break
        }

        #region Package the app
        # Download the Intune Win32 wrapper
        # TODO: Check if already available and skip download if it is.
        Write-Verbose "  Executing: Join-Path -Path $Path -ChildPath (Split-Path -Path $Win32Wrapper -Leaf)"
        $wrapperBin = Join-Path -Path $Path -ChildPath (Split-Path -Path $Win32Wrapper -Leaf)
        try {
            Invoke-WebRequest -Uri $Win32Wrapper -OutFile $wrapperBin -UseBasicParsing
        }
        catch [System.Exception] {
            Write-Error -Message "MEM Win32 Content Prep tool failed with: $($_.Exception.Message)"
            Break
        }

        # Create the package
        Write-Host -ForegroundColor "Cyan" " Package path: $(Split-Path -Path $packageFile -Parent)"
        Write-Host -ForegroundColor "Cyan" " Update path: $packageFile"
        $ArgList = "-c $(Split-Path -Path $packageFile -Parent) -s $packageFile -o $PackageOutputPath -q"
        Write-Host "  Argument list: $ArgList"

        try {
           
            $params = @{
                FilePath     = $wrapperBin
                ArgumentList = $ArgList
                Wait         = $True
                PassThru     = $True
                NoNewWindow  = $True
            }
            Write-Host " Executing: $process = Start-Process @params"
            $process = Start-Process @params
        }
        catch [System.Exception] {
            Write-Error -Message "Failed to create MEM package with: $($_.Exception.Message)"
            Break
        }
        try {
            $IntuneWinFile = Get-ChildItem -Path $PackageOutputPath -Filter "*.intunewin" -ErrorAction "SilentlyContinue" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        catch {
            Write-Error -Message "Failed to find an Intunewin package in $PackageOutputPath with: $($_.Exception.Message)"
            Break
        }
        Write-Host -ForegroundColor "Cyan" "Found package: $($IntuneWinFile.FullName)."
        #endregion


        #region Upload intunewin file and create the Intune app
        # Convert image file to icon
        $ImageFile = (Join-Path -Path $Path -ChildPath (Split-Path -Path $IconSource -Leaf))
        try {
            Invoke-WebRequest -Uri $IconSource -OutFile $ImageFile -UseBasicParsing
        }
        catch [System.Exception] {
            Write-Error -Message "Failed to download: $IconSource with: $($_.Exception.Message)"
            Break
        }
        If (Test-Path -Path $ImageFile) {
            $Icon = New-IntuneWin32AppIcon -FilePath $ImageFile
        }
        Else {
            Write-Error -Message "Cannot find the icon file."
            Break
        }

        $DetectionRules = @()
        # Create detection rule using the en-US MSI product code (1033 in the GUID below correlates to the lcid)
        if ($ProductCode -and $PackageVersion) {
            $params = @{
                ProductCode = $ProductCode
                #ProductVersionOperator = "greaterThanOrEqual"
                #ProductVersion         = $PackageVersion
            }
            $DetectionRule1 = New-IntuneWin32AppDetectionRuleMSI @params
            $DetectionRules += $DetectionRule1
        }
        else {
            Write-Host -ForegroundColor "Cyan" "ProductCode: $ProductCode."
            Write-Host -ForegroundColor "Cyan" "Version: $PackageVersion."
            Write-Warning -Message "Cannot create the detection rule - check ProductCode and version number."

        }

        If ($AppPath -and $AppExecutable) {
            $params = @{
                Version              = $True
                Path                 = $AppPath
                FileOrFolder         = $AppExecutable
                Check32BitOn64System = $False 
                Operator             = "greaterThanOrEqual"
                VersionValue         = $PackageVersion
            }
            $DetectionRule2 = New-IntuneWin32AppDetectionRuleFile @params
            $DetectionRules += $DetectionRule2
        }
        else {
            Write-Warning -Message "Cannot create the detection rule - check application path and executable."
            Write-Host -ForegroundColor "Cyan" "Path: $AppPath."
            Write-Host -ForegroundColor "Cyan" "Exe: $AppExecutable."

        }

        # If ($DetectionRule1 -and $DetectionRule2) {
        #     $DetectionRule = @($DetectionRule1, $DetectionRule2)
        # }
        # Else {
        #     Write-Error -Message "Failed to create the detection rule."
        #     Break
        # }
    
        # Create custom requirement rule
        $params = @{
            Architecture                    = "All"
            MinimumSupportedOperatingSystem = "1607"
        }
        $RequirementRule = New-IntuneWin32AppRequirementRule @params


        # Add new EXE Win32 app
        # Requires a connection via Connect-MSIntuneGraph first
        If ($PSBoundParameters.Keys.Contains("Upload")) {
            try {
                $params = @{
                    FilePath                 = $IntuneWinFile.FullName
                    DisplayName              = $DisplayName
                    Description              = $Description
                    Publisher                = $Publisher
                    InformationURL           = $InformationURL
                    PrivacyURL               = $PrivacyURL
                    CompanyPortalFeaturedApp = $false
                    InstallExperience        = $InstallExperience
                    RestartBehavior          = "suppress"
                    DetectionRule            = $DetectionRules
                    RequirementRule          = $RequirementRule
                    InstallCommandLine       = $InstallCommandLine
                    UninstallCommandLine     = $UninstallCommandLine
                    AppVersion               = $PackageVersion
                    Icon                     = $Icon
                    Verbose                  = $true
                }
                $params | Write-Output
                $null = Add-IntuneWin32App @params
            }
            catch [System.Exception] {
                Write-Error -Message "Failed to create application: $DisplayName with: $($_.Exception.Message)"
                Break
            }

            # Create an available assignment for all users
            <#
            If ($Null -ne $App) {
                try {
                    $params = @{
                        Id                           = $App.Id
                        Intent                       = "available"
                        Notification                 = "showAll"
                        DeliveryOptimizationPriority = "foreground"
                        #AvailableTime                = ""
                        #DeadlineTime                 = ""
                        #UseLocalTime                 = $true
                        #EnableRestartGracePeriod     = $true
                        #RestartGracePeriod           = 360
                        #RestartCountDownDisplay      = 20
                        #RestartNotificationSnooze    = 60
                        Verbose                      = $true
                    }
                    Add-IntuneWin32AppAssignmentAllUsers @params
                }
                catch [System.Exception] {
                    Write-Warning -Message "Failed to add assignment to $($App.displayName) with: $($_.Exception.Message)"
                    Break
                }
            }
            #>
        }
        Else {
            Write-Warning -Message "Parameter -Upload not specified. Skipping upload to MEM."
        }
        #endregion
    }
    Else {
        Write-Error -Message "Failed to retrieve $Package update package via Evergreen."
    }