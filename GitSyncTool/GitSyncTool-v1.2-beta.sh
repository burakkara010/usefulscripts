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

# Function to display a progress bar
display_progress() {
    local current=$1
    local total=$2
    local repo_name=$3
    local branch_name=$4
    local percent=$((current * 100 / total))
    local completed=$((percent / 2))
    local remaining=$((50 - completed))
    
    # Create the progress bar
    local progress_bar="["
    for ((i=0; i<completed; i++)); do
        progress_bar+="#"
    done
    for ((i=0; i<remaining; i++)); do
        progress_bar+="."
    done
    progress_bar+="]"
    
    # Display the progress bar with repo and branch info
    echo -ne "\r\033[K$progress_bar $percent% ($current/$total) - Repo: $repo_name, Branch: $branch_name"
}

color_echo "\033[1;32m"
echo "script: RepoSyncTool-v1.2-beta.sh"
color_echo "\033[0m"
color_echo "\033[1;33m"
echo "This script will update all git repositories in the current directory to a specific branch or all branches."
color_echo "\033[0m"
color_echo "\033[1;36m"
echo "Make sure you are in the correct directory where the repositories are located."
color_echo "\033[0m"

# The default branch to pull updates from
defaultBranch="main"

# Set the maximum depth for the git folder structure
maxdepth=3

# Ask user which branch to pull from
color_echo "\033[33mWhich branch do you want to pull from these repositories? \n1: Manual Branch or only \"main\" \n2: All branches (Automatic Scan)\033[0m"
read -p "Please make a choice and press Enter: " branchOption

# Ask user for the target branch
targetBranch="$defaultBranch"
if [[ "$branchOption" == "1" ]]; then
    read -p "Enter the branch you want to pull updates from or
    Leave empty for (default: ${defaultBranch}): " inputBranch
    if [[ -n "$inputBranch" ]]; then
        targetBranch="$inputBranch"
    fi
    color_echo "\n\033[33mYou have chosen to pull updates from the '${targetBranch}' branch.\033[0m"
elif [[ "$branchOption" == "2" ]]; then
    color_echo "\n\033[33mYou have chosen to pull updates from all branches.\033[0m"
else
    color_echo "\n\033[31mInvalid option selected. Please run the script again and choose a valid option.\033[0m"
    exit 1
fi

# Countdown timer 
color_echo "\n\033[33m"
for i in {5..1}
do
    echo -ne "The script will start in $i second$([ $i -eq 1 ] || echo 's')...   \r"
    sleep 1
done
color_echo "Starting the script...\033[0m"

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
            Write-Host \"\`nNo repository folder found in this directory, please go to a directory where at least one repository folder is located.\`n\" -ForegroundColor Red
            exit 1
        }

        # Count total repositories for progress tracking
        \$totalRepos = \$repos.Count
        \$currentRepo = 0
        
        foreach (\$repo in \$repos) {
            \$currentRepo++
            Set-Location \$repo.FullName
            
            # Create progress bar
            \$percentComplete = [int](\$currentRepo / \$totalRepos * 100)
            \$progressBar = '['
            for (\$i = 0; \$i -lt 50; \$i++) {
                if (\$i -lt (\$percentComplete / 2)) {
                    \$progressBar += '#'
                } else {
                    \$progressBar += '.'
                }
            }
            \$progressBar += ']'
            
            if (\$pullAllBranches) {
                Write-Host \"\`nRepository \$currentRepo/\$totalRepos: \$progressBar \$percentComplete% - \$(\$repo.Name)\" -ForegroundColor Green
                \$branches = git branch -r | ForEach-Object { \$_.Trim() } | Where-Object { \$_ -notlike '*HEAD*' } | ForEach-Object { \$_.Replace('origin/', '') }
                
                # Count total branches for progress tracking
                \$totalBranches = \$branches.Count
                \$currentBranch = 0
                
                foreach (\$branch in \$branches) {
                    \$currentBranch++
                    \$branchPercent = [int](\$currentBranch / \$totalBranches * 100)
                    \$branchProgress = '['
                    for (\$i = 0; \$i -lt 50; \$i++) {
                        if (\$i -lt (\$branchPercent / 2)) {
                            \$branchProgress += '#'
                        } else {
                            \$branchProgress += '.'
                        }
                    }
                    \$branchProgress += ']'
                    
                    Write-Host \"  Branch \$currentBranch/\$totalBranches: \$branchProgress \$branchPercent% - \$branch\" -ForegroundColor Cyan
                    git checkout \$branch
                    git pull
                }
            } else {
                Write-Host \"\`nRepository \$currentRepo/\$totalRepos: \$progressBar \$percentComplete% - \$(\$repo.Name) on branch \$targetBranch\" -ForegroundColor Green
                git checkout \$targetBranch
                git pull
            }
            
            Set-Location ..
        }
        
        Write-Host \"\`nAll repositories have been updated successfully!\" -ForegroundColor Green
    }"
else
    color_echo "\n\033[34mMac/Linux detected, running Bash script...\033[0m\n"

    # Find directories with a .git folder, ignore .DS_Store
    repos=$(find . -maxdepth $maxdepth -type d ! -name "." ! -name ".DS_Store" -exec test -d "{}/.git" \; -print)

    if [ -z "$repos" ]; then
        color_echo "\n\033[31mNo repository folder found in this directory, please go to a directory where at least one repository folder is located.\033[0m\n"
        exit 1
    fi

    # Count total repositories for progress tracking
    total_repos=$(echo "$repos" | wc -l)
    current_repo=0
    
    for d in $repos; do
        current_repo=$((current_repo + 1))
        repo_name=$(basename "$d")
        
        # Display repository progress
        repo_percent=$((current_repo * 100 / total_repos))
        repo_completed=$((repo_percent / 2))
        repo_remaining=$((50 - repo_completed))
        
        repo_progress="["
        for ((i=0; i<repo_completed; i++)); do
            repo_progress+="#"
        done
        for ((i=0; i<repo_remaining; i++)); do
            repo_progress+="."
        done
        repo_progress+="]"
        
        color_echo "\n\n\033[32mRepository $current_repo/$total_repos: $repo_progress $repo_percent% - '$repo_name'\033[0m"
        
        if [ "$pullAllBranches" = true ]; then
            (
                cd "$d" || continue
                # Get all remote branches and remove origin/ prefix
                branches=$(git branch -r | grep -v HEAD | sed 's/origin\///')
                
                # Count total branches for progress tracking
                total_branches=$(echo "$branches" | wc -l)
                current_branch=0
                
                for branch in $branches; do
                    current_branch=$((current_branch + 1))
                    
                    # Display branch progress
                    display_progress $current_branch $total_branches "$repo_name" "$branch"
                    
                    git checkout "$branch" && git pull
                done
                echo # Add a newline after the progress bar
            )
        else
            color_echo "\033[36mPulling updates for branch '$targetBranch'...\033[0m"
            (cd "$d" && git checkout "$targetBranch" && git pull)
        fi
    done
    
    color_echo "\n\033[32mAll repositories have been updated successfully!\033[0m"
fi
