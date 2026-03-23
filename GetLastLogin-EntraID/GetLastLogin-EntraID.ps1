#!/usr/bin/env pwsh
# GetLastLogin-EntraID.ps1
# - Connects to Azure (Az) + Microsoft Graph
# - Reads an Excel file named Userlist.xlsx (with a Useraccount column)
# - Adds/updates a LastLoginDate column with Entra ID last sign-in timestamp
#
# Userlist.xlsx location (default search order when you press Enter at the prompt):
# - Current directory: ./Userlist.xlsx
# - Windows: %USERPROFILE%\Downloads\Userlist.xlsx
# - Linux/macOS: ~/Downloads/Userlist.xlsx
#
# Excel requirements:
# - The first column should be named 'Useraccount' and must contain at least an Entra ID username.
# - Lookup is performed using the values in the 'Useraccount' column (UPN or user id work best).

[CmdletBinding()]
param(
    # Runs the full workflow in one go: Connect-AzAccount -> Connect-MgGraph -> Update Excel.
    [switch]$RunSequence,

    # Show the interactive menu (step-by-step). If omitted, the script runs the full sequence by default.
    [switch]$Menu,

    # Force a fresh Microsoft Graph delegated sign-in (device code on Linux/headless), bypassing cached Graph context.
    [switch]$ForceGraphReauth,

    # Skip trying to reuse the Az token for Microsoft Graph (always use Connect-MgGraph delegated auth).
    [switch]$SkipAzTokenReuse,

    # Optional Excel path. If omitted, the script uses its default search/prompt behavior.
    [string]$ExcelPath
)

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

function Get-MsalCacheCandidatePaths {
    $paths = New-Object System.Collections.Generic.List[string]

    if ($env:HOME) {
        # Linux (common)
        $paths.Add((Join-Path -Path $env:HOME -ChildPath '.local/share/.IdentityService/msal.cache.cae'))
        # Fallbacks some environments may use
        $paths.Add((Join-Path -Path $env:HOME -ChildPath '.IdentityService/msal.cache.cae'))
    }

    if ($IsWindows) {
        if ($env:LOCALAPPDATA) {
            $paths.Add((Join-Path -Path $env:LOCALAPPDATA -ChildPath '.IdentityService\msal.cache.cae'))
        }
        if ($env:USERPROFILE) {
            $paths.Add((Join-Path -Path $env:USERPROFILE -ChildPath '.IdentityService\msal.cache.cae'))
        }
    }

    if ($IsMacOS -and $env:HOME) {
        $paths.Add((Join-Path -Path $env:HOME -ChildPath 'Library/Application Support/.IdentityService/msal.cache.cae'))
    }

    return @($paths | Select-Object -Unique)
}

function Test-IsMsalCacheDeserializationError {
    param(
        [Parameter(Mandatory=$true)][string]$Message
    )

    return (
        $Message -match 'MSAL deserialization failed to parse the cache contents' -or
        $Message -match 'TokenCacheJsonSerializer\.Deserialize' -or
        $Message -match 'Microsoft\.Identity\.Json\.JsonReaderException'
    )
}

function Clear-LocalMsalTokenCache {
    $candidates = Get-MsalCacheCandidatePaths
    $foundAny = $false

    foreach ($p in $candidates) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $foundAny = $true

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = "$p.bak-$timestamp"
        try {
            Copy-Item -LiteralPath $p -Destination $backup -Force
            Remove-Item -LiteralPath $p -Force
            Write-Host "Cleared MSAL cache: $p (backup: $backup)" -ForegroundColor Yellow
        } catch {
            throw "Failed to clear MSAL cache '$p': $($_.Exception.Message)"
        }
    }

    if (-not $foundAny) {
        Write-Host 'No MSAL cache file found to clear.' -ForegroundColor DarkGray
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

    $connectCmd = $null
    try { $connectCmd = Get-Command Connect-MgGraph -ErrorAction Stop } catch { $connectCmd = $null }

    function Get-ConnectMgGraphExtraParams {
        $extra = @{}
        if ($connectCmd -and $connectCmd.Parameters.ContainsKey('ForceRefresh')) {
            $extra['ForceRefresh'] = $true
        }
        if ($connectCmd -and $connectCmd.Parameters.ContainsKey('ContextScope')) {
            $extra['ContextScope'] = 'Process'
        }
        return $extra
    }

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
    # Note: if the resulting token cannot access signInActivity (Forbidden), we will fall back to a scoped Connect-MgGraph.
    function Convert-SecureStringToPlainText {
        param(
            [Parameter(Mandatory = $true)][securestring]$SecureString
        )

        return [System.Net.NetworkCredential]::new('', $SecureString).Password
    }

    function Convert-TokenForConnectMgGraph {
        param(
            [Parameter(Mandatory = $true)]$Token
        )

        $accessTokenParamType = $null
        try {
            $accessTokenParamType = (Get-Command Connect-MgGraph -ErrorAction Stop).Parameters['AccessToken'].ParameterType
        } catch {
            $accessTokenParamType = [string]
        }

        $expectsSecureString = ($accessTokenParamType -eq [securestring])

        if ($expectsSecureString) {
            if ($Token -is [securestring]) { return $Token }
            if ($Token -is [string]) { return (ConvertTo-SecureString -String $Token -AsPlainText -Force) }
            return (ConvertTo-SecureString -String ([string]$Token) -AsPlainText -Force)
        }

        if ($Token -is [securestring]) { return (Convert-SecureStringToPlainText -SecureString $Token) }
        return [string]$Token
    }

    $skipAzTokenReuseEffective = [bool]$SkipAzTokenReuse
    if ($ForceGraphReauth) {
        $skipAzTokenReuseEffective = $true
    }

    if ($ForceGraphReauth) {
        Write-Host 'Graph auth: forcing fresh delegated sign-in (bypassing cached context).' -ForegroundColor DarkGray
        try { Disconnect-MgGraph | Out-Null } catch { }
    }

    if (-not $skipAzTokenReuseEffective -and (Get-Command Get-AzAccessToken -ErrorAction SilentlyContinue)) {
        try {
            $azCtx2 = Get-AzContext -ErrorAction SilentlyContinue
            if ($azCtx2) {
                Write-Host 'Trying to connect to Graph using the existing Az session...' -ForegroundColor DarkGray
                $tokenResponse = if ($tenantId) {
                    Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com' -TenantId $tenantId
                } else {
                    Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com'
                }

                if ($tokenResponse -and $tokenResponse.Token) {
                    $graphAccessToken = Convert-TokenForConnectMgGraph -Token $tokenResponse.Token
                    Connect-MgGraph -AccessToken $graphAccessToken -NoWelcome | Out-Null

                    try {
                        Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=id' | Out-Null
                    } catch {
                        $m2 = $_.Exception.Message
                        if ($m2 -match 'Unauthorized|401|InvalidAuthenticationToken') {
                            Write-Host 'Az token connected, but Graph calls returned Unauthorized. Falling back to normal Connect-MgGraph...' -ForegroundColor Yellow
                            try { Disconnect-MgGraph | Out-Null } catch { }
                        }
                    }
                }
            }
        } catch {
            Write-Host ("Az token method failed, falling back to interactive/device code. Details: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        }
    } elseif ($skipAzTokenReuseEffective) {
        Write-Host 'Graph auth: skipping Az token reuse; using delegated Connect-MgGraph.' -ForegroundColor DarkGray
    }

    function Test-CanReadSignInActivity {
        try {
            $ctxLocal = Get-MgContext
            if (-not $ctxLocal -or -not $ctxLocal.Account) { return $false }

            $encodedAccount = [System.Uri]::EscapeDataString([string]$ctxLocal.Account)
            $testUri = "https://graph.microsoft.com/v1.0/users/${encodedAccount}?`$select=id,signInActivity"
            Invoke-MgGraphRequest -Method GET -Uri $testUri | Out-Null
            return $true
        } catch {
            $m = $_.Exception.Message
            if ($m -match 'Forbidden') { return $false }
            if ($m -match 'Unauthorized|401|InvalidAuthenticationToken') { return $false }
            # Non-forbidden errors (transient, not found etc.) shouldn't block auth.
            return $true
        }
    }

    function Get-CurrentGraphScopesString {
        try {
            $c = Get-MgContext
            if ($c -and $c.Scopes) {
                return (($c.Scopes | Sort-Object -Unique) -join ', ')
            }
        } catch {
            # ignore
        }
        return '(unknown)'
    }

    function Test-CanListUsers {
        try {
            Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/users?$top=1&$select=id' | Out-Null
            return $true
        } catch {
            $m = $_.Exception.Message
            if ($m -match 'Forbidden|Unauthorized|401|403|InvalidAuthenticationToken') { return $false }
            return $true
        }
    }

    function Test-CanReadSignInActivityForAnyUser {
        $urisToTry = @(
            'https://graph.microsoft.com/beta/users?$top=1&$select=id,signInActivity',
            'https://graph.microsoft.com/v1.0/users?$top=1&$select=id,signInActivity'
        )
        foreach ($u in $urisToTry) {
            try {
                Invoke-MgGraphRequest -Method GET -Uri $u | Out-Null
                return $true
            } catch {
                $m = $_.Exception.Message
                if ($m -match 'Forbidden|Unauthorized|401|403|InvalidAuthenticationToken') { return $false }
                continue
            }
        }
        return $true
    }

    # If we are connected but cannot read signInActivity (Forbidden), disconnect and do a normal connect.
    $mgExisting = $null
    try { $mgExisting = Get-MgContext } catch { $mgExisting = $null }
    if (($mgExisting -and $mgExisting.Account) -and (-not (Test-CanReadSignInActivity))) {
        Write-Host 'Connected to Graph, but token cannot access sign-in activity (Forbidden). Re-authenticating with requested scopes...' -ForegroundColor Yellow
        try { Disconnect-MgGraph | Out-Null } catch { }
        $mgExisting = $null
    }

    if (-not ($mgExisting -and $mgExisting.Account)) {
        $maxAttempts = 3
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                if (Test-PreferDeviceAuthentication) {
                    Write-Host 'Device code sign-in: open https://microsoft.com/devicelogin and enter the displayed code.' -ForegroundColor DarkGray
                    $extra = Get-ConnectMgGraphExtraParams
                    if ($tenantId) {
                        Connect-MgGraph -Scopes $scopes -UseDeviceCode -TenantId $tenantId -NoWelcome @extra | Out-Null
                    } else {
                        Connect-MgGraph -Scopes $scopes -UseDeviceCode -NoWelcome @extra | Out-Null
                    }
                } else {
                    $extra = Get-ConnectMgGraphExtraParams
                    if ($tenantId) {
                        Connect-MgGraph -Scopes $scopes -TenantId $tenantId -NoWelcome @extra | Out-Null
                    } else {
                        Connect-MgGraph -Scopes $scopes -NoWelcome @extra | Out-Null
                    }
                }

                Write-Host 'Note: if you were NOT prompted with a device-code URL, Graph likely reused an existing valid cached session (this is OK).' -ForegroundColor DarkGray

                if (-not (Test-CanReadSignInActivity)) {
                    throw 'Forbidden: connected but missing permission/role to read signInActivity.'
                }

                break
            } catch {
                $msg = $_.Exception.Message

                if (Test-IsMsalCacheDeserializationError -Message $msg) {
                    Write-Host 'Authentication failed due to a local MSAL token cache parsing error.' -ForegroundColor Yellow
                    Write-Host 'This is usually fixed by clearing the local MSAL cache and signing in again.' -ForegroundColor Yellow
                    $doClear = Read-YesNoPrompt 'Clear local MSAL token cache now and retry authentication?'
                    if ($doClear) {
                        Clear-LocalMsalTokenCache
                        continue
                    }
                }

                if ($msg -match 'timed out' -and $attempt -lt $maxAttempts) {
                    Write-Host ("Authentication timed out. Retrying ($attempt/$maxAttempts)...") -ForegroundColor Yellow
                    continue
                }
                if ($msg -match 'Forbidden') {
                    throw "Connect-MgGraph succeeded but reading sign-in activity is Forbidden. Ensure admin consent for Graph delegated permissions ($($scopes -join ', ')) and that your signed-in account has a role like Reports Reader / Security Reader / Global Reader (or higher)."
                }
                throw "Connect-MgGraph failed: $msg"
            }
        }
    }

    # Newer Microsoft Graph PowerShell versions may not include Select-MgProfile.
    # We avoid relying on profiles and instead call explicit v1.0/beta endpoints where needed.
    if (Get-Command Select-MgProfile -ErrorAction SilentlyContinue) {
        Select-MgProfile -Name 'v1.0' | Out-Null
    }

    $mg = Get-MgContext
    if (-not $mg -or -not $mg.Account) {
        throw 'No Microsoft Graph context found after Connect-MgGraph.'
    }

    function Get-MissingRequiredScopes {
        param(
            [Parameter(Mandatory = $true)][string[]] $RequiredScopes
        )

        $ctx = $null
        try { $ctx = Get-MgContext } catch { $ctx = $null }
        $current = @()
        if ($ctx -and $ctx.Scopes) { $current = @($ctx.Scopes) }

        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($rs in $RequiredScopes) {
            if (-not ($current -contains $rs)) {
                $missing.Add($rs)
            }
        }
        return @($missing)
    }

    $missingScopes = Get-MissingRequiredScopes -RequiredScopes $scopes
    if ($missingScopes.Count -gt 0) {
        Write-Host ("Graph token is missing required scopes: {0}" -f ($missingScopes -join ', ')) -ForegroundColor Yellow
        Write-Host 'Re-authenticating to Microsoft Graph with the required scopes...' -ForegroundColor Yellow
        try { Disconnect-MgGraph | Out-Null } catch { }

        $extra = Get-ConnectMgGraphExtraParams
        if (Test-PreferDeviceAuthentication) {
            Write-Host 'Device code sign-in: open https://microsoft.com/devicelogin and enter the displayed code.' -ForegroundColor DarkGray
            if ($tenantId) {
                Connect-MgGraph -Scopes $scopes -UseDeviceCode -TenantId $tenantId -NoWelcome @extra | Out-Null
            } else {
                Connect-MgGraph -Scopes $scopes -UseDeviceCode -NoWelcome @extra | Out-Null
            }
        } else {
            if ($tenantId) {
                Connect-MgGraph -Scopes $scopes -TenantId $tenantId -NoWelcome @extra | Out-Null
            } else {
                Connect-MgGraph -Scopes $scopes -NoWelcome @extra | Out-Null
            }
        }

        $missingScopes = Get-MissingRequiredScopes -RequiredScopes $scopes
        if ($missingScopes.Count -gt 0) {
            $scopeStr2 = Get-CurrentGraphScopesString
            throw "Microsoft Graph connected, but the access token still does not contain the required delegated scopes: $($missingScopes -join ', '). This usually means admin consent was NOT granted for the Microsoft Graph PowerShell client (clientId: 14d82eec-204b-4c2f-b7e8-296a70dab67e) for these scopes in this tenant. Current token scopes: $scopeStr2"
        }
    }

    $scopeStr = Get-CurrentGraphScopesString
    Write-Host ("Graph scopes in token: {0}" -f $scopeStr) -ForegroundColor DarkGray

    if (-not (Test-CanListUsers)) {
        throw "Connected to Graph, but cannot list users (likely missing User.Read.All / Directory.Read.All delegated permission or required Entra role). Current scopes: $scopeStr"
    }
    if (-not (Test-CanReadSignInActivityForAnyUser)) {
        throw "Connected to Graph, but cannot read signInActivity for users (403). This is typically missing AuditLog.Read.All delegated permission and/or missing Entra role (Reports Reader / Security Reader / Global Reader). Current scopes: $scopeStr"
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
            # Some Linux distros use lowercase 'downloads'. Check both.
            $candidates.Add((Join-Path -Path $env:HOME -ChildPath 'Downloads/Userlist.xlsx'))
            $candidates.Add((Join-Path -Path $env:HOME -ChildPath 'downloads/Userlist.xlsx'))
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

function Resolve-EntraUserLookupKey {
    param(
        [Parameter(Mandatory=$true)][string]$Useraccount
    )

    $value = $Useraccount.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }

    # If it already looks like a UPN or object id, we can use it directly with /users/{id-or-upn}.
    if ($value -match '@') { return $value }
    if ($value -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { return $value }

    # Otherwise, attempt to resolve common account-name fields (hybrid / service accounts).
    $escaped = $value.Replace("'", "''")

    $filtersToTry = @(
        "onPremisesSamAccountName eq '$escaped'",
        "mailNickname eq '$escaped'"
    )

    foreach ($filterExpr in $filtersToTry) {
        $filterEncoded = [System.Uri]::EscapeDataString($filterExpr)
        $uri = "https://graph.microsoft.com/v1.0/users?`$filter=${filterEncoded}&`$select=id,userPrincipalName"
        $resp = $null
        try {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
        } catch {
            continue
        }

        if ($resp -and $resp.value -and $resp.value.Count -ge 1) {
            if ($resp.value.Count -gt 1) {
                throw "Multiple users matched '$value' using filter '$filterExpr'. Please use a unique UPN or object id in 'Useraccount'."
            }

            $match = $resp.value[0]
            if ($match.id) { return [string]$match.id }
            if ($match.userPrincipalName) { return [string]$match.userPrincipalName }
        }
    }

    # Fall back to original value; the caller will surface a Graph error if it can't be resolved.
    return $value
}

function Get-EntraLastSignInDateTime {
    param(
        [Parameter(Mandatory=$true)][string]$Upn
    )

    # signInActivity can be empty for accounts that never signed in.
    # Depending on tenant/features, signInActivity may not be available in v1.0.
    # We try v1.0 first and fall back to beta if necessary.
    $lookupKey = Resolve-EntraUserLookupKey -Useraccount $Upn
    if ([string]::IsNullOrWhiteSpace($lookupKey)) { return $null }

    $encoded = [System.Uri]::EscapeDataString($lookupKey)
    $v1Uri = "https://graph.microsoft.com/v1.0/users/${encoded}?`$select=userPrincipalName,signInActivity"
    $betaUri = "https://graph.microsoft.com/beta/users/${encoded}?`$select=userPrincipalName,signInActivity"

    $resp = $null
    try {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $v1Uri
    } catch {
        $v1Error = $_.Exception.Message
        if ($v1Error -match 'Unauthorized|401|InvalidAuthenticationToken') {
            throw "Unauthorized (401): your Microsoft Graph access token is missing/invalid/expired. Re-run option 2 (Connect Microsoft Graph) to re-authenticate, or run with -RunSequence so the script connects with delegated scopes. Details: $v1Error"
        }
        if ($v1Error -match 'Forbidden') {
            $scopeStr = '(unknown)'
            try {
                $c2 = Get-MgContext
                if ($c2 -and $c2.Scopes) { $scopeStr = (($c2.Scopes | Sort-Object -Unique) -join ', ') }
            } catch { }
            throw "Forbidden: missing permission/role to read signInActivity. Ensure admin consent for delegated Graph permissions (AuditLog.Read.All, Directory.Read.All, User.Read.All) and assign a role like Reports Reader / Security Reader / Global Reader (or higher) to the signed-in account. Current token scopes: $scopeStr"
        }
        try {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $betaUri
        } catch {
            $betaError = $_.Exception.Message
            if ($betaError -match 'Unauthorized|401|InvalidAuthenticationToken') {
                throw "Unauthorized (401): your Microsoft Graph access token is missing/invalid/expired. Re-run option 2 (Connect Microsoft Graph) to re-authenticate, or run with -RunSequence so the script connects with delegated scopes. Details: $betaError"
            }
            if ($betaError -match 'Forbidden') {
                $scopeStr = '(unknown)'
                try {
                    $c3 = Get-MgContext
                    if ($c3 -and $c3.Scopes) { $scopeStr = (($c3.Scopes | Sort-Object -Unique) -join ', ') }
                } catch { }
                throw "Forbidden: missing permission/role to read signInActivity. Ensure admin consent for delegated Graph permissions (AuditLog.Read.All, Directory.Read.All, User.Read.All) and assign a role like Reports Reader / Security Reader / Global Reader (or higher) to the signed-in account. Current token scopes: $scopeStr"
            }
            throw "Graph request failed for '$Upn' (v1.0 then beta): $v1Error | $betaError"
        }
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

    if (-not ($columnNames -contains 'Useraccount')) {
        throw "Column 'Useraccount' was not found. Please include a 'Useraccount' column (UPN or user id)."
    }

    $total = $rows.Count
    $i = 0

    foreach ($row in $rows) {
        $i++
        $userAccount = $row.Useraccount

        $percent = [math]::Floor(($i / $total) * 100)
        Write-Progress -Activity 'Retrieving last login (Entra ID)' -Status ("$i of $total") -PercentComplete $percent

        if ([string]::IsNullOrWhiteSpace([string]$userAccount)) {
            $row | Add-Member -NotePropertyName 'LastLoginDate' -NotePropertyValue $null -Force
            continue
        }

        try {
            $last = Get-EntraLastSignInDateTime -Upn ([string]$userAccount)
            $row | Add-Member -NotePropertyName 'LastLoginDate' -NotePropertyValue $last -Force
        } catch {
            $row | Add-Member -NotePropertyName 'LastLoginDate' -NotePropertyValue $null -Force
            $errMsg = $_.Exception.Message
            Write-Host "[$i/$total] Could not retrieve last login for '$userAccount': $errMsg" -ForegroundColor Yellow
            if ($errMsg -match 'Forbidden: missing permission/role' -or $errMsg -match 'signInActivity is Forbidden') {
                throw $errMsg
            }
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
    Write-Host '4) Run full sequence (1 -> 2 -> 3)'
    Write-Host '5) Exit'
}

function Invoke-FullSequence {
    param(
        [string]$ExcelPath
    )

    Connect-AzureAz
    Connect-Graph
    Update-UserlistWithLastLogin -ExcelPath $ExcelPath
}

function Start-App {
    $excelPath = $null

    while ($true) {
        Show-MainMenu
        $choice = (Read-Host 'Choose an option (1-5)').Trim()

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

                # Always ensure we have a Graph token that can read signInActivity.
                # (A previous MgContext may exist with different scopes, causing Forbidden later.)
                Connect-Graph

                $excelPath = Read-Host 'Excel path (Enter for default search: Userlist.xlsx)'
                if ([string]::IsNullOrWhiteSpace($excelPath)) { $excelPath = $null }

                Update-UserlistWithLastLogin -ExcelPath $excelPath
            }
            '4' {
                # Full sequence uses the script's default Excel resolution logic:
                # ./Userlist.xlsx, then Downloads, then prompt if not found.
                Invoke-FullSequence -ExcelPath $null
            }
            '5' {
                break
            }
            default {
                Write-Host 'Invalid choice.' -ForegroundColor Yellow
            }
        }
    }
}

try {
    if ($Menu) {
        Start-App
    } else {
        Invoke-FullSequence -ExcelPath $ExcelPath
    }
} catch {
    Write-Host ''
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Tip: run this script in PowerShell 7+ (pwsh).' -ForegroundColor Yellow
    exit 1
}
