<#
.SYNOPSIS
    Removes autofstx.exe from the WinRE BootExecute registry value.

.DESCRIPTION
    This remediation script removes the "autofstx.exe" entry from the BootExecute
    REG_MULTI_SZ value inside the Windows Recovery Environment (WinRE) offline
    SYSTEM registry hive. This is a security fix to prevent autofstx.exe from
    executing during WinRE boot.

    The script performs the following steps:
      1. Verify administrator privileges
      2. Verify WinRE is enabled
      3. Mount the WinRE image via reagentc
      4. Load the offline SYSTEM registry hive
      5. Read BootExecute and remove autofstx.exe if present
      6. Unload the offline hive
      7. Unmount the WinRE image with commit
      8. Disable and re-enable WinRE to re-seal BitLocker trust chain

    Exit 0 = Success (entry removed or not present)
    Exit 1 = Failure (error during remediation)

.PARAMETER MountPath
    Directory to use as the WinRE mount point. Created if it does not exist.
    Default: C:\Mount

.EXAMPLE
    # Standard run
    .\Remove-AutoFsTxFromWinRE.ps1

.EXAMPLE
    # Custom mount path
    .\Remove-AutoFsTxFromWinRE.ps1 -MountPath D:\mount

.NOTES
    Requirements: Windows with WinRE and reagentc support, Administrator privileges.
    The WinRE disable/enable cycle at the end is required to re-seal the
    BitLocker measurement chain after modifying the WinRE image.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$MountPath = "C:\Mount"
)

# Target entry to remove from BootExecute
$EntryToRemove = "autofstx.exe"

# Internal constant for the offline hive key name
$HiveName = "WinREHive"

# State tracking for cleanup
$hiveLoaded   = $false
$imageMounted = $false
$mountCreated = $false
$changesMade  = $false

Write-Host "Remove autofstx.exe from WinRE BootExecute"

# 1. Verify Administrator Privileges
# PS Version: All | Admin: Yes | System Requirements: None
try {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "[1/8] Administrator check: FAILED" -ForegroundColor Red
        Write-Host "  This script must be run as Administrator."
        Write-Host "  Right-click PowerShell and select 'Run as administrator'."
        exit 1
    }

    Write-Host "[1/8] Administrator check: Passed" -ForegroundColor Green
} catch {
    Write-Warning "Error checking administrator privileges: $_"
    exit 1
}

# 2. Check WinRE Status
# PS Version: All | Admin: Yes | System Requirements: reagentc.exe
try {
    $winreOutput = & reagentc /info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[2/8] WinRE status check: FAILED" -ForegroundColor Red
        Write-Warning "reagentc /info returned exit code $LASTEXITCODE"
        exit 1
    }
    $winreOutputStr = $winreOutput -join "`n"

    if ($winreOutputStr -notmatch "Windows RE status:\s+Enabled") {
        Write-Host "[2/8] WinRE status: NOT ENABLED. Exiting." -ForegroundColor Green
        exit 0
    }

    Write-Host "[2/8] WinRE status: Enabled" -ForegroundColor Green
} catch {
    Write-Warning "Error checking WinRE status: $_"
    exit 1
}

# 3. Mount WinRE Image
# PS Version: All | Admin: Yes | System Requirements: reagentc.exe
try {
    if (-not (Test-Path $MountPath)) {
        New-Item -ItemType Directory -Path $MountPath -Force | Out-Null
        $mountCreated = $true
        Write-Host "[3/8] Created mount directory: $MountPath"
    } else {
        $existing = Get-ChildItem -Path $MountPath -Force -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "[3/8] Mount WinRE image: FAILED" -ForegroundColor Red
            Write-Host "  Mount directory $MountPath is not empty."
            Write-Host "  Clean it or specify a different -MountPath."
            exit 1
        }
    }

    $mountOutput = & reagentc /mountre /path $MountPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[3/8] Mount WinRE image: FAILED" -ForegroundColor Red
        Write-Warning "reagentc /mountre output: $mountOutput"
        exit 1
    }

    $imageMounted = $true
    Write-Host "[3/8] WinRE image mounted: $MountPath" -ForegroundColor Green
} catch {
    Write-Warning "Error mounting WinRE image: $_"
    exit 1
}

# 4. Load Offline SYSTEM Registry Hive
# PS Version: All | Admin: Yes | System Requirements: reg.exe
try {
    # Locate the SYSTEM hive in the mounted WinRE image
    $hivePath = $null
    $hiveCandidates = @(
        "$MountPath\Windows\System32\config\SYSTEM",
        "$MountPath\windows\system32\config\SYSTEM"
    )

    foreach ($candidate in $hiveCandidates) {
        if (Test-Path $candidate) {
            $hivePath = $candidate
            break
        }
    }

    if (-not $hivePath) {
        # Broader search as fallback
        $found = Get-ChildItem -Path $MountPath -Recurse -Filter "SYSTEM" -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -match "config\\SYSTEM$" } |
                 Select-Object -First 1

        if ($found) {
            $hivePath = $found.FullName
        }
    }

    if (-not $hivePath) {
        Write-Host "[4/8] Load offline hive: FAILED" -ForegroundColor Red
        Write-Warning "Cannot locate SYSTEM hive in mounted WinRE image."

        # Cleanup: unmount with discard
        $null = & reagentc /unmountre /path $MountPath /discard 2>&1
        $imageMounted = $false
        exit 1
    }

    Write-Host "[4/8] Found SYSTEM hive: $hivePath"

    $loadOutput = & reg load "HKLM\$HiveName" $hivePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[4/8] Load offline hive: FAILED" -ForegroundColor Red
        Write-Warning "reg load output: $loadOutput"

        # Cleanup: unmount with discard
        $null = & reagentc /unmountre /path $MountPath /discard 2>&1
        $imageMounted = $false
        exit 1
    }

    $hiveLoaded = $true
    Write-Host "[4/8] Hive loaded as HKLM\$HiveName" -ForegroundColor Green
} catch {
    Write-Warning "Error loading offline hive: $_"

    if ($imageMounted) {
        $null = & reagentc /unmountre /path $MountPath /discard 2>&1
        $imageMounted = $false
    }
    exit 1
}

# 5. Read BootExecute and Remove autofstx.exe
# PS Version: All | Admin: Yes | System Requirements: None
try {
    # Determine active ControlSets from Select key
    $selectPath = "Registry::HKEY_LOCAL_MACHINE\$HiveName\Select"
    $selectProps = Get-ItemProperty -Path $selectPath -ErrorAction SilentlyContinue

    if ($selectProps -and $selectProps.Current) {
        $csNumbers = @($selectProps.Current)
        if ($selectProps.Default -and $selectProps.Default -ne $selectProps.Current) {
            $csNumbers += $selectProps.Default
        }
        $controlSets = $csNumbers | ForEach-Object { "ControlSet{0:D3}" -f [int]$_ }
        Write-Host "[5/8] Active ControlSets (from Select key): $($controlSets -join ', ')"
    } else {
        $controlSets = @("ControlSet001")
        Write-Host "[5/8] Select key not readable, falling back to ControlSet001"
    }

    # Remediate all relevant ControlSets
    $foundEntry = $false

    foreach ($cs in $controlSets) {
        $regPath = "Registry::HKEY_LOCAL_MACHINE\$HiveName\$cs\Control\Session Manager"
        $testResult = Get-ItemProperty -Path $regPath -Name "BootExecute" -ErrorAction SilentlyContinue

        if (-not $testResult) {
            Write-Host "  $cs\Session Manager\BootExecute: not found, skipping"
            continue
        }

        $currentValue = $testResult.BootExecute

        if (-not $currentValue) {
            Write-Host "  $cs BootExecute: (empty)"
            continue
        }

        # Remove matching entry (case-insensitive)
        $updatedValue = @($currentValue | Where-Object {
            $_ -and
            ($_ -ne $EntryToRemove) -and
            ($_ -notmatch "^\s*$([regex]::Escape($EntryToRemove))\s*$")
        })

        if ($updatedValue.Count -eq @($currentValue).Count) {
            Write-Host "  $cs BootExecute: '$EntryToRemove' not present"
            continue
        }

        # Write updated REG_MULTI_SZ back
        Set-ItemProperty -Path $regPath -Name "BootExecute" -Value $updatedValue
        $foundEntry = $true

        Write-Host "  $cs BootExecute: removed '$EntryToRemove'" -ForegroundColor Green

        # Verify the write
        $verifyValue = (Get-ItemProperty -Path $regPath -Name "BootExecute" -ErrorAction Stop).BootExecute
        Write-Host "  $cs verification: $($verifyValue -join '; ')"
    }

    if (-not $foundEntry) {
        Write-Host "[5/8] '$EntryToRemove' not found in any active ControlSet. No changes needed." -ForegroundColor Green

        # Cleanup: unload hive, unmount with discard
        [gc]::Collect()
        Start-Sleep -Seconds 1
        $null = & reg unload "HKLM\$HiveName" 2>&1
        $hiveLoaded = $false
        $null = & reagentc /unmountre /path $MountPath /discard 2>&1
        $imageMounted = $false
        if ($mountCreated) { Remove-Item -Path $MountPath -Recurse -Force -ErrorAction SilentlyContinue }
        exit 0
    }

    $changesMade = $true
    Write-Host "[5/8] Removed '$EntryToRemove' from BootExecute" -ForegroundColor Green
} catch {
    Write-Warning "Error modifying BootExecute: $_"

    # Cleanup: unload hive, unmount with discard
    [gc]::Collect()
    Start-Sleep -Seconds 2
    if ($hiveLoaded) {
        $null = & reg unload "HKLM\$HiveName" 2>&1
        $hiveLoaded = $false
    }
    if ($imageMounted) {
        $null = & reagentc /unmountre /path $MountPath /discard 2>&1
        $imageMounted = $false
    }
    exit 1
}

# 6. Unload Offline Registry Hive
# PS Version: All | Admin: Yes | System Requirements: reg.exe
try {
    [gc]::Collect()
    Start-Sleep -Seconds 2

    $unloadOutput = & reg unload "HKLM\$HiveName" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "First unload attempt failed, retrying..."
        [gc]::Collect()
        Start-Sleep -Seconds 3
        $unloadOutput = & reg unload "HKLM\$HiveName" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[6/8] Unload hive: FAILED" -ForegroundColor Red
            Write-Warning "reg unload output: $unloadOutput"
            Write-Host "  Close any Registry Editor windows and retry."

            # Try to unmount with discard to avoid leaving image mounted
            $null = & reagentc /unmountre /path $MountPath /discard 2>&1
            $imageMounted = $false
            exit 1
        }
    }

    $hiveLoaded = $false
    Write-Host "[6/8] Offline hive unloaded" -ForegroundColor Green
} catch {
    Write-Warning "Error unloading hive: $_"

    $null = & reagentc /unmountre /path $MountPath /discard 2>&1
    $imageMounted = $false
    exit 1
}

# 7. Unmount WinRE Image with Commit
# PS Version: All | Admin: Yes | System Requirements: reagentc.exe
try {
    if ($changesMade) {
        $unmountOutput = & reagentc /unmountre /path $MountPath /commit 2>&1
    } else {
        $unmountOutput = & reagentc /unmountre /path $MountPath /discard 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[7/8] Unmount WinRE: FAILED" -ForegroundColor Red
        Write-Warning "reagentc /unmountre output: $unmountOutput"

        # Attempt discard as fallback
        if ($changesMade) {
            Write-Host "  Attempting discard to avoid leaving image in broken state..."
            $null = & reagentc /unmountre /path $MountPath /discard 2>&1
        }
        $imageMounted = $false
        exit 1
    }

    $imageMounted = $false

    if ($changesMade) {
        Write-Host "[7/8] WinRE image unmounted and committed" -ForegroundColor Green
    } else {
        Write-Host "[7/8] WinRE image unmounted (no changes)" -ForegroundColor Green
    }
} catch {
    Write-Warning "Error unmounting WinRE image: $_"
    exit 1
}

# 8. Re-seal WinRE (Disable + Enable Cycle for BitLocker Trust Chain)
# PS Version: All | Admin: Yes | System Requirements: reagentc.exe, BitLocker
try {
    if (-not $changesMade) {
        Write-Host "[8/8] Re-seal WinRE: Skipped (no changes made)" -ForegroundColor Green
    } else {
        $disableOutput = & reagentc /disable 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "reagentc /disable returned non-zero: $disableOutput"
        } else {
            Write-Host "  WinRE disabled."
        }

        $enableOutput = & reagentc /enable 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[8/8] Re-seal WinRE: FAILED" -ForegroundColor Red
            Write-Warning "reagentc /enable output: $enableOutput"
            Write-Host "  WinRE may need manual recovery. Run: reagentc /enable"
            exit 1
        }

        Write-Host "[8/8] WinRE re-sealed (disable + enable cycle)" -ForegroundColor Green
    }
} catch {
    Write-Warning "Error during WinRE re-seal: $_"
    Write-Host "  Run manually: reagentc /enable"
    exit 1
}

Write-Host ""
Write-Host "  COMPLETE: '$EntryToRemove' removed from WinRE BootExecute" -ForegroundColor Green

# Cleanup: remove mount directory if we created it
if ($mountCreated -and (Test-Path $MountPath)) {
    Remove-Item -Path $MountPath -Recurse -Force -ErrorAction SilentlyContinue
}

exit 0
