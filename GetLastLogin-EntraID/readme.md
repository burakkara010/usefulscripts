# GetLastLogin-EntraID

This script retrieves the **last login (lastSignInDateTime)** for users in **Microsoft Entra ID** and writes it back to the same Excel sheet in a new column **LastLoginDate**.

## Requirements (exact)

### 1) Local/runtime requirements

- PowerShell 7+ (`pwsh`)
- PowerShell modules:
  - `Az.Accounts`
  - `Microsoft.Graph`
  - `ImportExcel`

The script can install these modules automatically from PSGallery (with confirmation).

### 2) Linux dependencies (recommended)

On Linux, `ImportExcel` can run without these, but **auto-size** requires additional native libraries.

If you see: `WARNING: ImportExcel Module Cannot Autosize...`, install:

```bash
sudo apt-get -y update && sudo apt-get install -y --no-install-recommends libgdiplus libc6-dev
```

### 3) Entra ID / Microsoft Graph requirements (needed for last login)

To read `signInActivity` / last sign-in timestamps for *other users*, you need BOTH:

- **Delegated Graph scopes in the access token** (admin consent typically required):
  - `AuditLog.Read.All` (required)
  - `Directory.Read.All`
  - `User.Read.All`

- **An active Entra directory role at token-issue time** (often via PIM), e.g.:
  - `Global Reader` (commonly sufficient)
  - or `Reports Reader` / `Security Reader` (or higher)

Important: Microsoft Graph CLI (`mgc`) permissions are separate from Microsoft Graph PowerShell (`Connect-MgGraph`).
This script authenticates via Microsoft Graph PowerShell (default clientId: `14d82eec-204b-4c2f-b7e8-296a70dab67e`).
Admin consent must be granted for that client (or you must use a custom app registration).

## Excel input

- File: default `Userlist.xlsx`. If you press Enter at the path prompt, the script automatically searches (in order):
  - Current directory: `./Userlist.xlsx`
  - Windows: `%USERPROFILE%\Downloads\Userlist.xlsx`
  - Linux/macOS: `~/Downloads/Userlist.xlsx` and `~/downloads/Userlist.xlsx`
  - If nothing is found, the script will ask you for a path.
The script looks up each user using the value in the `Useraccount` column (UPN or user id work best).

## Usage

From the repo root (works on Windows and Linux):

```powershell
pwsh -File ./GetLastLogin-EntraID-v1.ps1
```

By default, the script runs the full workflow in one go (Az login + Graph login + Excel update).

Run everything in one go (Connect Az + Connect Graph + Update Excel):

```powershell
pwsh -File ./GetLastLogin-EntraID-v1.ps1 -RunSequence
```

If you want a specific file path:

```powershell
pwsh -File ./GetLastLogin-EntraID-v1.ps1 -RunSequence -ExcelPath ./Userlist.xlsx
```

Menu (step-by-step):

```powershell
pwsh -File ./GetLastLogin-EntraID-v1.ps1 -Menu
```

1. Connect AzAccount (Azure login)
2. Connect Microsoft Graph (required for sign-in data)
3. Update Excel with `LastLoginDate`
4. Run full sequence (1 -> 2 -> 3)

## Notes

- For `signInActivity`, **admin consent** is typically required for the Graph scopes (`AuditLog.Read.All`, `Directory.Read.All`, `User.Read.All`).
- If a user never signed in, `LastLoginDate` may remain empty.
- On Linux/headless sessions where a browser cannot be opened, the script prefers **device code** sign-in (`Connect-AzAccount -UseDeviceAuthentication` and `Connect-MgGraph -UseDeviceCode`).
- For Microsoft Graph, the script first tries to reuse the existing Az session (`Get-AzAccessToken` for `https://graph.microsoft.com`). If that fails, it falls back to device code. If you see a timeout, run option 2 again and complete the device login promptly.
- If you want to force a fresh Graph sign-in prompt (device code URL + code), use `-ForceGraphReauth`. This bypasses any cached Graph context.
- If you want to always skip Az-token reuse for Graph (delegated auth only), use `-SkipAzTokenReuse`.
- If you suspect Graph keeps reusing a cached token with the wrong scopes, run with `-ClearMsalCache` (this clears the local IdentityService MSAL cache and forces device-code sign-in again).
- The script does not require `Select-MgProfile`. It calls the Graph `v1.0` endpoint first and falls back to `beta` if `signInActivity` isn't available in `v1.0` for your tenant.

## Quick troubleshooting

- **Error: token is missing required delegated scopes (especially `AuditLog.Read.All`)**
  - Ask a Global Admin to grant admin consent for delegated Microsoft Graph permissions (`AuditLog.Read.All`, `Directory.Read.All`, `User.Read.All`) to the Microsoft Graph PowerShell clientId `14d82eec-204b-4c2f-b7e8-296a70dab67e` in your tenant.
  - Then re-run with: `-ForceGraphReauth -ClearMsalCache`.

- **MSAL deserialization / cache parse errors**
  - Run with `-ClearMsalCache` to rebuild the local token cache.

- **Rows show `User not found`**
  - The value in the Excel `Useraccount` column did not match any Entra user (UPN/objectId is best).

- **Rows show `signInActivity doesn't exist`**
  - The Graph response did not include the `signInActivity` property for that query/profile/tenant behavior. The script uses beta fallback, but tenants/policies can still block it.
