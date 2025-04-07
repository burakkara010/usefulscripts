# Changelog

## [v1.2-beta] 
2025-04-04

**Optimization:**
- Improved script performance by reducing redundant operations.
- Enhanced compatibility with nested repositories by refining the `find` command logic.

___

## [v1.1] 
2025-04-03

**Added:**
- User prompt to select between pulling a specific branch or all branches.
- Support for detecting and handling repositories with detached HEAD states.
- Additional error handling for invalid user input during branch selection.

___

## [v1.0] 
Initial Release

**Features:**
- **Operating System Detection**:
  - Detects the operating system (Windows or Mac/Linux) and runs the appropriate script for updating Git repositories.
- **Branch Update Options**:
  - Allows the user to choose between:
    - Pulling updates only for the default branch (`main` by default).
    - Pulling updates for all branches in each repository.
- **Multi-Repository Support**:
  - Supports updating multiple Git repositories in the current directory and its subdirectories (up to a configurable depth, default is 3).
- **Windows Support**:
  - Uses PowerShell to find repositories and pull updates.
  - Pulls all branches or a specific branch based on user input.
- **Mac/Linux Support**:
  - Uses the `find` command to locate repositories and pull updates.
  - Pulls all branches or a specific branch based on user input.
- **Error Handling**:
  - Displays an error message if no Git repositories are found in the current directory.
  - Exits gracefully if no repositories are detected.
- **User Interaction**:
  - Prompts the user to select the branch update mode (specific branch or all branches).
  - Provides clear and color-coded output for better readability.
- **Cross-Platform Compatibility**:
  - Works on both Windows (via PowerShell) and Mac/Linux (via Bash).

**Notes:**
- Ensure the script has executable permissions (`chmod +x GitSyncTool-v1.0.sh`) before running.
- Requires Git to be installed and available in the system's PATH.
- For Windows, PowerShell Core (`pwsh`) is required for execution.