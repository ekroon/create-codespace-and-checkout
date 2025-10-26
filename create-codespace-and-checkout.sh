#!/bin/bash

# Script to create a new codespace and checkout a git branch
# Usage: ./create-codespace-and-checkout.sh [options] [branch-name]
# Options:
#   -R <repo>               Repository (default: github/github, env: REPO)
#   -m <machine-type>       Codespace machine type (default: xLargePremiumLinux, env: CODESPACE_SIZE)
#   --devcontainer-path <path>  Path to devcontainer (default: .devcontainer/devcontainer.json, env: DEVCONTAINER_PATH)
#   --default-permissions   Use default permissions without authorization prompt

# set -e  # Exit on any error

# Check for required dependencies
MISSING_DEPS=()

if ! command -v gh >/dev/null 2>&1; then
    MISSING_DEPS+=("gh")
fi

if ! command -v mise >/dev/null 2>&1; then
    MISSING_DEPS+=("mise")
fi

if ! command -v infocmp >/dev/null 2>&1; then
    MISSING_DEPS+=("infocmp")
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo "[ERROR] Missing required dependencies: ${MISSING_DEPS[*]}"
    exit 1
fi

# Function to print status messages using gum log
print_status() {
    mise x ubi:charmbracelet/gum -- gum log --level info "$1"
}

print_warning() {
    mise x ubi:charmbracelet/gum -- gum log --level warn "$1"
}

print_error() {
    mise x ubi:charmbracelet/gum -- gum log --level error "$1"
}

# Set defaults from environment variables or use built-in defaults
REPO=${REPO:-"github/github"}
CODESPACE_SIZE=${CODESPACE_SIZE:-"xLargePremiumLinux"}
DEVCONTAINER_PATH=${DEVCONTAINER_PATH:-".devcontainer/devcontainer.json"}
DEFAULT_PERMISSIONS=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -R)
            REPO="$2"
            shift 2
            ;;
        -m)
            CODESPACE_SIZE="$2"
            shift 2
            ;;
        --devcontainer-path)
            DEVCONTAINER_PATH="$2"
            shift 2
            ;;
        --default-permissions)
            DEFAULT_PERMISSIONS="--default-permissions"
            shift
            ;;
        -*)
            print_error "Unknown option: $1"
            exit 1
            ;;
        *)
            # This is the branch name
            BRANCH_NAME="$1"
            shift
            ;;
    esac
done

# Check if branch name is provided
BRANCH_NAME=${BRANCH_NAME:-""}

# Extract repository name from REPO (e.g., "github/github" -> "github")
REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)

if [ -z "$BRANCH_NAME" ]; then
    BRANCH_NAME=$(mise x ubi:charmbracelet/gum -- gum input --placeholder "Enter the branch name to checkout")
    if [ -z "$BRANCH_NAME" ]; then
        print_error "Branch name is required"
        exit 1
    fi
fi

print_status "Starting codespace creation process..."

# Step 1: Create the codespace and capture the output
print_status "Creating new codespace with $CODESPACE_SIZE machine type..."
if ! CODESPACE_OUTPUT=$(gh cs create -R "$REPO" -m "$CODESPACE_SIZE" --devcontainer-path "$DEVCONTAINER_PATH" $DEFAULT_PERMISSIONS 2>&1); then
    # Check if the failure is due to permissions authorization required
    if echo "$CODESPACE_OUTPUT" | grep -q "You must authorize or deny additional permissions"; then
        print_error "Codespace creation requires additional permissions authorization"
        print_error "Please authorize the permissions in your browser, then try again"
        # Extract and display the authorization URL if present
        AUTH_URL=$(echo "$CODESPACE_OUTPUT" | grep -o "https://github\.com/[^[:space:]]*")
        if [ -n "$AUTH_URL" ]; then
            print_status "Authorization URL: $AUTH_URL"
        fi
        print_warning "Alternatively, you can rerun this script with --default-permissions option"
        exit 1
    else
        print_error "Failed to create codespace"
        print_error "$CODESPACE_OUTPUT"
        exit 1
    fi
fi


# Extract the codespace name (last line of output)
CODESPACE_NAME=$(echo "$CODESPACE_OUTPUT" | tail -n 1 | tr -d '\r\n')

print_status "Codespace created successfully: $CODESPACE_NAME"

# Step 2: Wait for the codespace to be fully ready
print_status "Waiting for codespace to be fully ready..."
MAX_ATTEMPTS=30
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    print_status "Checking codespace readiness (attempt $ATTEMPT/$MAX_ATTEMPTS)..."
    
    # Check if we can successfully connect and the workspace is ready
    if gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'test -d /workspaces/$REPO_NAME && cd /workspaces/$REPO_NAME && pwd'" >/dev/null 2>&1; then
        print_status "Codespace is ready!"
        break
    fi
    
    if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        print_error "Codespace failed to become ready after $MAX_ATTEMPTS attempts"
        exit 1
    fi
    
    sleep 10
    ATTEMPT=$((ATTEMPT + 1))
done

# Step 3: Fetch latest remote information (silently with progress indicator)
mise x ubi:charmbracelet/gum -- gum spin --spinner dot --title "Fetching latest remote information..." -- gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'cd /workspaces/$REPO_NAME && git fetch origin'"
FETCH_EXIT_CODE=$?

if [ $FETCH_EXIT_CODE -ne 0 ]; then
    print_error "Failed to fetch from remote. Git authentication may not be ready yet."
    print_warning "Try connecting to the codespace manually: gh cs ssh -c $CODESPACE_NAME"
    exit 1
fi

print_status "Uploading xterm-ghostty terminfo to codespace..."
if infocmp -x xterm-ghostty | gh cs ssh -c "$CODESPACE_NAME" -- tic -x - >/dev/null 2>&1; then
    print_status "Successfully uploaded xterm-ghostty terminfo."
else
    print_warning "Failed to upload xterm-ghostty terminfo. Terminal features may be limited."
fi

print_status "Checking if branch '$BRANCH_NAME' exists remotely..."
REMOTE_CHECK=$(gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'cd /workspaces/$REPO_NAME && git ls-remote --heads origin $BRANCH_NAME'" 2>/dev/null || echo "")

# Step 4: Checkout the branch
if [ -n "$REMOTE_CHECK" ]; then
    print_status "Branch '$BRANCH_NAME' exists remotely, checking out..."
    if gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'cd /workspaces/$REPO_NAME && git checkout \"$BRANCH_NAME\"'" >/dev/null 2>&1; then
        print_status "Successfully checked out branch '$BRANCH_NAME' in codespace '$CODESPACE_NAME'"
    else
        print_error "Failed to checkout branch '$BRANCH_NAME'"
        print_warning "Codespace '$CODESPACE_NAME' was created but branch checkout failed"
        exit 1
    fi
else
    print_warning "Branch '$BRANCH_NAME' doesn't exist remotely. Creating new branch..."
    if gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'cd /workspaces/$REPO_NAME && git checkout -b \"$BRANCH_NAME\"'" >/dev/null 2>&1; then
        print_status "Successfully checked out branch '$BRANCH_NAME' in codespace '$CODESPACE_NAME'"
    else
        print_error "Failed to checkout branch '$BRANCH_NAME'"
        print_warning "Codespace '$CODESPACE_NAME' was created but branch checkout failed"
        exit 1
    fi
fi

# Step 5: Wait for codespace configuration to complete
print_status "Waiting for codespace configuration to complete..."
CONFIG_MAX_ATTEMPTS=60  # 10 minutes total (60 * 10 seconds)
CONFIG_ATTEMPT=1

while [ $CONFIG_ATTEMPT -le $CONFIG_MAX_ATTEMPTS ]; do
    print_status "Checking configuration status (attempt $CONFIG_ATTEMPT/$CONFIG_MAX_ATTEMPTS)..."
    
    # Check the last log line to see if configuration is finished
    LAST_LOG=$(gh cs logs --codespace "$CODESPACE_NAME" | tail -n 1 2>/dev/null || echo "")
    
    if [[ "$LAST_LOG" == *"Finished configuring codespace."* ]]; then
        print_status "Codespace configuration complete! ✓"
        break
    fi
    
    if [ $CONFIG_ATTEMPT -eq $CONFIG_MAX_ATTEMPTS ]; then
        print_warning "Codespace configuration did not complete after $CONFIG_MAX_ATTEMPTS attempts"
        print_warning "The codespace may still be configuring in the background"
        break
    fi
    
    sleep 10
    CONFIG_ATTEMPT=$((CONFIG_ATTEMPT + 1))
done

print_status "Setup complete! Your codespace is ready with branch '$BRANCH_NAME' checked out."
print_status "Connect with: gh cs ssh -c $CODESPACE_NAME"
