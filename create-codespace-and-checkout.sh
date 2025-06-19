#!/bin/bash

# Script to create a new codespace and checkout a git branch
# Usage: ./create-codespace-and-checkout.sh [branch-name]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show a simple spinner
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Check if branch name is provided
BRANCH_NAME=${1:-""}

if [ -z "$BRANCH_NAME" ]; then
    read -p "Enter the branch name to checkout: " BRANCH_NAME
    if [ -z "$BRANCH_NAME" ]; then
        print_error "Branch name is required"
        exit 1
    fi
fi

print_status "Starting codespace creation process..."

# Step 1: Create the codespace and capture the output
print_status "Creating new codespace with xLargePremiumLinux machine type..."
CODESPACE_OUTPUT=$(gh cs create -R github/github -m xLargePremiumLinux --devcontainer-path .devcontainer/devcontainer.json 2>&1)

if [ $? -ne 0 ]; then
    print_error "Failed to create codespace"
    print_error "$CODESPACE_OUTPUT"
    exit 1
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
    if gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'test -d /workspaces/github && cd /workspaces/github && pwd'" >/dev/null 2>&1; then
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
printf "${GREEN}[INFO]${NC} Fetching latest remote information..."
gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'cd /workspaces/github && git fetch origin'" >/dev/null 2>&1 &
FETCH_PID=$!

# Show spinner while fetching
show_spinner $FETCH_PID
wait $FETCH_PID
FETCH_EXIT_CODE=$?

if [ $FETCH_EXIT_CODE -eq 0 ]; then
    echo " ✓"
else
    echo " ✗"
    print_error "Failed to fetch from remote. Git authentication may not be ready yet."
    print_warning "Try connecting to the codespace manually: gh cs ssh -c $CODESPACE_NAME"
    exit 1
fi

print_status "Checking if branch '$BRANCH_NAME' exists remotely..."
REMOTE_CHECK=$(gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'cd /workspaces/github && git ls-remote --heads origin $BRANCH_NAME'" 2>/dev/null || echo "")

# Step 4: Checkout the branch
if [ -n "$REMOTE_CHECK" ]; then
    print_status "Branch '$BRANCH_NAME' exists remotely, checking out..."
    gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'cd /workspaces/github && git checkout $BRANCH_NAME'" >/dev/null 2>&1
else
    print_warning "Branch '$BRANCH_NAME' doesn't exist remotely. Creating new branch..."
    gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'cd /workspaces/github && git checkout -b $BRANCH_NAME'" >/dev/null 2>&1
fi

if [ $? -eq 0 ]; then
    print_status "Successfully checked out branch '$BRANCH_NAME' in codespace '$CODESPACE_NAME'"
else
    print_error "Failed to checkout branch '$BRANCH_NAME'"
    print_warning "Codespace '$CODESPACE_NAME' was created but branch checkout failed"
    exit 1
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
