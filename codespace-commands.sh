#!/bin/bash

# Module for running commands in GitHub Codespaces with retry logic

# Source the common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Wait for the codespace to be fully ready
# Usage: wait_for_codespace_ready <codespace_name> <repo_name> [max_attempts] [sleep_seconds]
wait_for_codespace_ready() {
    local codespace_name=$1
    local repo_name=$2
    local max_attempts=${3:-30}
    local sleep_seconds=${4:-10}
    
    print_status "Waiting for codespace to be fully ready..."
    
    if ! retry_until "$max_attempts" "$sleep_seconds" "Checking codespace readiness" \
        gh cs ssh -c "$codespace_name" -- "bash -l -c 'test -d /workspaces/$repo_name && cd /workspaces/$repo_name && pwd'"; then
        print_error "Codespace failed to become ready after $max_attempts attempts"
        return 1
    fi
    
    print_status "Codespace is ready!"
    return 0
}

# Fetch latest remote information in the codespace
# Usage: fetch_remote <codespace_name> <repo_name>
fetch_remote() {
    local codespace_name=$1
    local repo_name=$2
    
    mise x ubi:charmbracelet/gum -- gum spin --spinner dot --title "Fetching latest remote information..." -- \
        gh cs ssh -c "$codespace_name" -- "bash -l -c 'cd /workspaces/$repo_name && git fetch origin'"
    local fetch_exit_code=$?
    
    if [ $fetch_exit_code -ne 0 ]; then
        print_error "Failed to fetch from remote. Git authentication may not be ready yet."
        print_warning "Try connecting to the codespace manually: gh cs ssh -c $codespace_name"
        return 1
    fi
    
    return 0
}

# Upload terminfo for terminal compatibility
# Usage: upload_terminfo <codespace_name> <terminfo_name>
upload_terminfo() {
    local codespace_name=$1
    local terminfo_name=$2
    
    print_status "Uploading $terminfo_name terminfo to codespace..."
    if infocmp -x "$terminfo_name" | gh cs ssh -c "$codespace_name" -- tic -x - >/dev/null 2>&1; then
        print_status "Successfully uploaded $terminfo_name terminfo."
        return 0
    else
        print_warning "Failed to upload $terminfo_name terminfo. Terminal features may be limited."
        return 1
    fi
}

# Checkout a git branch in the codespace
# Usage: checkout_branch <codespace_name> <repo_name> <branch_name>
checkout_branch() {
    local codespace_name=$1
    local repo_name=$2
    local branch_name=$3
    
    print_status "Checking if branch '$branch_name' exists remotely..."
    local remote_check
    remote_check=$(gh cs ssh -c "$codespace_name" -- "bash -l -c 'cd /workspaces/$repo_name && git ls-remote --heads origin $branch_name'" 2>/dev/null || echo "")
    
    if [ -n "$remote_check" ]; then
        print_status "Branch '$branch_name' exists remotely, checking out..."
        if gh cs ssh -c "$codespace_name" -- "bash -l -c 'cd /workspaces/$repo_name && git checkout \"$branch_name\"'" >/dev/null 2>&1; then
            print_status "Successfully checked out branch '$branch_name' in codespace '$codespace_name'"
            return 0
        else
            print_error "Failed to checkout branch '$branch_name'"
            print_warning "Codespace '$codespace_name' was created but branch checkout failed"
            return 1
        fi
    else
        print_warning "Branch '$branch_name' doesn't exist remotely. Creating new branch..."
        if gh cs ssh -c "$codespace_name" -- "bash -l -c 'cd /workspaces/$repo_name && git checkout -b \"$branch_name\"'" >/dev/null 2>&1; then
            print_status "Successfully created and checked out branch '$branch_name' in codespace '$codespace_name'"
            return 0
        else
            print_error "Failed to create branch '$branch_name'"
            print_warning "Codespace '$codespace_name' was created but branch creation failed"
            return 1
        fi
    fi
}

# Wait for codespace configuration to complete
# Usage: wait_for_configuration_complete <codespace_name> [max_attempts] [sleep_seconds]
wait_for_configuration_complete() {
    local codespace_name=$1
    local max_attempts=${2:-60}
    local sleep_seconds=${3:-10}
    
    print_status "Waiting for codespace configuration to complete..."
    
    # Helper function to check if configuration is complete
    _check_config_complete() {
        local last_log
        last_log=$(gh cs logs --codespace "$codespace_name" 2>/dev/null | tail -n 1 || echo "")
        [[ "$last_log" == *"Finished configuring codespace."* ]]
    }
    
    if retry_until "$max_attempts" "$sleep_seconds" "Checking configuration status" _check_config_complete; then
        print_status "Codespace configuration complete! ✓"
        return 0
    else
        print_warning "Codespace configuration did not complete after $max_attempts attempts"
        print_warning "The codespace may still be configuring in the background"
        return 1
    fi
}
