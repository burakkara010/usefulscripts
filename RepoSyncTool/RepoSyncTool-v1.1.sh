#!/bin/bash

#This script is designed to update all git repositories in the current directory to the main branch.
#Description:
#This script will check all directories in the current directory for git repositories and update them to the specified branch.
#It works on both Windows and Mac/Linux systems.
#Go to the directory where the repositories are located and run this script.
#Make sure you have the necessary permissions to run this script.
#chmod +x update-all-repo-main.sh

# Define a function for colored echo to hide the -e flag
color_echo() {
    echo -e "$@"
}

color_echo "\033[1;32m"
echo "script: RepoSyncTool-v1.1.sh"
color_echo "\033[0m"
color_echo "\033[1;33m"
echo "This script will update all git repositories in the current directory to a specific branch or all branches."
color_echo "\033[0m"

# The default branch to pull updates from
defaultBranch="main"

# Set the maximum depth for the git folder structure
maxdepth=3

# Ask user which branch to pull from
color_echo "\033[33mWhich branch do you want to pull from these repositories? \n1: Manual Branch or leave empty for only \"main\" \n2: All branches (Automatic Scan)\033[0m"
read -p "Please make a choice and press Enter: " branchOption

# Ask user for the target branch
targetBranch="$defaultBranch"
if [[ "$branchOption" == "1" ]]; then
    read -p "Enter the branch you want to pull updates from (default: ${defaultBranch}): " inputBranch
    if [[ -n "$inputBranch" ]]; then
        targetBranch="$inputBranch"
    fi
fi
color_echo "\n\033[33mYou have chosen to pull updates from the '${targetBranch}' branch.\033[0m"

color_echo "\n\033[33mThe script will start in 5 seconds...\033[0m"
sleep 5
color_echo "\n\033[33mStarting the script...\033[0m"

pullAllBranches=false
if [[ "$branchOption" == "2" ]]; then
    pullAllBranches=true
    color_echo "\n\033[33mPulling all available branches for each repository\033[0m"
else
    color_echo "\n\033[33mPulling only the '${targetBranch}' branch for each repository\033[0m"
fi

# Detect OS
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    color_echo "\n\033[34mWindows detected, running PowerShell script...\033[0m\n"
    pwsh -Command "& {
        \$targetBranch = '$targetBranch'
        \$pullAllBranches = \$${pullAllBranches}
        \$repos = Get-ChildItem -Directory | Where-Object { Test-Path \"\$_/.git\" }

        if (\$repos.Count -eq 0) {
            Write-Host '`nNo repository folder found in this directory, please go to a directory where at least one repository folder is located.`n' -ForegroundColor Red
            exit 1
        }

        foreach (\$repo in \$repos) {
            Set-Location \$repo.FullName
            
            if (\$pullAllBranches) {
                Write-Host '`nPulling all branches for repository `'\$($repo.Name)`'...`n' -ForegroundColor Green
                \$branches = git branch -r | ForEach-Object { \$_.Trim() } | Where-Object { \$_ -notlike '*HEAD*' } | ForEach-Object { \$_.Replace('origin/', '') }
                
                foreach (\$branch in \$branches) {
                    Write-Host '`nPulling branch `'\$branch`'...`n' -ForegroundColor Cyan
                    git checkout \$branch
                    git pull
                }
            } else {
                Write-Host '`nPulling updates for repository `'\$($repo.Name)`' on branch `'\$targetBranch`'...`n' -ForegroundColor Green
                git checkout \$targetBranch
                git pull
            }
            
            Set-Location ..
        }
    }"
else
    color_echo "\n\033[34mMac/Linux detected, running Bash script...\033[0m\n"

    # Find directories with a .git folder, ignore .DS_Store
    repos=$(find . -maxdepth $maxdepth -type d ! -name "." ! -name ".DS_Store" -exec test -d "{}/.git" \; -print)

    if [ -z "$repos" ]; then
        color_echo "\n\033[31mNo repository folder found in this directory, please go to a directory where at least one repository folder is located.\033[0m\n"
        exit 1
    fi

    for d in $repos; do
        if [ "$pullAllBranches" = true ]; then
            color_echo "\n\n\033[32mPulling all branches for repository '$(basename "$d")'...\033[0m"
            (
                cd "$d" || continue
                # Get all remote branches and remove origin/ prefix
                branches=$(git branch -r | grep -v HEAD | sed 's/origin\///')
                
                for branch in $branches; do
                    color_echo "\n\033[36mPulling branch '$branch'...\033[0m"
                    git checkout "$branch" && git pull
                done
            )
        else
            color_echo "\n\n\033[32mPulling updates for repository '$(basename "$d")' on branch '$targetBranch'...\033[0m"
            (cd "$d" && git checkout "$targetBranch" && git pull)
        fi
    done
fi
