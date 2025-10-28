#!/bin/bash

# Module for creating GitHub Codespaces

# Source the common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Create a new GitHub Codespace
# Usage: create_codespace <repo> <machine_type> <devcontainer_path> [default_permissions]
# Returns: The codespace name via stdout
create_codespace() {
    local repo=$1
    local machine_type=$2
    local devcontainer_path=$3
    local default_permissions=$4
    
    print_status "Creating new codespace with $machine_type machine type..."
    
    local codespace_output
    if ! codespace_output=$(gh cs create -R "$repo" -m "$machine_type" --devcontainer-path "$devcontainer_path" $default_permissions 2>&1); then
        # Check if the failure is due to permissions authorization required
        if echo "$codespace_output" | grep -q "You must authorize or deny additional permissions"; then
            print_error "Codespace creation requires additional permissions authorization"
            print_error "Please authorize the permissions in your browser, then try again"
            # Extract and display the authorization URL if present
            local auth_url
            auth_url=$(echo "$codespace_output" | grep -o "https://github\.com/[^[:space:]]*")
            if [ -n "$auth_url" ]; then
                print_status "Authorization URL: $auth_url"
            fi
            print_warning "Alternatively, you can rerun this script with --default-permissions option"
            return 1
        else
            print_error "Failed to create codespace"
            print_error "$codespace_output"
            return 1
        fi
    fi
    
    # Extract the codespace name (last line of output)
    local codespace_name
    codespace_name=$(echo "$codespace_output" | tail -n 1 | tr -d '\r\n')
    
    print_status "Codespace created successfully: $codespace_name"
    echo "$codespace_name"
    return 0
}
