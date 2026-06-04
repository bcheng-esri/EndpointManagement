<#
.SYNOPSIS
	This script is used to install the Esri SCCM client.

.DESCRIPTION
	This script will check if the device is on the internal or internet network.

.NOTES
	Created on:   2024-03-04
	Modified:     2026-06-04
	Author:       Brian Cheng
	Version:      2.0

	Changelog:
	----------
	2024-03-04 - v1.0 - The Creation date of this script
	2026-06-04 - v2.0 - Added verification checks for domain join and vaid ConfigMgr computer certificate
					  - Added download and copy of ccmsetup.exe from internet and local SCCM servers
					  - Obfuscated sensitive information

#>
$ProgressPreference = 'SilentlyContinue'
write-host ""
write-host ""
write-host ""
write-host ""
write-host ""
write-host ""
write-host ""
write-host ""

#Execute script as administrator
Write-Host "=== Checking if script executed as administrator ==="
function Test-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
    Write-Warning "  ⚠️ This script must be run as Administrator. Aborting."
	write-host ""
    pause
	exit
} else {
    Write-Host "  Script elevated" -ForegroundColor DarkGray
}

#Verifying existing SCCM client
$procCCMExec = Get-Process -Name ccmexec -ErrorAction SilentlyContinue
write-host "=== Verifying SCCM client is already installed: ==="
If ($procCCMExec -ne $null) {
    write-host "  SCCM client is already installed on this device" -ForegroundColor Red
    write-host "  Exiting script" -ForegroundColor Red
    write-host ""
    pause
    exit
} Else {
    write-host "  SCCM client is not installed, continuing script" -ForegroundColor Green
}

#Verifying the computer is joined to Esri.com or UC.esri.com domain
$domain = (gwmi win32_computersystem).domain
write-host "=== Verifying domain join: ==="
if (($domain -eq "esri.com") -or ($domain -eq "uc.esri.com")) {
    write-host "  Device is joined to $domain" -ForegroundColor Green
} else {
    write-host "  Device is NOT joined to esri.com nor uc.esri.com!" -ForegroundColor Red
	write-host "  Exiting script" -ForegroundColor Red
    write-host ""
    pause
    exit
}

#Verifying the computer has a ConfigMgr certificate enrolled
$templateName = 'ConfigMgr Client Certificate'
$sccmcert = Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object{ $_.Extensions | Where-Object{ ($_.Oid.FriendlyName -eq 'Certificate Template Information') -and ($_.Format(0) -match $templateName) }}
write-host "=== Verifying ConfigMgr certificate: ==="
if ($sccmcert -ne $null) {
    if ($sccmcert.NotAfter -gt (Get-Date)) {
        write-host "  Device has a valid ConfigMgr computer certificate" -ForegroundColor Green
    } else {
        $sccmcertdate = $sccmcert.NotAfter
        write-host "  Device has a ConfigMgr computer certificate BUT the certificate is expired! ($sccmcertdate)" -ForegroundColor Red
    }
} else {
    write-host "  Device does NOT have the correct computer certificate!" -ForegroundColor Red
    write-host "  Please run certlm.msc and ensure the correct certificate is enrolled" -ForegroundColor Red
	write-host "  Exiting script" -ForegroundColor Red
    write-host ""
    pause
    exit
}

#Verifying the computer has access to SCCM servers
$CMGServer = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("ZXNyaWNtZy5lc3JpLmNvbQ=="))
$SCCMServer = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("cmVkLWluZi1zY2NtLXAyLmVzcmkuY29t"))
write-host "=== Verifying access to Cloud Management Gateway or internal SCCM server: ==="
$CMGServerConnection = Test-NetConnection -ComputerName $CMGServer -Port 443 -InformationLevel quiet
$SCCMServerConnection = Test-NetConnection -ComputerName $SCCMServer -Port 443 -InformationLevel quiet
write-host "  Device access to CMG is $CMGServerConnection"
write-host "  Device access to SCCM server is $SCCMServerConnection"

If ($CMGServerConnection -eq $true) {
	#Verifying ccmsetup.exe is in ccmsetup folder
	$targetFolder = "$env:windir\ccmsetup"
	$targetFile = Join-Path $targetFolder "ccmsetup.exe"
	$sourceUrl = "https://github.com/bcheng-esri/EndpointManagement/raw/refs/heads/main/files/ccmsetup.exe"
    write-host "=== Verifying ccmsetup.exe exists: ==="
	# Check if the file exists, if not, download it
	if (-not (Test-Path -Path $targetFile)) {
		Write-Host "  ccmsetup.exe is missing. Attempting to download..." -ForegroundColor Yellow
		# Ensure the folder exists
		if (-not (Test-Path -Path $targetFolder)) {
			New-Item -ItemType Directory -Path $targetFolder | Out-Null
		}
		try {
			# Download the file
			Invoke-WebRequest -Uri $sourceUrl -OutFile $targetFile -ErrorAction Stop
			Write-Host "  Download complete. File saved to $targetFile" -ForegroundColor Green
		} catch {
			Write-Host "  Failed to download ccmsetup.exe from $sourceUrl. Please verify the URL and network connectivity." -ForegroundColor Red
			Write-Host "  Exiting script" -ForegroundColor Red
			Write-Host ""
			pause
			exit
		}
	} else {
		Write-Host "  ccmsetup.exe already exists in $env:windir\ccmsetup. No action taken." -ForegroundColor Cyan
	}
    write-host "=== Device has internet access. Using Cloud Management Gateway for install ==="
    $b64Args1 = "L25vY3JsY2hlY2sgL21wOmh0dHBzOi8vRVNSSUNNRy5FU1JJLkNPTS9DQ01fUHJveHlfTXV0dWFsQXV0aC83MjA1NzU5NDAzNzkyNzkzNyBDQ01IT1NUTkFNRT1FU1JJQ01HLkVTUkkuQ09NL0NDTV9Qcm94eV9NdXR1YWxBdXRoLzcyMDU3NTk0MDM3OTI3OTM3IFNNU1NpdGVDb2RlPVJFRA=="
    $decodedArgs1 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Args1))
    Start-Process "$targetFolder\ccmsetup.exe" -ArgumentList $decodedArgs1 -Wait
    do {
	Start-Sleep 10
	Write-host "=== Installing SCCM client over internet... ==="
	$procCCMSetup = Get-Process -Name ccmsetup -ErrorAction SilentlyContinue
	Start-Sleep 10
	}
	until ($procCCMSetup -eq $null)
    Write-host -fore green "SCCM client install is successful."
} ElseIf ($SCCMServerConnection -eq $true) {
	#Verifying ccmsetup.exe is in ccmsetup folder
	$targetFolder = "$env:windir\ccmsetup"
	$targetFile = Join-Path $targetFolder "ccmsetup.exe"
	$sourceUrl = "\\esri.com\software\Desktop\DesktopM-Z\Microsoft\SCCM\ccmsetup.exe"
    write-host "=== Verifying ccmsetup.exe exists: ==="
	#Check if the file exists, if not, download it
	if (-not (Test-Path -Path $targetFile)) {
		Write-Host "  ccmsetup.exe is missing. Attempting to copy..." -ForegroundColor Yellow
		# Ensure the folder exists
		if (-not (Test-Path -Path $targetFolder)) {
			New-Item -ItemType Directory -Path $targetFolder | Out-Null
		}
		try {
			# Copy the file
			Copy-Item -Path $sourceUrl -Destination $targetFolder -ErrorAction Stop
			Write-Host "  Copy complete. File saved to $targetFile" -ForegroundColor Green
		} catch {
			Write-Host "  Failed to copy ccmsetup.exe from $sourceUrl. Please verify the source and network connectivity." -ForegroundColor Red
			Write-Host "  Exiting script" -ForegroundColor Red
			Write-Host ""
			pause
			exit
		}
	} else {
		Write-Host "  ccmsetup.exe already exists in $env:windir\ccmsetup. No action taken." -ForegroundColor Cyan
	}
    write-host "=== Device is on internal network only. Using internal management point for install ==="
    $b64Args2 = "U01TU0lURUNPREU9UkVEIEZTUD1yZWQtaW5mLWNtZHAtcDEuZXNyaS5jb20gQ0NNRklSU1RDRVJUPTEgQ0NNQ0VSVFNUT1JFPU1ZIFNNU01QPWh0dHBzOi8vcmVkLWluZi1zY2NtLXAyLmVzcmkuY29tIC9NUDpodHRwczovL3JlZC1pbmYtc2NjbS1wMi5lc3JpLmNvbSAvVXNlUEtJQ2VydA=="
    $decodedArgs2 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Args2))
    Start-Process "$targetFolder\ccmsetup.exe" -ArgumentList $decodedArgs2 -Wait
    do {
	Start-Sleep 10
	Write-host "  Installing SCCM client..."
	$procCCMSetup = Get-Process -Name ccmsetup -ErrorAction SilentlyContinue
	Start-Sleep 10
	}
	until ($procCCMSetup -eq $null)
    Write-host "=== SCCM client install is successful." -ForegroundColor Green
} Else {
    write-host "=== Device cannot connect to neither the CMG nor internal servers. Please check the network connection! ===" -ForegroundColor Red
}
write-host ""
write-host ""

pause



