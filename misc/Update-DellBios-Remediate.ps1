<#
.SYNOPSIS
Updates Bios on DELL machines by finding latest version avialble in Dell Command Update XML, Downloading and installing, then triggers a restart

Remediation & Detection Scripts are the same, just change the variable $Remediate. ($false = Detect | $true = Remediate)

Requirements: Dell Command Monitor Installed (Unless this is a pretty new model, then it might not need it, however I don't have new ones to test on, so I can't confirm)

Big thanks to the original developer: Gary Blok | @gwblok | recastsoftware.com
https://github.com/gwblok/garytown/blob/master/Intune/

I've updated a few things.
- Moved many things to be parameters instead of just variables.
- Updated CMtrace logging to streamline logging and screen output
- Removed default proxy server info and added a $UseProxy parameter that is $false by default.

#>

[CmdletBinding()]
param (
    [parameter()] $ScriptVersion = "21.4.7.1",
    $whoami = $env:USERNAME,
    $IntuneFolder = "$env:ProgramData\Intune",
    $LogFilePath = "$IntuneFolder\Logs",
    $LogFile = "$LogFilePath\Dell-Updates.log",
    $scriptName = "Dell BIOS Update - From Cloud",
    $SystemSKUNumber = (Get-CimInstance -ClassName Win32_ComputerSystem).SystemSKUNumber,
    $CabPath = "$env:temp\DellCabDownloads\DellSDPCatalogPC.cab",
    $CabPathIndex = "$env:temp\DellCabDownloads\CatalogIndexPC.cab",
    $CabPathIndexModel = "$env:temp\DellCabDownloads\CatalogIndexModel.cab",
    $DellCabExtractPath = "$env:temp\DellCabDownloads\DellCabExtract",
    $ProxyConnection = "null.null",
    $ProxyConnectionPort = "8080",
    $Remediate = $true,
    [bool]$UseProxy = $false,
    $ProxyServer,
    $BitsProxyList
)

$BIOS = Get-WmiObject -Class 'Win32_Bios'

if ($Remediate -eq $true)
{ $ComponentText = "MEM - Remediation" }
else { $ComponentText = "MEM - Detection" }

if (!(Test-Path -Path $LogFilePath)) { $null = New-Item -Path $LogFilePath -ItemType Directory -Force -ErrorAction SilentlyContinue }

function New-CMTraceLog {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        $Message,
 
        [Parameter(Mandatory = $false)]
        $ErrorMessage,
 
        [Parameter(Mandatory = $false)]
        $Component = $ComponentText,
 
        [Parameter(Mandatory = $false)]
        [int]$Type,
		
        [Parameter(Mandatory = $true)]
        $LogFile = "$env:ProgramData\Intune\Logs\CMLog.log"
    )

    <#
        Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
    #>
    $Time = Get-Date -Format "HH:mm:ss.ffffff"
    $Date = Get-Date -Format "MM-dd-yyyy"
 
    if ($null -ne $ErrorMessage) { $Type = 3 }
    if ($null -eq $Component) { $Component = " " }
    if ($null -eq $Type) { $Type = 1 }
 
    $LogMessage = "<![LOG[$Message $ErrorMessage" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile

    if ($Type -eq 1) {
        Write-Output $Message
    }
    elseif ($Type -eq 2) {
        Write-Warning $Message
    }
    elseif ($Type -eq 3) {
        Write-Error $Message
    }
    else {
        Write-Host $Message
    }
    
}

Function Restart-ByPassComputer {

    #Add Toast Notification

    #Assuming if Process "Explorer" Exist, that a user is logged on.
    $Session = Get-Process -Name "Explorer" -ErrorAction SilentlyContinue
    New-CMTraceLog -Message "User Session: $Session" -Type 1 -LogFile $LogFile
    Suspend-BitLocker -MountPoint $env:SystemDrive

    if ($Session -ne $null) {
        New-CMTraceLog -Message "User Session: $Session, Restarting in 60 minutes" -Type 1 -LogFile $LogFile
        Start-Process shutdown.exe -ArgumentList '/r /f /t 3600 /c "Your computer needs a BIOS update. Please save your work and restart otherwise your computer will restart in 60 minutes!"'
    }
    else {
        New-CMTraceLog -Message "No User Session Found, Restarting in 5 Seconds" -Type 1 -LogFile $LogFile
        Start-Process shutdown.exe -ArgumentList '/r /f /t 5 /c "Updating Bios, Computer will restart in 5 seconds"'
    }

}  

New-CMTraceLog -Message "---------------------------------" -Type 1 -LogFile $LogFile
New-CMTraceLog -Message "Starting $ScriptName, $ScriptVersion | Remediation Mode $Remediate" -Type 1 -LogFile $LogFile
New-CMTraceLog -Message "Running as $whoami" -Type 1 -LogFile $LogFile

# Test if proxy
if ($UseProxy) {

    if (((Test-NetConnection $ProxyConnection -Port $ProxyConnectionPort -ErrorAction SilentlyContinue).PingSucceeded -eq $true)) {
        Write-Output "Proxy server verified"
        [system.net.webrequest]::DefaultWebProxy = New-Object system.net.webproxy("$ProxyServer")
    }
    else {
        $UseProxy = $false
        $ProxyServer = $null
        $BitsProxyList = $null
        Write-Output "Proxy server not found"
    }
}

# Get Dell BIOS Info ##########################
try {

    if ($BIOS.SMBIOSBIOSVersion -match "A") {
        #Deal with Versions with A
        [String]$CurrentBIOSVersion = $BIOS.SMBIOSBIOSVersion
    }
    else {
        [System.Version]$CurrentBIOSVersion = $BIOS.SMBIOSBIOSVersion
    }   
}
catch { 
    $CurrentBIOSVersion = $null
    
}


# Pull down Dell XML CAB used in Dell Command Update ,extract and Load
if (!(Test-Path $DellCabExtractPath)) { $newfolder = New-Item -Path $DellCabExtractPath -ItemType Directory -Force }
Write-Host "Downloading Dell Cab" -ForegroundColor Yellow
Invoke-WebRequest -Uri "https://downloads.dell.com/catalog/CatalogIndexPC.cab" -OutFile $CabPathIndex -UseBasicParsing -Proxy $ProxyServer
[int32]$n = 1

while (!(Test-Path $CabPathIndex) -and $n -lt '3') {
    Invoke-WebRequest -Uri "https://downloads.dell.com/catalog/CatalogIndexPC.cab" -OutFile $CabPathIndex -UseBasicParsing -Proxy $ProxyServer
    $n++
}

if (Test-Path "$DellCabExtractPath\DellSDPCatalogPC.xml") { 
    Remove-Item -Path "$DellCabExtractPath\DellSDPCatalogPC.xml" -Force 
}

Start-Sleep -Seconds 1

if (Test-Path $DellCabExtractPath) { 
    Remove-Item -Path $DellCabExtractPath -Force -Recurse
}


$NewFolder = New-Item -Path $DellCabExtractPath -ItemType Directory

Write-Host "Expanding cab file..." -ForegroundColor Yellow
$Expand = expand $CabPathIndex $DellCabExtractPath\CatalogIndexPC.xml

Write-Host "Loading Dell Catalog XML..." -ForegroundColor Yellow
[xml]$XMLIndex = Get-Content "$DellCabExtractPath\CatalogIndexPC.xml"


#Dig through the XML to find model of this computer (Based on System SKU)
$XMLModel = $XMLIndex.ManifestIndex.GroupManifest | Where-Object { $_.SupportedSystems.Brand.Model.systemID -match $SystemSKUNumber }
if ($XMLModel) {
    New-CMTraceLog -Message "Downloaded Dell DCU XML, now looking for updates" -Type 1 -LogFile $LogFile
    Invoke-WebRequest -Uri "http://downloads.dell.com/$($XMLModel.ManifestInformation.path)" -OutFile $CabPathIndexModel -UseBasicParsing -Proxy $ProxyServer
    if (Test-Path $CabPathIndexModel) {
        $Expand = expand $CabPathIndexModel $DellCabExtractPath\CatalogIndexPCModel.xml
        [xml]$XMLIndexCAB = Get-Content "$DellCabExtractPath\CatalogIndexPCModel.xml"
        $DCUBIOSAvailable = $XMLIndexCAB.Manifest.SoftwareComponent | Where-Object { $_.ComponentType.value -eq "BIOS" }
        $DCUBIOSAvailableVersionsRAW = $DCUBIOSAvailable.dellversion

        if ($DCUBIOSAvailableVersionsRAW[0] -match "A") {
            [String[]]$DCUBIOSAvailableVersions = $DCUBIOSAvailableVersionsRAW
            $DCUBIOSLatestVersion = $DCUBIOSAvailableVersions | Sort-Object | Select-Object -Last 1
            $DCUBIOSLatest = $DCUBIOSAvailable | Where-Object { $_.dellversion -eq $DCUBIOSLatestVersion }
            [String]$DCUBIOSVersion = $DCUBIOSLatest.dellVersion
        }

        if ($DCUBIOSAvailableVersionsRAW[0] -ne $null -and $DCUBIOSAvailableVersionsRAW[0] -ne "" -and $DCUBIOSAvailableVersionsRAW[0] -notmatch "A") {
            [System.Version[]]$DCUBIOSAvailableVersions = $DCUBIOSAvailableVersionsRAW
            $DCUBIOSLatestVersion = $DCUBIOSAvailableVersions | Sort-Object | Select-Object -Last 1
            $DCUBIOSLatest = $DCUBIOSAvailable | Where-Object { $_.dellversion -eq $DCUBIOSLatestVersion }
            [System.Version]$DCUBIOSVersion = $DCUBIOSLatest.dellVersion
        }              
                
        $DCUBIOSLatestVersion = $DCUBIOSAvailableVersions | Sort-Object | Select-Object -Last 1
        $DCUBIOSN1Version = $DCUBIOSAvailableVersions | Sort-Object | Select-Object -Last 2 | Select-Object -First 1
        $DCUBIOSLatest = $DCUBIOSAvailable | Where-Object { $_.dellversion -eq $DCUBIOSLatestVersion }
        $DCUBIOSVersion = $DCUBIOSLatest.dellVersion
        $DCUBIOSReleaseDate = $(Get-Date $DCUBIOSLatest.releaseDate -Format 'yyyy-MM-dd')               
        $TargetLink = "http://downloads.dell.com/$($DCUBIOSLatest.path)"
        $TargetFileName = ($DCUBIOSLatest.path).Split("/") | Select-Object -Last 1

        if ($DCUBIOSVersion -gt $CurrentBIOSVersion) {
            
            if ($Remediate -eq $true) {
                New-CMTraceLog -Message "New BIOS Update available: Installed = $CurrentBIOSVersion DCU = $DCUBIOSVersion" -Type 1 -LogFile $LogFile
                New-CMTraceLog -Message "  Title: $($DCUBIOSLatest.Name.Display.'#cdata-section')" -Type 1 -LogFile $LogFile
                New-CMTraceLog -Message "  ----------------------------" -Type 1 -LogFile $LogFile
                New-CMTraceLog -Message "   Severity: $($DCUBIOSLatest.Criticality.Display.'#cdata-section')" -Type 1 -LogFile $LogFile
                New-CMTraceLog -Message "   FileName: $TargetFileName" -Type 1 -LogFile $LogFile
                New-CMTraceLog -Message "   BIOS Release Date: $DCUBIOSReleaseDate" -Type 1 -LogFile $LogFile
                New-CMTraceLog -Message "   KB: $($DCUBIOSLatest.releaseID)" -Type 1 -LogFile $LogFile
                New-CMTraceLog -Message "   Link: $TargetLink" -Type 1 -LogFile $LogFile
                New-CMTraceLog -Message "   Info: $($DCUBIOSLatest.ImportantInfo.URL)" -Type 1 -LogFile $LogFile
                New-CMTraceLog -Message "   BIOS Version: $DCUBIOSVersion " -Type 1 -LogFile $LogFile

                # Build info to download and update CM package
                $TargetFilePathName = "$($DellCabExtractPath)\$($TargetFileName)"
                New-CMTraceLog -Message "   Running Command: Invoke-WebRequest -Uri $TargetLink -OutFile $TargetFilePathName -UseBasicParsing -Proxy $ProxyServer " -Type 1 -LogFile $LogFile
                Invoke-WebRequest -Uri $TargetLink -OutFile $TargetFilePathName -UseBasicParsing -Proxy $ProxyServer

                #Confirm Download
                if (Test-Path $TargetFilePathName) {
                    New-CMTraceLog -Message "   Download Complete " -Type 1 -LogFile $LogFile
                    if ((Get-BitLockerVolume -MountPoint $env:SystemDrive).ProtectionStatus -eq "On" ) {
                        New-CMTraceLog -Message "Bitlocker Status: On - Suspending before Update" -Type 1 -LogFile $LogFile
                        Suspend-BitLocker -MountPoint $env:SystemDrive -Force
                        Start-Sleep 5

                        if ((Get-BitLockerVolume -MountPoint $env:SystemDrive).ProtectionStatus -eq "On" ) {
                            New-CMTraceLog -Message "Unable to suspend Bitlocker, exiting update process!" -Type 1 -LogFile $LogFile
                            exit 1
                        }
                        else {
                            New-CMTraceLog -Message "Bitlocker Status: Off" -Type 1 -LogFile $LogFile
                        }
                    }
                    else {
                        New-CMTraceLog -Message "Bitlocker Status: Off" -Type 1 -LogFile $LogFile
                    }                  
                    $BiosLogFileName = $TargetFilePathName.replace(".exe", ".log")
                    $BiosArguments = "/s /l=$BiosLogFileName"
                    Write-Output "Starting BIOS Update"

                    New-CMTraceLog -Message " Running Command: Start-Process $TargetFilePathName $BiosArguments -Wait -PassThru " -Type 1 -LogFile $LogFile
                    $Process = Start-Process "$TargetFilePathName" $BiosArguments -Wait -PassThru
                    New-CMTraceLog -Message " Update Complete with Exitcode: $($Process.ExitCode)" -Type 1 -LogFile $LogFile
                    
                    if ($Process -ne $null -and $Process.ExitCode -eq '2') {
                        Restart-ByPassComputer
                    }
                }
                else {
                    New-CMTraceLog -Message " Failed to download BIOS update!" -Type 3 -LogFile $LogFile
                    exit 1
                }
            }
            else {
                # Needs Remediation
                New-CMTraceLog -Message "New BIOS Update available: Installed = $CurrentBIOSVersion DCU = $DCUBIOSVersion | Remediation Required" -Type 1 -LogFile $LogFile
                exit 1
            }
            
        }
        else {
            #Compliant
            New-CMTraceLog -Message " BIOS in DCU XML same as BIOS in CM: $CurrentBIOSVersion" -Type 1 -LogFile $LogFile
            exit 0
        }
    }
    else {
        #No Cab with XML was able to download
        New-CMTraceLog -Message "No cab file available for this computer model" -Type 2 -LogFile $LogFile
    }
}
else {
    #No Match in the DCU XML for this Model (SKUNumber)
    New-CMTraceLog -Message "No Match in XML for $SystemSKUNumber" -Type 2 -LogFile $LogFile
}    
