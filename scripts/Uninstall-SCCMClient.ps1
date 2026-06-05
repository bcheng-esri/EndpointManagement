<#
.SYNOPSIS
    Fully uninstalls the SCCM/ConfigMgr client and removes all related folders,
    registry keys, services, certificates, and WMI namespaces.

.DESCRIPTION
    This script performs a complete removal of the Configuration Manager client:
      1. Runs the official ccmsetup.exe /uninstall
      2. Stops and removes SCCM-related services
      3. Deletes SCCM folders
      4. Removes SCCM registry keys
      5. Cleans up WMI namespaces and repositories
      6. Removes SCCM certificates
      7. Removes ccmsetup scheduled tasks

.NOTES
	Created on:   2026-06-04
	Author:       Brian Cheng
	Version:      1.0
    
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
	write-host ""
    pause
    exit
} else {
    Write-Host "  Script elevated" -ForegroundColor DarkGray
}

# -- Logging Setup --
$LogFile = "$env:SystemRoot\Temp\Uninstall-SCCMClient_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

Write-Log "===== SCCM Client Full Uninstall Script Started ====="

# -- Step 1: Run Official Uninstaller --
Write-Log "Step 1: Running ccmsetup.exe /uninstall..."

$ccmsetupPaths = @(
    "$env:SystemRoot\ccmsetup\ccmsetup.exe",
    "$env:SystemRoot\ccm\ccmsetup.exe"
)

$uninstallRan = $false
foreach ($path in $ccmsetupPaths) {
    if (Test-Path $path) {
        Write-Log "Found ccmsetup at: $path"
        try {
            $process = Start-Process -FilePath $path -ArgumentList "/uninstall" -Wait -PassThru -NoNewWindow
            Write-Log "ccmsetup /uninstall exited with code: $($process.ExitCode)"
            $uninstallRan = $true
            Write-Log "Waiting for ccmsetup process to fully complete..."
            Start-Sleep -Seconds 30
            while (Get-Process -Name ccmsetup -ErrorAction SilentlyContinue) {
                Write-Log "ccmsetup still running, waiting..."
                Start-Sleep -Seconds 10
            }
            break
        }
        catch {
            Write-Log "Error running ccmsetup: $_" -Level "ERROR"
        }
    }
}

if (-not $uninstallRan) {
    Write-Log "ccmsetup.exe not found -- skipping official uninstall." -Level "WARN"
}

# -- Step 2: Stop and Remove SCCM Services --
Write-Log "Step 2: Stopping and removing SCCM services..."

$sccmServices = @(
    "CcmExec",
    "ccmsetup",
    "smstsmgr",
    "CmRcService"
)

foreach ($svc in $sccmServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        Write-Log "Stopping service: $svc"
        try {
            Stop-Service -Name $svc -Force -ErrorAction Stop
            Write-Log "Stopped service: $svc" -Level "SUCCESS"
        }
        catch {
            Write-Log "Could not stop service $svc -- $_" -Level "WARN"
            $proc = Get-CimInstance Win32_Service -Filter "Name='$svc'" -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessId -gt 0) {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                Write-Log "Force-killed process for service: $svc"
            }
        }
        try {
            sc.exe delete $svc | Out-Null
            Write-Log "Deleted service: $svc" -Level "SUCCESS"
        }
        catch {
            Write-Log "Could not delete service $svc -- $_" -Level "ERROR"
        }
    }
    else {
        Write-Log "Service not found (already removed): $svc"
    }
}

# -- Step 3: Delete SCCM Folders --
Write-Log "Step 3: Deleting SCCM folders..."

$sccmFolders = @(
    "$env:SystemRoot\CCM",
    "$env:SystemRoot\ccmsetup",
    "$env:SystemRoot\ccmcache",
    "$env:SystemRoot\SMSCFG.ini",
    "$env:SystemRoot\Temp\CCM*",
    "$env:SystemDrive\_SMSTaskSequence",
    "$env:SystemDrive\SMSTSLog"
)

foreach ($folder in $sccmFolders) {
    if (Test-Path $folder) {
        try {
            Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
            Write-Log "Deleted: $folder" -Level "SUCCESS"
        }
        catch {
            Write-Log "Failed to delete $folder -- $_ (may require reboot)" -Level "WARN"
        }
    }
    else {
        Write-Log "Not found (skipped): $folder"
    }
}

# -- Step 4: Delete SCCM Registry Keys --
Write-Log "Step 4: Removing SCCM registry keys..."

$sccmRegKeys = @(
    "HKLM:\SOFTWARE\Microsoft\CCM",
    "HKLM:\SOFTWARE\Microsoft\CCMSetup",
    "HKLM:\SOFTWARE\Microsoft\SMS",
    "HKLM:\SOFTWARE\Microsoft\DeviceManageabilityCSP",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\CCM",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\CCMSetup",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\SMS",
    "HKLM:\SYSTEM\CurrentControlSet\Services\CcmExec",
    "HKLM:\SYSTEM\CurrentControlSet\Services\ccmsetup",
    "HKLM:\SYSTEM\CurrentControlSet\Services\smstsmgr",
    "HKLM:\SYSTEM\CurrentControlSet\Services\CmRcService"
)

foreach ($key in $sccmRegKeys) {
    if (Test-Path $key) {
        try {
            Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
            Write-Log "Deleted registry key: $key" -Level "SUCCESS"
        }
        catch {
            Write-Log "Failed to delete registry key: $key -- $_" -Level "ERROR"
        }
    }
    else {
        Write-Log "Registry key not found (skipped): $key"
    }
}

# Remove SCCM from Uninstall registry (Add/Remove Programs)
Write-Log "Checking for SCCM entries in Uninstall registry..."
$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($uninstPath in $uninstallPaths) {
    if (Test-Path $uninstPath) {
        Get-ChildItem -Path $uninstPath -ErrorAction SilentlyContinue | ForEach-Object {
            $displayName = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
            if ($displayName -match "Configuration Manager Client" -or $displayName -match "System Center" -or $displayName -match "ccmsetup") {
                try {
                    Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed uninstall entry: $displayName" -Level "SUCCESS"
                }
                catch {
                    Write-Log "Failed to remove uninstall entry: $displayName -- $_" -Level "WARN"
                }
            }
        }
    }
}

# -- Step 5: Clean Up WMI Namespaces --
Write-Log "Step 5: Cleaning up WMI namespaces..."

$wmiNamespaces = @(
    "root\ccm",
    "root\cimv2\sms",
    "root\SmsDm"
)

foreach ($ns in $wmiNamespaces) {
    try {
        $parentNS = $ns.Substring(0, $ns.LastIndexOf('\'))
        $childName = $ns.Split('\')[-1]
        $nsObj = Get-WmiObject -Namespace $parentNS -Class __Namespace -Filter "Name='$childName'" -ErrorAction SilentlyContinue
        if ($nsObj) {
            $nsObj | Remove-WmiObject -ErrorAction Stop
            Write-Log "Removed WMI namespace: $ns" -Level "SUCCESS"
        }
        else {
            Write-Log "WMI namespace not found (skipped): $ns"
        }
    }
    catch {
        Write-Log "Failed to remove WMI namespace $ns -- $_" -Level "WARN"
    }
}

# -- Step 6: Remove SCCM Certificates --
Write-Log "Step 6: Removing SCCM-related certificates..."

$certStores = @(
    "Cert:\LocalMachine\SMS"
)

foreach ($store in $certStores) {
    if (Test-Path $store) {
        try {
            Get-ChildItem -Path $store | Remove-Item -Force -ErrorAction Stop
            Write-Log "Removed certificates from: $store" -Level "SUCCESS"
        }
        catch {
            Write-Log "Failed to remove certificates from $store -- $_" -Level "WARN"
        }
    }
    else {
        Write-Log "Certificate store not found (skipped): $store"
    }
}

# -- Step 7: Remove SCCM Scheduled Tasks --
Write-Log "Step 7: Removing SCCM scheduled tasks..."

$sccmTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -match "Configuration Manager" -or
    $_.TaskPath -match "Microsoft\\Configuration Manager" -or
    $_.TaskName -match "CCM" -or
    $_.TaskName -match "SMS"
}

if ($sccmTasks) {
    foreach ($task in $sccmTasks) {
        try {
            Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction Stop
            Write-Log "Removed scheduled task: $($task.TaskName)" -Level "SUCCESS"
        }
        catch {
            Write-Log "Failed to remove scheduled task: $($task.TaskName) -- $_" -Level "WARN"
        }
    }
}
else {
    Write-Log "No SCCM scheduled tasks found."
}

# -- Step 8: Final Cleanup --
Write-Log "Step 8: Final cleanup -- removing SMSCFG.ini..."

$smscfg = "$env:SystemRoot\SMSCFG.ini"
if (Test-Path $smscfg) {
    Remove-Item -Path $smscfg -Force -ErrorAction SilentlyContinue
    Write-Log "Deleted SMSCFG.ini" -Level "SUCCESS"
}

# -- Summary --
Write-Log "===== SCCM Client Uninstall Script Completed ====="
Write-Log "Log file saved to: $LogFile"
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  SCCM Client Uninstall Complete!                              " -ForegroundColor Green
Write-Host "  A system REBOOT is strongly recommended.                     " -ForegroundColor Green
Write-Host "  Log: $LogFile" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

# Prompt for reboot
$reboot = Read-Host "Would you like to restart the computer now? (Y/N)"
if ($reboot -eq 'Y' -or $reboot -eq 'y') {
    Write-Log "User initiated reboot."
    Restart-Computer -Force
}
