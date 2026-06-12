<#
.SYNOPSIS
    Resets all Windows Update components to their default state.

.DESCRIPTION
    This script performs a complete reset of Windows Update:
      1. Stops Windows Update-related services
      2. Removes BITS jobs
      3. Backs up and clears SoftwareDistribution and catroot2 folders
      4. Resets BITS and Windows Update service security descriptors
      5. Re-registers Windows Update DLLs
      6. Resets Winsock and proxy settings
      7. Restarts all services
      8. Forces a new update detection cycle

.NOTES
    Author  : Brian Cheng
    Date    : 2026-06-04

#>
# -- Execute script as administrator --
Write-Host "==== Checking if script executed as administrator ===="
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
    Write-Host "  Script elevated" -ForegroundColor DarkGray
}

# -- Logging Setup --
$LogFile = "$env:SystemRoot\Temp\Reset-WindowsUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

Write-Log "===== Windows Update Reset Script Started ====="
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "OS: $((Get-CimInstance Win32_OperatingSystem).Caption)"

# -- Step 1: Stop Windows Update Services --
Write-Log "Step 1: Stopping Windows Update services..."

$services = @(
    "wuauserv",        # Windows Update
    "bits",            # Background Intelligent Transfer Service
    "appidsvc",        # Application Identity
    "cryptsvc",        # Cryptographic Services
    "msiserver",       # Windows Installer
    "dosvc",           # Delivery Optimization
    "usosvc"           # Update Orchestrator Service
)

foreach ($svc in $services) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        try {
            Stop-Service -Name $svc -Force -ErrorAction Stop
            Write-Log "Stopped service: $svc ($($service.DisplayName))" -Level "SUCCESS"
        }
        catch {
            Write-Log "Could not stop $svc -- attempting force kill" -Level "WARN"
            $proc = Get-CimInstance Win32_Service -Filter "Name='$svc'" -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessId -gt 0) {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                Write-Log "Force-killed process for: $svc" -Level "WARN"
            }
        }
    }
    else {
        Write-Log "Service not found (skipped): $svc"
    }
}

# -- Step 2: Clear BITS Queue --
Write-Log "Step 2: Clearing BITS job queue..."

try {
    Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | Remove-BitsTransfer -ErrorAction SilentlyContinue
    Write-Log "BITS queue cleared." -Level "SUCCESS"
}
catch {
    Write-Log "Could not clear BITS queue -- $_" -Level "WARN"
}

# -- Step 3: Backup and Remove SoftwareDistribution and catroot2 --
Write-Log "Step 3: Backing up and removing update cache folders..."

$foldersToReset = @(
    @{ Path = "$env:SystemRoot\SoftwareDistribution";           Backup = "$env:SystemRoot\SoftwareDistribution.bak" },
    @{ Path = "$env:SystemRoot\System32\catroot2";              Backup = "$env:SystemRoot\System32\catroot2.bak" },
    @{ Path = "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader"; Backup = "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader.bak" }
)

foreach ($item in $foldersToReset) {
    $sourcePath = $item.Path
    $backupPath = $item.Backup

    if (Test-Path $sourcePath) {
        # Remove any previous backup
        if (Test-Path $backupPath) {
            try {
                Remove-Item -Path $backupPath -Recurse -Force -ErrorAction Stop
                Write-Log "Removed old backup: $backupPath"
            }
            catch {
                Write-Log "Could not remove old backup $backupPath -- $_" -Level "WARN"
            }
        }
        # Rename current folder as backup
        try {
            Rename-Item -Path $sourcePath -NewName (Split-Path $backupPath -Leaf) -Force -ErrorAction Stop
            Write-Log "Backed up: $sourcePath -> $backupPath" -Level "SUCCESS"
        }
        catch {
            Write-Log "Could not rename $sourcePath -- attempting delete" -Level "WARN"
            try {
                Remove-Item -Path $sourcePath -Recurse -Force -ErrorAction Stop
                Write-Log "Deleted: $sourcePath" -Level "SUCCESS"
            }
            catch {
                Write-Log "Failed to delete $sourcePath -- $_ (may need reboot)" -Level "ERROR"
            }
        }
    }
    else {
        Write-Log "Folder not found (skipped): $sourcePath"
    }
}

# -- Step 4: Remove Windows Update Log --
Write-Log "Step 4: Clearing Windows Update log..."

$wuLog = "$env:SystemRoot\WindowsUpdate.log"
if (Test-Path $wuLog) {
    try {
        Remove-Item -Path $wuLog -Force -ErrorAction Stop
        Write-Log "Deleted: $wuLog" -Level "SUCCESS"
    }
    catch {
        Write-Log "Could not delete $wuLog -- $_" -Level "WARN"
    }
}
else {
    Write-Log "WindowsUpdate.log not found (skipped)."
}

# -- Step 5: Reset BITS and WU Service Security Descriptors --
Write-Log "Step 5: Resetting service security descriptors..."

try {
    sc.exe sdset bits "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)" | Out-Null
    Write-Log "Reset BITS security descriptor." -Level "SUCCESS"
}
catch {
    Write-Log "Failed to reset BITS security descriptor -- $_" -Level "WARN"
}

try {
    sc.exe sdset wuauserv "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)" | Out-Null
    Write-Log "Reset Windows Update security descriptor." -Level "SUCCESS"
}
catch {
    Write-Log "Failed to reset Windows Update security descriptor -- $_" -Level "WARN"
}

# -- Step 6: Re-register Windows Update DLLs --
Write-Log "Step 6: Re-registering Windows Update DLLs..."

$dlls = @(
    "atl.dll",
    "urlmon.dll",
    "mshtml.dll",
    "shdocvw.dll",
    "browseui.dll",
    "jscript.dll",
    "vbscript.dll",
    "scrrun.dll",
    "msxml.dll",
    "msxml3.dll",
    "msxml6.dll",
    "actxprxy.dll",
    "softpub.dll",
    "wintrust.dll",
    "dssenh.dll",
    "rsaenh.dll",
    "gpkcsp.dll",
    "sccbase.dll",
    "slbcsp.dll",
    "cryptdlg.dll",
    "oleaut32.dll",
    "ole32.dll",
    "shell32.dll",
    "initpki.dll",
    "wuapi.dll",
    "wuaueng.dll",
    "wuaueng1.dll",
    "wucltui.dll",
    "wups.dll",
    "wups2.dll",
    "wuweb.dll",
    "qmgr.dll",
    "qmgrprxy.dll",
    "wucltux.dll",
    "muweb.dll",
    "wuwebv.dll",
    "wudriver.dll"
)

$registered = 0
$skipped = 0

foreach ($dll in $dlls) {
    $dllPath = "$env:SystemRoot\System32\$dll"
    if (Test-Path $dllPath) {
        $result = regsvr32.exe /s $dllPath 2>&1
        $registered++
    }
    else {
        $skipped++
    }
}

Write-Log "Re-registered $registered DLLs, skipped $skipped (not found)." -Level "SUCCESS"

# -- Step 7: Reset Winsock and Network Settings --
Write-Log "Step 7: Resetting Winsock and network settings..."

try {
    netsh winsock reset 2>&1 | Out-Null
    Write-Log "Winsock reset complete." -Level "SUCCESS"
}
catch {
    Write-Log "Winsock reset failed -- $_" -Level "WARN"
}

try {
    netsh winhttp reset proxy 2>&1 | Out-Null
    Write-Log "WinHTTP proxy reset complete." -Level "SUCCESS"
}
catch {
    Write-Log "WinHTTP proxy reset failed -- $_" -Level "WARN"
}

# -- Step 8: Clear Windows Update Registry Settings --
Write-Log "Step 8: Clearing Windows Update registry overrides..."

$wuRegKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
)

foreach ($regKey in $wuRegKeys) {
    if (Test-Path $regKey) {
        # Remove AccountDomainSid and SusClientId to force re-registration
        $valuesToRemove = @("AccountDomainSid", "PingID", "SusClientId", "SusClientIdValidation")
        foreach ($val in $valuesToRemove) {
            try {
                Remove-ItemProperty -Path $regKey -Name $val -ErrorAction SilentlyContinue
                Write-Log "Removed registry value: $regKey\$val"
            }
            catch {
                # Value may not exist, that is fine
            }
        }
        Write-Log "Processed registry key: $regKey" -Level "SUCCESS"
    }
    else {
        Write-Log "Registry key not found (skipped): $regKey"
    }
}

# -- Step 9: Restart Windows Update Services --
Write-Log "Step 9: Restarting Windows Update services..."

foreach ($svc in $services) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        try {
            Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
            Start-Service -Name $svc -ErrorAction Stop
            Write-Log "Started service: $svc ($($service.DisplayName))" -Level "SUCCESS"
        }
        catch {
            Write-Log "Could not start $svc -- it may start on demand -- $_" -Level "WARN"
        }
    }
}

# -- Step 10: Force Windows Update Detection --
Write-Log "Step 10: Forcing Windows Update detection cycle..."

try {
    # Trigger update scan via UsoClient (Windows 10/11 and Server 2016+)
    Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartScan" -NoNewWindow -ErrorAction SilentlyContinue
    Write-Log "Triggered update scan via UsoClient." -Level "SUCCESS"
}
catch {
    Write-Log "UsoClient scan trigger failed -- $_" -Level "WARN"
}

try {
    # Also try wuauclt for legacy compatibility
    Start-Process -FilePath "wuauclt.exe" -ArgumentList "/detectnow /resetauthorization" -NoNewWindow -ErrorAction SilentlyContinue
    Write-Log "Triggered update scan via wuauclt." -Level "SUCCESS"
}
catch {
    Write-Log "wuauclt scan trigger failed -- $_" -Level "WARN"
}

# -- Summary --
Write-Log "===== Windows Update Reset Script Completed ====="
Write-Log "Log file saved to: $LogFile"
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Windows Update Reset Complete!                                " -ForegroundColor Green
Write-Host "                                                                " -ForegroundColor Green
Write-Host "  Next Steps:                                                   " -ForegroundColor Green
Write-Host "    1. Reboot the computer (strongly recommended)               " -ForegroundColor Green
Write-Host "    2. Open Settings > Windows Update > Check for updates       " -ForegroundColor Green
Write-Host "    3. Review log: $LogFile" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

# Prompt for reboot
$reboot = Read-Host "Would you like to restart the computer now? (Y/N)"
if ($reboot -eq 'Y' -or $reboot -eq 'y') {
    Write-Log "User initiated reboot."
    Restart-Computer -Force
}
