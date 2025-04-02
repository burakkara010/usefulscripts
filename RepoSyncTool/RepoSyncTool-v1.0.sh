#This script is designed to update all git repositories in the current directory to the main branch.
#It works on both Windows and Mac/Linux systems.
#Go to the directory where the repositories are located and run this script.
#Make sure you have the necessary permissions to run this script.
#chmod +x update-all-repo-main.sh

#!/bin/bash

# The default branch to pull updates from
targetBranch="main"

# Set the maximum depth for the find command
maxdepth=3

# Ask user which branch to pull from
echo -e "\n\033[33mWhich branch do you want to pull from these repositories? \n1: ${targetBranch} \n2: Update all branches from all Repositories\033[0m"
read -p "Please make a choice and press Enter: " branchOption

pullAllBranches=false
if [[ "$branchOption" == "2" ]]; then
    pullAllBranches=true
    echo -e "\n\033[33mPulling all available branches for each repository\033[0m"
else
    echo -e "\n\033[33mPulling only the '${targetBranch}' branch for each repository\033[0m"
fi

# Detect OS
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    echo -e "\n\033[34mWindows detected, running PowerShell script...\033[0m\n"
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
    echo -e "\n\033[34mMac/Linux detected, running Bash script...\033[0m\n"

    # Find directories with a .git folder, ignore .DS_Store
    repos=$(find . -maxdepth $maxdepth -type d ! -name "." ! -name ".DS_Store" -exec test -d "{}/.git" \; -print)

    if [ -z "$repos" ]; then
        echo -e "\n\033[31mNo repository folder found in this directory, please go to a directory where at least one repository folder is located.\033[0m\n"
        exit 1
    fi

    for d in $repos; do
        if [ "$pullAllBranches" = true ]; then
            echo -e "\n\n\033[32mPulling all branches for repository '$(basename "$d")'...\033[0m"
            (
                cd "$d" || continue
                # Get all remote branches and remove origin/ prefix
                branches=$(git branch -r | grep -v HEAD | sed 's/origin\///')
                
                for branch in $branches; do
                    echo -e "\n\033[36mPulling branch '$branch'...\033[0m"
                    git checkout "$branch" && git pull
                done
            )
        else
            echo -e "\n\n\033[32mPulling updates for repository '$(basename "$d")' on branch '$targetBranch'...\033[0m"
            (cd "$d" && git checkout "$targetBranch" && git pull)
        fi
    done
fi
