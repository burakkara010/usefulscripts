# GetLastLogin-EntraID

This script retrieves the **last login (lastSignInDateTime)** for users in **Microsoft Entra ID** and writes it back to the same Excel sheet in a new column **LastLoginDate**.

## Requirements

- PowerShell 7+ (`pwsh`)
- PowerShell modules:
  - `Az.Accounts`
  - `Microsoft.Graph`
  - `ImportExcel`

The script can install these modules automatically from PSGallery (with confirmation).

## Excel input

- File: default `Userlist.xlsx`. If you press Enter at the path prompt, the script automatically searches (in order):
  - Current directory: `./Userlist.xlsx`
  - Windows: `%USERPROFILE%\Downloads\Userlist.xlsx`
  - Linux/macOS: `~/Downloads/Userlist.xlsx`
  - If nothing is found, the script will ask you for a path.
- Required UPN column (one of these names):
  - `User Principal Name (UPN)`
  - `UPN`
  - `UserPrincipalName`

The first column should be named `Useraccount` and should contain at least an Entra ID username. The lookup itself is based on UPN.

## Usage

From the repo root (works on Windows and Linux):

```powershell
pwsh -File ./GetLastLogin-EntraID/GetLastLogin-EntraID.ps1
```

Menu (step-by-step):

1. Connect AzAccount (Azure login)
2. Connect Microsoft Graph (required for sign-in data)
3. Update Excel with `LastLoginDate`

## Notes

- For `signInActivity`, **admin consent** is typically required for the Graph scopes (`AuditLog.Read.All`, `Directory.Read.All`, `User.Read.All`).
- If a user never signed in, `LastLoginDate` may remain empty.
- On Linux/headless sessions where a browser cannot be opened, the script prefers **device code** sign-in (`Connect-AzAccount -UseDeviceAuthentication` and `Connect-MgGraph -UseDeviceCode`).
- For Microsoft Graph, the script first tries to reuse the existing Az session (`Get-AzAccessToken` for `https://graph.microsoft.com`). If that fails, it falls back to device code. If you see a timeout, run option 2 again and complete the device login promptly.
