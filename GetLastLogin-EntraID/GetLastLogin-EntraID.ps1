#!/usr/bin/env pwsh
# GetLastLogin-EntraID.ps1
# - Connects to Azure (Az) + Microsoft Graph
# - Reads an Excel file named Userlist.xlsx (with Useraccount + UPN column)
# - Adds/updates a LastLoginDate column with Entra ID last sign-in timestamp
#
# Userlist.xlsx location (default search order when you press Enter at the prompt):
# - Current directory: ./Userlist.xlsx
# - Windows: %USERPROFILE%\Downloads\Userlist.xlsx
# - Linux/macOS: ~/Downloads/Userlist.xlsx
#
# Excel requirements:
# - The first column should be named 'Useraccount' and must contain at least an Entra ID username.
# - A UPN column is required for the lookup (supported names: 'User Principal Name (UPN)', 'UPN', 'UserPrincipalName').

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-PreferDeviceAuthentication {
    # Prefer device authentication in headless or remote sessions where a browser cannot be opened.
    if ($IsLinux -or $IsMacOS) { return $true }
    if ($env:SSH_CONNECTION -or $env:SSH_CLIENT) { return $true }
    if ($env:WSL_INTEROP) { return $true }
    if (-not $env:DISPLAY -and -not $env:WAYLAND_DISPLAY) { return $true }
    return $false
}

function Write-SectionHeader([string]$Text) {
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('-' * $Text.Length) -ForegroundColor DarkCyan
}

function Read-YesNoPrompt([string]$Prompt) {
    while ($true) {
        $answer = (Read-Host "$Prompt (y/n)").Trim().ToLowerInvariant()
        if ($answer -in @('y','yes')) { return $true }
        if ($answer -in @('n','no')) { return $false }
        Write-Host 'Please answer with y or n.' -ForegroundColor Yellow
    }
}

function Ensure-PowerShellModule([string]$Name) {
    if (Get-Module -ListAvailable -Name $Name) {
        return
    }

    Write-Host "PowerShell module '$Name' is not installed." -ForegroundColor Yellow
    $doInstall = Read-YesNoPrompt "Do you want to install '$Name' now from PSGallery?"
    if (-not $doInstall) {
        throw "Missing module '$Name'. Install with: Install-Module $Name -Scope CurrentUser"
    }

    try {
        Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber
    } catch {
        throw "Failed to install module '$Name': $($_.Exception.Message)"
    }
}

function Connect-AzureAz {
    Ensure-PowerShellModule 'Az.Accounts'
    Import-Module Az.Accounts -ErrorAction Stop

    Write-SectionHeader 'Step 1: Connect-AzAccount'
    if (Test-PreferDeviceAuthentication) {
        Connect-AzAccount -UseDeviceAuthentication | Out-Null
    } else {
        try {
            Connect-AzAccount | Out-Null
        } catch {
            Write-Host 'Interactive login failed, trying device login...' -ForegroundColor Yellow
            Connect-AzAccount -UseDeviceAuthentication | Out-Null
        }
    }

    $ctx = Get-AzContext
    if (-not $ctx) {
        throw 'No Azure context found after Connect-AzAccount.'
    }

    Write-Host ("Signed in as: {0} (Tenant: {1})" -f $ctx.Account.Id, $ctx.Tenant.Id) -ForegroundColor Green
}

function Connect-Graph {
    Ensure-PowerShellModule 'Microsoft.Graph'
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    Write-SectionHeader 'Step 2: Connect-MgGraph'

    # Note: these scopes typically require admin consent.
    $scopes = @(
        'User.Read.All',
        'Directory.Read.All',
        'AuditLog.Read.All'
    )

    $tenantId = $null
    try {
        $azCtx = Get-AzContext -ErrorAction SilentlyContinue
        if ($azCtx -and $azCtx.Tenant -and $azCtx.Tenant.Id) {
            $tenantId = [string]$azCtx.Tenant.Id
        }
    } catch {
        $tenantId = $null
    }

    # Best effort: if already connected with Az, reuse that session to obtain a Graph access token.
    # This avoids browser/device-code timeouts in headless environments.
    if (Get-Command Get-AzAccessToken -ErrorAction SilentlyContinue) {
        try {
            $azCtx2 = Get-AzContext -ErrorAction SilentlyContinue
            if ($azCtx2) {
                Write-Host 'Trying to connect to Graph using the existing Az session...' -ForegroundColor DarkGray
                $token = if ($tenantId) {
                    Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com' -TenantId $tenantId -AsSecureString
                } else {
                    Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com' -AsSecureString
                }

                if ($token -and $token.Token) {
                    Connect-MgGraph -AccessToken $token.Token -NoWelcome | Out-Null
                }
            }
        } catch {
            Write-Host ("Az token method failed, falling back to interactive/device code. Details: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        }
    }

    # If not connected yet, do a normal connect.
    $mgExisting = $null
    try { $mgExisting = Get-MgContext } catch { $mgExisting = $null }
    if (-not ($mgExisting -and $mgExisting.Account)) {
        $maxAttempts = 3
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                if (Test-PreferDeviceAuthentication) {
                    Write-Host 'Device code sign-in: open https://microsoft.com/devicelogin and enter the displayed code.' -ForegroundColor DarkGray
                    if ($tenantId) {
                        Connect-MgGraph -Scopes $scopes -UseDeviceCode -TenantId $tenantId -NoWelcome | Out-Null
                    } else {
                        Connect-MgGraph -Scopes $scopes -UseDeviceCode -NoWelcome | Out-Null
                    }
                } else {
                    if ($tenantId) {
                        Connect-MgGraph -Scopes $scopes -TenantId $tenantId -NoWelcome | Out-Null
                    } else {
                        Connect-MgGraph -Scopes $scopes -NoWelcome | Out-Null
                    }
                }

                break
            } catch {
                $msg = $_.Exception.Message
                if ($msg -match 'timed out' -and $attempt -lt $maxAttempts) {
                    Write-Host ("Authentication timed out. Retrying ($attempt/$maxAttempts)...") -ForegroundColor Yellow
                    continue
                }
                throw "Connect-MgGraph failed: $msg"
            }
        }
    }

    Select-MgProfile -Name 'v1.0' | Out-Null

    $mg = Get-MgContext
    if (-not $mg -or -not $mg.Account) {
        throw 'No Microsoft Graph context found after Connect-MgGraph.'
    }

    Write-Host ("Connected to Graph as: {0} (Tenant: {1})" -f $mg.Account, $mg.TenantId) -ForegroundColor Green
}

function Resolve-ExcelPath {
    param(
        [string]$ExcelPath
    )

    if ([string]::IsNullOrWhiteSpace($ExcelPath)) {
        # Default file name is 'Userlist.xlsx'.
        # Search order: current directory, Downloads folder (Windows), Downloads folder (Linux/macOS).
        $candidates = New-Object System.Collections.Generic.List[string]

        $candidates.Add((Join-Path -Path (Get-Location) -ChildPath 'Userlist.xlsx'))

        if ($IsWindows -and $env:USERPROFILE) {
            $candidates.Add((Join-Path -Path $env:USERPROFILE -ChildPath 'Downloads\\Userlist.xlsx'))
        }

        if (-not $IsWindows -and $env:HOME) {
            $candidates.Add((Join-Path -Path $env:HOME -ChildPath 'Downloads/Userlist.xlsx'))
        }

        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate) {
                return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
            }
        }

        $ExcelPath = Read-Host 'No default Userlist.xlsx found. Enter the path to the Excel file (e.g. ./Userlist.xlsx)'
    }

    $resolved = Resolve-Path -LiteralPath $ExcelPath -ErrorAction Stop
    return $resolved.Path
}

function Resolve-UpnColumnName {
    param(
        [string[]]$ColumnNames
    )

    # Accept some common variants.
    $candidates = @(
        'User Principal Name (UPN)',
        'UPN',
        'UserPrincipalName',
        'userPrincipalName'
    )

    foreach ($c in $candidates) {
        if ($ColumnNames -contains $c) { return $c }
    }

    throw "UPN column not found. Expected one of: $($candidates -join ', ')"
}

function Get-EntraLastSignInDateTime {
    param(
        [Parameter(Mandatory=$true)][string]$Upn
    )

    # Use Graph endpoint with $select=signInActivity.
    # signInActivity can be empty for accounts that never signed in.
    $encoded = [System.Uri]::EscapeDataString($Upn)
    $uri = "/users/$encoded?`$select=userPrincipalName,signInActivity"

    try {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
    } catch {
        # Users could also be referenced by objectId in a sheet; here we rely on UPN.
        throw "Graph request failed for '$Upn': $($_.Exception.Message)"
    }

    $last = $null
    if ($resp.signInActivity -and $resp.signInActivity.lastSignInDateTime) {
        $last = $resp.signInActivity.lastSignInDateTime
    }

    return $last
}

function Update-UserlistWithLastLogin {
    param(
        [string]$ExcelPath
    )

    Ensure-PowerShellModule 'ImportExcel'
    Import-Module ImportExcel -ErrorAction Stop

    Write-SectionHeader 'Step 3: Read Excel and populate LastLoginDate'

    $path = Resolve-ExcelPath -ExcelPath $ExcelPath

    $sheetName = $null
    try {
        $sheetInfo = Get-ExcelSheetInfo -Path $path | Select-Object -First 1
        if ($sheetInfo -and $sheetInfo.Name) { $sheetName = [string]$sheetInfo.Name }
    } catch {
        $sheetName = $null
    }

    $rows = if ($sheetName) { Import-Excel -Path $path -WorksheetName $sheetName } else { Import-Excel -Path $path }
    if (-not $rows -or $rows.Count -eq 0) {
        throw "No data found in Excel: $path"
    }

    $columnNames = @($rows[0].PSObject.Properties.Name)
    $upnCol = Resolve-UpnColumnName -ColumnNames $columnNames

    # Best-effort validation for the requested first column requirement.
    if (-not ($columnNames -contains 'Useraccount')) {
        Write-Host "Warning: Column 'Useraccount' was not found. The first column should be named 'Useraccount'." -ForegroundColor Yellow
    }

    $total = $rows.Count
    $i = 0

    foreach ($row in $rows) {
        $i++
        $upn = $row.$upnCol

        $percent = [math]::Floor(($i / $total) * 100)
        Write-Progress -Activity 'Retrieving last login (Entra ID)' -Status ("$i of $total") -PercentComplete $percent

        if ([string]::IsNullOrWhiteSpace([string]$upn)) {
            $row | Add-Member -NotePropertyName 'LastLoginDate' -NotePropertyValue $null -Force
            continue
        }

        try {
            $last = Get-EntraLastSignInDateTime -Upn ([string]$upn)
            $row | Add-Member -NotePropertyName 'LastLoginDate' -NotePropertyValue $last -Force
        } catch {
            $row | Add-Member -NotePropertyName 'LastLoginDate' -NotePropertyValue $null -Force
            Write-Host "[$i/$total] Could not retrieve last login for '$upn': $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Progress -Activity 'Retrieving last login (Entra ID)' -Completed

    # Overwrite the same file (as requested) and keep the original worksheet name.
    if (-not $sheetName) { $sheetName = 'Sheet1' }
    Export-Excel -Path $path -InputObject $rows -WorksheetName $sheetName -AutoSize -ClearSheet

    Write-Host "Done. Excel updated: $path" -ForegroundColor Green
}

function Show-MainMenu {
    Write-SectionHeader 'GetLastLogin - Entra ID'
    Write-Host '1) Connect AzAccount (Azure login)'
    Write-Host '2) Connect Microsoft Graph (scopes for last login)'
    Write-Host '3) Update Userlist Excel with LastLoginDate'
    Write-Host '4) Exit'
}

function Start-App {
    $excelPath = $null

    while ($true) {
        Show-MainMenu
        $choice = (Read-Host 'Choose an option (1-4)').Trim()

        switch ($choice) {
            '1' {
                Connect-AzureAz
            }
            '2' {
                Connect-Graph
            }
            '3' {
                if (-not (Get-Command Connect-AzAccount -ErrorAction SilentlyContinue)) {
                    Write-Host 'You are not connected with Az yet (option 1). This is recommended.' -ForegroundColor Yellow
                }
                if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
                    Write-Host 'You are not connected to Graph yet (option 2). This is required.' -ForegroundColor Yellow
                }

                # If Graph is not connected yet, connect now.
                try {
                    $ctx = Get-MgContext
                    if (-not $ctx -or -not $ctx.Account) {
                        Connect-Graph
                    }
                } catch {
                    Connect-Graph
                }

                $excelPath = Read-Host 'Excel path (Enter for default search: Userlist.xlsx)'
                if ([string]::IsNullOrWhiteSpace($excelPath)) { $excelPath = $null }

                Update-UserlistWithLastLogin -ExcelPath $excelPath
            }
            '4' {
                break
            }
            default {
                Write-Host 'Invalid choice.' -ForegroundColor Yellow
            }
        }
    }
}

try {
    Start-App
} catch {
    Write-Host ''
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Tip: run this script in PowerShell 7+ (pwsh).' -ForegroundColor Yellow
    exit 1
}
