#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes pending system restart flags set by SCCM and Windows Update.
.DESCRIPTION
    Clears all registry keys and WMI flags that trigger SCCM's pending reboot
    state, cancels any scheduled shutdown, and restarts the SCCM client service.
.NOTES
    Must be run as Administrator.
    Reference: Internal doc "Stop Auto Reboot" (Jay Littlefield / Scott Simmons)
#>

# ── 1. Check current pending reboot status ──────────────────────────────────
Write-Host "=== Checking current pending reboot status ===" -ForegroundColor Cyan
try {
    $rebootStatus = Invoke-CimMethod -Namespace root/ccm/ClientSDK `
                        -ClassName CCM_ClientUtilities `
                        -MethodName DetermineIfRebootPending -ErrorAction Stop
    Write-Host "  RebootPending        : $($rebootStatus.RebootPending)"
    Write-Host "  IsHardRebootPending  : $($rebootStatus.IsHardRebootPending)"
} catch {
    Write-Warning "  Could not query SCCM Client SDK (client may not be installed): $_"
}

# ── 2. Clear SCCM Reboot Management registry keys ──────────────────────────
Write-Host "`n=== Clearing SCCM Reboot Management keys ===" -ForegroundColor Cyan

$sccmRebootData = 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData'
if (Test-Path $sccmRebootData) {
    Remove-Item -Path $sccmRebootData -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed: RebootData" -ForegroundColor Green
} else {
    Write-Host "  RebootData key not found (already clear)" -ForegroundColor DarkGray
}

# ── 3. Clear SCCM Updates Reboot Status ────────────────────────────────────
Write-Host "`n=== Clearing SCCM Updates Reboot Status ===" -ForegroundColor Cyan

$sccmUpdatesReboot = 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Updates Management\Handler\UpdatesRebootStatus'
if (Test-Path $sccmUpdatesReboot) {
    Remove-Item -Path "$sccmUpdatesReboot\*" -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed: UpdatesRebootStatus entries" -ForegroundColor Green
} else {
    Write-Host "  UpdatesRebootStatus key not found (already clear)" -ForegroundColor DarkGray
}

# ── 4. Clear Windows Update RebootRequired key ─────────────────────────────
Write-Host "`n=== Clearing Windows Update RebootRequired ===" -ForegroundColor Cyan

$wuRebootRequired = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
if (Test-Path $wuRebootRequired) {
    Remove-ItemProperty -Name * -Path $wuRebootRequired -Force -ErrorAction SilentlyContinue
    Write-Host "  Cleared: RebootRequired properties" -ForegroundColor Green
} else {
    Write-Host "  RebootRequired key not found (already clear)" -ForegroundColor DarkGray
}

# ── 5. Clear Component Based Servicing (CBS) RebootPending ─────────────────
Write-Host "`n=== Clearing CBS RebootPending ===" -ForegroundColor Cyan

$cbsRebootPending = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
if (Test-Path $cbsRebootPending) {
    Remove-Item -Path $cbsRebootPending -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed: CBS RebootPending" -ForegroundColor Green
} else {
    Write-Host "  CBS RebootPending key not found (already clear)" -ForegroundColor DarkGray
}

$cbsPackagesPending = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'
if (Test-Path $cbsPackagesPending) {
    Remove-Item -Path $cbsPackagesPending -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed: CBS PackagesPending" -ForegroundColor Green
} else {
    Write-Host "  CBS PackagesPending key not found (already clear)" -ForegroundColor DarkGray
}

# ── 6. Clear PendingFileRenameOperations ────────────────────────────────────
Write-Host "`n=== Clearing PendingFileRenameOperations ===" -ForegroundColor Cyan

$sessionMgr = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
$pfro = (Get-ItemProperty -Path $sessionMgr -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue)
if ($pfro) {
    Remove-ItemProperty -Path $sessionMgr -Name 'PendingFileRenameOperations' -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed: PendingFileRenameOperations" -ForegroundColor Green
} else {
    Write-Host "  PendingFileRenameOperations not found (already clear)" -ForegroundColor DarkGray
}

# ── 7. Cancel any pending shutdown ──────────────────────────────────────────
Write-Host "`n=== Cancelling any scheduled shutdown ===" -ForegroundColor Cyan
& shutdown.exe /a 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  Scheduled shutdown cancelled" -ForegroundColor Green
} else {
    Write-Host "  No scheduled shutdown to cancel" -ForegroundColor DarkGray
}

# ── 8. Restart the SCCM Client service ─────────────────────────────────────
Write-Host "`n=== Restarting SCCM Client (CcmExec) ===" -ForegroundColor Cyan
try {
    Restart-Service -Name CcmExec -Force -ErrorAction Stop
    Write-Host "  CcmExec service restarted successfully" -ForegroundColor Green
} catch {
    Write-Warning "  Could not restart CcmExec: $_"
}

# ── 9. Verify reboot status is cleared ──────────────────────────────────────
Write-Host "`n=== Verifying pending reboot status ===" -ForegroundColor Cyan
Start-Sleep -Seconds 5   # Allow service to fully restart

try {
    $verifyStatus = Invoke-CimMethod -Namespace root/ccm/ClientSDK `
                        -ClassName CCM_ClientUtilities `
                        -MethodName DetermineIfRebootPending -ErrorAction Stop
    if ($verifyStatus.RebootPending -eq $false) {
        Write-Host "  ✅ Pending reboot has been CLEARED successfully!" -ForegroundColor Green
    } else {
        Write-Warning "  ⚠️ Reboot is still pending — a manual restart may be required."
    }
} catch {
    Write-Warning "  Could not verify reboot status via SCCM Client SDK."
}

Write-Host "`nDone." -ForegroundColor Cyan
Read-Host -Prompt "Press Enter to exit"
