<#
.SYNOPSIS
	This script is used to install the Esri SCCM client.

.DESCRIPTION
	This script will check if the device is on the internal or internet network.

.NOTES
	Created on:   2024-03-04
	Modified:     2026-06-04
	Author:       Brian Cheng
	Version:      2.1

	Changelog:
	----------
	2024-03-04 - v1.0 - The Creation date of this script
	2026-06-04 - v2.0 - Added verification checks for domain join and vaid ConfigMgr computer certificate
					  - Added download and copy of ccmsetup.exe from internet and local SCCM servers
					  - Obfuscated sensitive information
	2026-06-04 - v2.1 - Added comprehensive logging to file and console

#>
$ProgressPreference = 'SilentlyContinue'
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""

# -- Check script execution elevation --
Write-Host "=== Checking if script executed as administrator ==="
function Test-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
    Write-Warning "  This script must be run as Administrator. Aborting."
	Write-Host ""
    pause
	exit
} else {
    Write-Host "  Script elevated"
}

# -- Logging Setup --
$LogFile = "$env:SystemRoot\Temp\Install-SCCMClient_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
if (!(Test-Path "$env:SystemRoot\Temp")) {
    New-Item -Path "$env:SystemRoot\Temp" -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    switch ($Level) {
        "ERROR"   { Write-Host $entry -ForegroundColor Red }
        "WARN"    { Write-Host $entry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
        default   { Write-Host $entry -ForegroundColor Cyan }
    }
    Add-Content -Path $LogFile -Value $entry
}
Write-Log "Script started" -Level "INFO"
Write-Log "Log file: $LogFile" -Level "INFO"

# -- Verifying existing SCCM client --
$procCCMExec = Get-Process -Name ccmexec -ErrorAction SilentlyContinue
Write-Log "=== Verifying SCCM client is already installed: ===" -Level "INFO"
If ($procCCMExec -ne $null) {
    Write-Log "  SCCM client is already installed on this device" -Level "WARN"
    Write-Log "  Exiting script" -Level "WARN"
    Write-Host ""
    pause
    exit
} Else {
    Write-Log "  SCCM client is not installed, continuing script" -Level "SUCCESS"
}

# -- Verifying the computer is joined to Esri.com or UC.esri.com domain --
$domain = (gwmi win32_computersystem).domain
Write-Log "=== Verifying domain join: ===" -Level "INFO"
if (($domain -eq "esri.com") -or ($domain -eq "uc.esri.com")) {
    Write-Log "  Device is joined to $domain" -Level "SUCCESS"
} else {
    Write-Log "  Device is NOT joined to esri.com nor uc.esri.com!" -Level "ERROR"
	Write-Log "  Exiting script" -Level "ERROR"
    Write-Host ""
    pause
    exit
}

# -- Verifying the computer has a ConfigMgr certificate enrolled --
$templateName = 'ConfigMgr Client Certificate'
$sccmcert = Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object{ $_.Extensions | Where-Object{ ($_.Oid.FriendlyName -eq 'Certificate Template Information') -and ($_.Format(0) -match $templateName) }}
Write-Log "=== Verifying ConfigMgr certificate: ===" -Level "INFO"
if ($sccmcert -ne $null) {
    if ($sccmcert.NotAfter -gt (Get-Date)) {
        Write-Log "  Device has a valid ConfigMgr computer certificate" -Level "SUCCESS"
    } else {
        $sccmcertdate = $sccmcert.NotAfter
        Write-Log "  Device has a ConfigMgr computer certificate BUT the certificate is expired! ($sccmcertdate)" -Level "ERROR"
    }
} else {
    Write-Log "  Device does NOT have the correct computer certificate!" -Level "ERROR"
    Write-Log "  Please run certlm.msc and ensure the correct certificate is enrolled" -Level "ERROR"
	Write-Log "  Exiting script" -Level "ERROR"
    Write-Host ""
    pause
    exit
}

# -- Verifying the computer has access to SCCM servers --
$CMGServer = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("ZXNyaWNtZy5lc3JpLmNvbQ=="))
$SCCMServer = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("cmVkLWluZi1zY2NtLXAyLmVzcmkuY29t"))
Write-Log "=== Verifying access to Cloud Management Gateway or internal SCCM server: ===" -Level "INFO"
$CMGServerConnection = Test-NetConnection -ComputerName $CMGServer -Port 443 -InformationLevel quiet
$SCCMServerConnection = Test-NetConnection -ComputerName $SCCMServer -Port 443 -InformationLevel quiet
Write-Log "  Device access to CMG is $CMGServerConnection" -Level "INFO"
Write-Log "  Device access to SCCM server is $SCCMServerConnection" -Level "INFO"

If ($CMGServerConnection -eq $true) {
	# Verifying ccmsetup.exe is in ccmsetup folder
	$targetFolder = "$env:windir\ccmsetup"
	$targetFile = Join-Path $targetFolder "ccmsetup.exe"
	$sourceUrl = "https://github.com/bcheng-esri/EndpointManagement/raw/refs/heads/main/files/ccmsetup.exe"
    Write-Log "=== Verifying ccmsetup.exe exists: ===" -Level "INFO"
	# Check if the file exists, if not, download it
	if (-not (Test-Path -Path $targetFile)) {
		Write-Log "  ccmsetup.exe is missing. Attempting to download..." -Level "WARN"
		# Ensure the folder exists
		if (-not (Test-Path -Path $targetFolder)) {
			New-Item -ItemType Directory -Path $targetFolder | Out-Null
		}
		try {
			# Download the file
			Invoke-WebRequest -Uri $sourceUrl -OutFile $targetFile -ErrorAction Stop
			Write-Log "  Download complete. File saved to $targetFile" -Level "SUCCESS"
		} catch {
			Write-Log "  Failed to download ccmsetup.exe from $sourceUrl. Please verify the URL and network connectivity." -Level "ERROR"
			Write-Log "  Error details: $_" -Level "ERROR"
			Write-Log "  Exiting script" -Level "ERROR"
			Write-Host ""
			pause
			exit
		}
	} else {
		Write-Log "  ccmsetup.exe already exists in $env:windir\ccmsetup. No action taken." -Level "INFO"
	}
    Write-Log "=== Device has internet access. Using Cloud Management Gateway for install ===" -Level "INFO"
    $b64Args1 = "L25vY3JsY2hlY2sgL21wOmh0dHBzOi8vRVNSSUNNRy5FU1JJLkNPTS9DQ01fUHJveHlfTXV0dWFsQXV0aC83MjA1NzU5NDAzNzkyNzkzNyBDQ01IT1NUTkFNRT1FU1JJQ01HLkVTUkkuQ09NL0NDTV9Qcm94eV9NdXR1YWxBdXRoLzcyMDU3NTk0MDM3OTI3OTM3IFNNU1NpdGVDb2RlPVJFRA=="
    $decodedArgs1 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Args1))
    Write-Log "  Starting ccmsetup.exe with CMG parameters..." -Level "INFO"
    Start-Process "$targetFolder\ccmsetup.exe" -ArgumentList $decodedArgs1 -Wait
    do {
	Start-Sleep 10
	Write-Log "=== Installing SCCM client over internet... ===" -Level "INFO"
	$procCCMSetup = Get-Process -Name ccmsetup -ErrorAction SilentlyContinue
	Start-Sleep 10
	}
	until ($procCCMSetup -eq $null)
} ElseIf ($SCCMServerConnection -eq $true) {
	# Verifying ccmsetup.exe is in ccmsetup folder
	$targetFolder = "$env:windir\ccmsetup"
	$targetFile = Join-Path $targetFolder "ccmsetup.exe"
	$sourceUrl = "\\esri.com\software\Desktop\DesktopM-Z\Microsoft\SCCM\ccmsetup.exe"
    Write-Log "=== Verifying ccmsetup.exe exists: ===" -Level "INFO"
	# Check if the file exists, if not, download it
	if (-not (Test-Path -Path $targetFile)) {
		Write-Log "  ccmsetup.exe is missing. Attempting to copy..." -Level "WARN"
		# Ensure the folder exists
		if (-not (Test-Path -Path $targetFolder)) {
			New-Item -ItemType Directory -Path $targetFolder | Out-Null
		}
		try {
			# Copy the file
			Copy-Item -Path $sourceUrl -Destination $targetFolder -ErrorAction Stop
			Write-Log "  Copy complete. File saved to $targetFile" -Level "SUCCESS"
		} catch {
			Write-Log "  Failed to copy ccmsetup.exe from $sourceUrl. Please verify the source and network connectivity." -Level "ERROR"
			Write-Log "  Error details: $_" -Level "ERROR"
			Write-Log "  Exiting script" -Level "ERROR"
			Write-Host ""
			pause
			exit
		}
	} else {
		Write-Log "  ccmsetup.exe already exists in $env:windir\ccmsetup. No action taken." -Level "INFO"
	}
    Write-Log "=== Device is on internal network only. Using internal management point for install ===" -Level "INFO"
    $b64Args2 = "U01TU0lURUNPREU9UkVEIEZTUD1yZWQtaW5mLWNtZHAtcDEuZXNyaS5jb20gQ0NNRklSU1RDRVJUPTEgQ0NNQ0VSVFNUT1JFPU1ZIFNNU01QPWh0dHBzOi8vcmVkLWluZi1zY2NtLXAyLmVzcmkuY29tIC9NUDpodHRwczovL3JlZC1pbmYtc2NjbS1wMi5lc3JpLmNvbSAvVXNlUEtJQ2VydA=="
    $decodedArgs2 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Args2))
    Write-Log "  Starting ccmsetup.exe with internal MP parameters..." -Level "INFO"
    Start-Process "$targetFolder\ccmsetup.exe" -ArgumentList $decodedArgs2 -Wait
    do {
	Start-Sleep 10
	Write-Log "  Installing SCCM client..." -Level "INFO"
	$procCCMSetup = Get-Process -Name ccmsetup -ErrorAction SilentlyContinue
	Start-Sleep 10
	}
	until ($procCCMSetup -eq $null)
} Else {
    Write-Log "=== Device cannot connect to neither the CMG nor internal servers. Please check the network connection! ===" -Level "ERROR"
}

# -- Retrieving the ccmsetup result from log file --
$ccmsetupLogFile = "$env:windir\ccmsetup\logs\ccmsetup.log"
# Check if the file exists
if (Test-Path -Path $ccmsetupLogFile) {
	# Read the file and find the last line matching either pattern
	$matchLine = Get-Content -Path $ccmsetupLogFile | Where-Object {
		$_ -match "CcmSetup failed" -or $_ -match "CcmSetup is exiting"
	} | Select-Object -Last 1
	if ($matchLine) {
		# Extract the readable message from SCCM log format
		if ($matchLine -match '<!\[LOG\[(.*?)\]LOG\]') {
			$message = $Matches[1]
		} else {
			$message = $matchLine
		}
		# Determine the status based on the message content
		if ($message -eq "CcmSetup is exiting with return code 0") {
			$color = "SUCCESS"
		} elseif ($message -match "CcmSetup failed") {
			$color = "ERROR"
		} else {
			$color = "WARN"
		}
		Write-Log "  CCMSetup result:" -Level "INFO"
		Write-Log (" ", $message) -Level $color
	} else {
		Write-Log "  No lines matching 'CcmSetup failed' or 'CcmSetup is exiting' were found." -Level "WARN"
	}
} else {
	Write-Log "  Log file not found: $ccmsetupLogFile" -Level "ERROR"
}

Write-Log "Script completed" -Level "INFO"
Write-Host ""
Write-Host ""
pause
