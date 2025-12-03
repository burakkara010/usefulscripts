<#
.SYNOPSIS
    Script for preparing an AVD Golden Image.
    Version: 4.3 (Includes Strict BitLocker Decryption, Smart Log Analysis, FSLogix & Auto-Sysprep Fix)

.DESCRIPTION
    This script configures:
    1. FSLogix & Entra ID Profile settings.
    2. STRICT BitLocker Check (Handles 'WaitingForActivation' states).
    3. Sysprep Generalize & Shutdown.
    4. FIX: Smartly analyzes setupact.log for the LATEST run errors only.

.NOTES
    Requires: Administrator privileges.
    Supports: Azure Files with Entra ID Authentication.
#>

function Show-Header {
    Clear-Host
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "      AVD Golden Image Preparation Tool v4.3" -ForegroundColor Yellow
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Check-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "WARNING: This script must be run as Administrator!"
        Break
    }
}

function Configure-FSLogix {
    [CmdletBinding()]
    param ( [string]$VHDLocation )

    Write-Host "--- Starting Configuration ---" -ForegroundColor Green

    # Input check
    if ([string]::IsNullOrWhiteSpace($VHDLocation)) {
        $VHDLocation = Read-Host "Enter the UNC path (e.g., \\mystorage.file.core.windows.net\profiles)"
    }
    if ([string]::IsNullOrWhiteSpace($VHDLocation)) { Write-Error "No valid path specified. Aborted."; return }

    # -----------------------------------------------------------
    # PART 1: FSLogix Base Settings
    # -----------------------------------------------------------
    $fslogixPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
    if (-not (Test-Path $fslogixPath)) { New-Item -Path $fslogixPath -Force | Out-Null }

    try {
        Set-ItemProperty -Path $fslogixPath -Name "Enabled" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $fslogixPath -Name "VHDLocations" -Value $VHDLocation -Type MultiString -Force
        Set-ItemProperty -Path $fslogixPath -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $fslogixPath -Name "VolumeType" -Value "VHDX" -Type String -Force
        Set-ItemProperty -Path $fslogixPath -Name "FlipFlopProfileDirectoryName" -Value 1 -Type DWord -Force
        
        Write-Host "[OK] FSLogix base configuration applied." -ForegroundColor Green
    } catch { Write-Error "Error during FSLogix configuration: $_" }

    # -----------------------------------------------------------
    # PART 2: Storage Access (Entra ID Kerberos)
    # -----------------------------------------------------------
    $kerberosPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters"
    if (-not (Test-Path $kerberosPath)) { New-Item -Path $kerberosPath -Force | Out-Null }

    try {
        Set-ItemProperty -Path $kerberosPath -Name "CloudKerberosTicketRetrievalEnabled" -Value 1 -Type DWord -Force
        Write-Host "[OK] Cloud Kerberos Ticket Retrieval Enabled." -ForegroundColor Green
    } catch { Write-Error "Error setting Kerberos: $_" }

    # -----------------------------------------------------------
    # PART 3: Identity Roaming (LoadCredKeyFromProfile)
    # -----------------------------------------------------------
    $aadPath = "HKLM:\SOFTWARE\Policies\Microsoft\AzureADAccount"
    if (-not (Test-Path $aadPath)) { New-Item -Path $aadPath -Force | Out-Null }

    try {
        Set-ItemProperty -Path $aadPath -Name "LoadCredKeyFromProfile" -Value 1 -Type DWord -Force
        Write-Host "[OK] Identity Roaming Enabled." -ForegroundColor Green
    } catch { Write-Error "Error setting AAD identity roaming: $_" }
    
    Write-Host "Configuration completed successfully." -ForegroundColor Cyan
    Write-Host "------------------------------------"
    Pause
}

function Disable-BitLocker-Check {
    Write-Host "--- Checking BitLocker Status ---" -ForegroundColor Magenta
    try {
        $bitlockerStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
        
        # DEBUG INFO: Show the user exactly what the drive state is
        Write-Host "Current Status: $($bitlockerStatus.VolumeStatus)" -ForegroundColor Gray
        Write-Host "Protection:     $($bitlockerStatus.ProtectionStatus)" -ForegroundColor Gray

        # UPDATED LOGIC: If the drive is not "FullyDecrypted", we must act.
        # This catches "WaitingForActivation", "Suspended", and "Encrypted".
        if ($bitlockerStatus.VolumeStatus -ne 'FullyDecrypted') {
            Write-Warning "BitLocker is NOT fully decrypted. Sysprep requires a clean drive."
            Write-Host "Forcing BitLocker Decryption now..." -ForegroundColor Yellow
            
            # Disable-BitLocker handles 'WaitingForActivation' by clearing the clear key
            Disable-BitLocker -MountPoint "C:" -Confirm:$false -ErrorAction SilentlyContinue
            
            # Wait loop until it is truly clean
            do {
                Start-Sleep -Seconds 5
                $status = Get-BitLockerVolume -MountPoint "C:"
                $percent = $status.EncryptionPercentage
                Write-Host "Decrypting... Remaining Encrypted: $percent%" -NoNewline -ForegroundColor Gray; Write-Host "`r" -NoNewline
            } until ($status.VolumeStatus -eq 'FullyDecrypted')
            
            Write-Host "`n[OK] Drive C: is now Fully Decrypted." -ForegroundColor Green
        }
        else {
            Write-Host "[OK] Volume is Fully Decrypted. Safe to Sysprep." -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Could not query BitLocker status. Ensure run as Admin."
    }
    Write-Host "------------------------------------"
}

function Fix-Sysprep-Apps {
    Write-Host "--- Sysprep Error Analysis & Cleanup ---" -ForegroundColor Magenta
    
    $logPath = "$env:WINDIR\System32\Sysprep\Panther\setupact.log"
    
    if (-not (Test-Path $logPath)) {
        Write-Warning "Cannot find setupact.log. Have you run Sysprep yet?"
        Pause
        return
    }

    Write-Host "Reading log file..." -ForegroundColor Gray
    
    # Get a larger chunk of the log to ensure we find the start header
    $rawLog = Get-Content -Path $logPath -Tail 1000
    
    # -----------------------------------------------------------
    # INTELLIGENT PARSING: Find the start of the LATEST run
    # -----------------------------------------------------------
    $startMarker = "Beginning of a new sysprep run"
    $lastStartIndex = -1

    # Loop through to find the index of the LAST occurrence of the marker
    for ($i = 0; $i -lt $rawLog.Count; $i++) {
        if ($rawLog[$i] -match $startMarker) {
            $lastStartIndex = $i
        }
    }

    # If we found a start marker, slice the array to only keep lines AFTER that marker
    if ($lastStartIndex -ge 0) {
        Write-Host "Isolating the most recent Sysprep attempt..." -ForegroundColor Cyan
        $currentRunLog = $rawLog[$lastStartIndex..($rawLog.Count - 1)]
    }
    else {
        # Fallback if marker isn't found in the tail
        Write-Warning "Could not find 'Beginning of a new sysprep run' in the last 1000 lines."
        Write-Host "Analyzing the tail of the log as is..." -ForegroundColor Gray
        $currentRunLog = $rawLog
    }

    # -----------------------------------------------------------
    # 1. CHECK FOR BITLOCKER (0x80310039) IN CURRENT RUN
    # -----------------------------------------------------------
    if ($currentRunLog | Select-String "0x80310039") {
        Write-Host ""
        Write-Host "!!! ERROR FOUND IN LATEST RUN: BITLOCKER !!!" -ForegroundColor Red
        
        # Double check live status to be safe
        try {
            $blStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
            # Check strictly for FullyDecrypted
            if ($blStatus.VolumeStatus -ne 'FullyDecrypted') {
                Write-Host "Confirmation: BitLocker is still active (Status: $($blStatus.VolumeStatus))" -ForegroundColor Yellow
                $fixBitlocker = Read-Host "Do you want to disable BitLocker now? (Y/N)"
                if ($fixBitlocker -eq 'Y' -or $fixBitlocker -eq 'y') {
                    Disable-BitLocker-Check
                    Write-Host "BitLocker disabled. Please try running Sysprep again (Option 2)." -ForegroundColor Green
                    Pause
                    return
                }
            } else {
                Write-Host "Note: The log shows a BitLocker error, but the drive is currently Fully Decrypted." -ForegroundColor Green
                Write-Host "You should be safe to retry Sysprep." -ForegroundColor Gray
            }
        } catch {
            Write-Warning "Could not verify live BitLocker status."
        }
    }

    # -----------------------------------------------------------
    # 2. CHECK FOR APPX PACKAGES IN CURRENT RUN
    # -----------------------------------------------------------
    $pattern = "Package\s+(?<PackageName>[\w\.-]+)\s+was installed for a user"
    $match = $currentRunLog | Select-String -Pattern $pattern

    if ($match) {
        $badPackage = $match.Matches.Groups['PackageName'].Value | Select-Object -Unique | Select-Object -First 1
        
        Write-Host ""
        Write-Host "!!! APPX CULPRIT FOUND IN LATEST RUN !!!" -ForegroundColor Red
        Write-Host "Blocking Package: $badPackage" -ForegroundColor Yellow
        Write-Host ""
        
        $conf = Read-Host "Do you want to remove this specific package now? (Y/N)"
        if ($conf -eq 'Y' -or $conf -eq 'y') {
            Write-Host "Proceeding with removal of $badPackage..." -ForegroundColor Cyan
            
            Get-AppxPackage | Where-Object {$_.Name -like "*$badPackage*"} | Remove-AppxPackage -ErrorAction SilentlyContinue
            Get-AppxPackage -AllUsers | Where-Object {$_.Name -like "*$badPackage*"} | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            
            Write-Host "Package removed. Please try running Sysprep again (Option 2)." -ForegroundColor Green
        }
    } 
    else {
        # Only show generic cleanup if no specific errors were found in this specific run
        if (-not ($currentRunLog | Select-String "0x80310039")) {
            Write-Host "No specific errors found in the latest Sysprep run." -ForegroundColor Green
            Write-Host ""
            $confGeneric = Read-Host "Do you want to run a proactive cleanup (Xbox, Spotify, etc)? (Y/N)"
            
            if ($confGeneric -eq 'Y' -or $confGeneric -eq 'y') {
                $commonBloat = @("Microsoft.XboxApp", "Microsoft.ZuneMusic", "Microsoft.ZuneVideo", "Microsoft.BingWeather", "Microsoft.MicrosoftSolitaireCollection", "SpotifyAB.SpotifyMusic")
                foreach ($app in $commonBloat) {
                    if (Get-AppxPackage -AllUsers | Where-Object {$_.Name -like "*$app*"}) {
                        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*$app*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
                        Get-AppxPackage -AllUsers | Where-Object {$_.Name -like "*$app*"} | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                        Write-Host "$app Removed." -ForegroundColor Green
                    }
                }
                Write-Host "Generic cleanup finished."
            }
        }
    }
    Write-Host "------------------------------------"
    Pause
}

function Start-Sysprep {
    Write-Host "--- Starting Sysprep (Generalize) ---" -ForegroundColor Red
    
    # Auto-check BitLocker before starting
    Disable-BitLocker-Check

    Write-Warning "The VM will be generalized and shut down."
    
    $confirm = Read-Host "Type 'Y' to continue"
    if ($confirm -eq 'Y' -or $confirm -eq 'y') {
        $sysprepPath = "$env:SystemRoot\System32\Sysprep\sysprep.exe"
        if (Test-Path $sysprepPath) {
            Write-Host "Sysprep will start in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            Start-Process -FilePath $sysprepPath -ArgumentList "/generalize", "/oobe", "/shutdown", "/mode:vm" -Wait
        }
    } else {
        Write-Host "Canceled."
    }
}

# --- MAIN MENU LOOP ---

Check-Admin

do {
    Show-Header
    Write-Host "1. Configure Image (FSLogix, Entra Kerberos & Identity)"
    Write-Host "2. Start Sysprep & Shutdown (Auto-Checks BitLocker)"
    Write-Host "3. RUN ALL (Config + Sysprep)"
    Write-Host "4. FIX SYSPREP ERRORS (Smart Log Analyzer)" -ForegroundColor Magenta
    Write-Host "Q. Quit"
    Write-Host ""
    
    $selection = Read-Host "Choice"

    switch ($selection) {
        '1' { Configure-FSLogix }
        '2' { Start-Sysprep }
        '3' {
            $path = Read-Host "Enter the UNC path (e.g., \\storage.file.core.windows.net\profiles)"
            Configure-FSLogix -VHDLocation $path
            Start-Sysprep
        }
        '4' { Fix-Sysprep-Apps }
        'Q' { break }
        'q' { break }
    }
} until ($selection -eq 'Q' -or $selection -eq 'q')