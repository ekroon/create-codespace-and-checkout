#!/bin/bash

# Script to create a new codespace and checkout a git branch
# Usage: ./create-codespace-and-checkout.sh [options] [branch-name]
# Options:
#   -R <repo>               Repository (default: github/github, env: REPO)
#   -m <machine-type>       Codespace machine type (default: xLargePremiumLinux, env: CODESPACE_SIZE)
#   -d <display-name>       Display name for codespace (48 chars max, env: CODESPACE_DISPLAY_NAME)
#   --devcontainer-path <path>  Path to devcontainer (default: .devcontainer/devcontainer.json, env: DEVCONTAINER_PATH)
#   --default-permissions   Use default permissions without authorization prompt

# set -e  # Exit on any error

# Signal handler for clean exit on CTRL-C (SIGINT) and SIGTERM
cleanup_on_exit() {
    echo ""
    echo "Interrupted. Exiting..."
    exit 130
}

# Trap SIGINT (CTRL-C) and SIGTERM
trap cleanup_on_exit SIGINT SIGTERM

# Function to show help/usage information (defined early so it can be called before dependency checks)
show_help() {
    cat << EOF
Usage: ./create-codespace-and-checkout.sh [options]

Create a GitHub Codespace and optionally checkout a git branch.

Options:
  -b <branch>                  Branch name to checkout (optional, if not provided uses default branch)
  -R <repo>                    Repository (default: github/github, env: REPO)
  -m <machine-type>            Codespace machine type (default: xLargePremiumLinux, env: CODESPACE_SIZE)
  -d <display-name>            Display name for the codespace (48 characters or less, env: CODESPACE_DISPLAY_NAME)
  --devcontainer-path <path>   Path to devcontainer (default: .devcontainer/devcontainer.json, env: DEVCONTAINER_PATH)
  --default-permissions        Use default permissions without authorization prompt
  -x, --immediate              Skip interactive prompts for unspecified options (use defaults)
  -h, --help                   Show this help message and exit

Environment Variables:
  REPO                         Override default repository
  CODESPACE_SIZE              Override default machine type
  CODESPACE_DISPLAY_NAME      Override display name for codespace
  DEVCONTAINER_PATH           Override default devcontainer path
  GUM_LOG_*                   Customize log formatting (see gum log documentation)

Examples:
  ./create-codespace-and-checkout.sh -b my-branch
  ./create-codespace-and-checkout.sh -R myorg/myrepo -m large -b my-branch
  ./create-codespace-and-checkout.sh -d "my-feature-work" -b my-branch
  ./create-codespace-and-checkout.sh -x -b my-branch  # Skip interactive prompts
  ./create-codespace-and-checkout.sh  # Interactive mode, branch optional
  REPO=myorg/myrepo ./create-codespace-and-checkout.sh -x  # Use defaults, no branch checkout
EOF
    exit 0
}

# Check for help option first (before dependency checks)
for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
        show_help
    fi
done

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

# Helper function to set gum log style defaults
_gum_set_default() {
    # $1 = var name, $2 = default value
    if [ -z "${!1+x}" ]; then
        export "$1=$2"
    fi
}

# Set default gum log styling (can be overridden via environment)
_gum_set_default GUM_LOG_LEVEL_FOREGROUND 212
_gum_set_default GUM_LOG_LEVEL_BOLD true
_gum_set_default GUM_LOG_TIME_FOREGROUND 244
_gum_set_default GUM_LOG_MESSAGE_FOREGROUND 254
_gum_set_default GUM_LOG_KEY_FOREGROUND 240
_gum_set_default GUM_LOG_VALUE_FOREGROUND 118
_gum_set_default GUM_LOG_SEPARATOR_FOREGROUND 240

# Function to print status messages using gum log with structured formatting
print_status() {
    mise x ubi:charmbracelet/gum -- gum log --structured --level info --time rfc822 "$1"
}

print_warning() {
    mise x ubi:charmbracelet/gum -- gum log --structured --level warn --time rfc822 "$1"
}

print_error() {
    mise x ubi:charmbracelet/gum -- gum log --structured --level error --time rfc822 "$1"
}

# Fetch available machine types for a repository
# Usage: _fetch_machine_types <repo>
# Returns machine types as newline-separated list, or empty on failure
_fetch_machine_types() {
    local repo=$1
    gh api "/repos/$repo/machines" --jq '.machines[].name' 2>/dev/null
}

# Generic retry function for waiting on conditions
# Usage: retry_until <max_attempts> <sleep_seconds> <description> <command>
retry_until() {
    local max_attempts=$1
    local sleep_seconds=$2
    local description=$3
    shift 3
    local command=("$@")
    
    local attempt=1
    while [ $attempt -le "$max_attempts" ]; do
        print_status "$description (attempt $attempt/$max_attempts)..."
        
        if "${command[@]}" >/dev/null 2>&1; then
            return 0
        fi
        
        if [ $attempt -eq "$max_attempts" ]; then
            return 1
        fi
        
        sleep "$sleep_seconds"
        attempt=$((attempt + 1))
    done
}

# Set defaults from environment variables or use built-in defaults
REPO=${REPO:-"github/github"}
CODESPACE_SIZE=${CODESPACE_SIZE:-"xLargePremiumLinux"}
DEVCONTAINER_PATH=${DEVCONTAINER_PATH:-".devcontainer/devcontainer.json"}
DISPLAY_NAME=${CODESPACE_DISPLAY_NAME:-""}
DEFAULT_PERMISSIONS=""
BRANCH_NAME=""
IMMEDIATE_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -b)
            BRANCH_NAME="$2"
            shift 2
            ;;
        -R)
            REPO="$2"
            shift 2
            ;;
        -m)
            CODESPACE_SIZE="$2"
            shift 2
            ;;
        -d)
            DISPLAY_NAME="$2"
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
        -x|--immediate)
            IMMEDIATE_MODE=true
            shift
            ;;
        -*)
            print_error "Unknown option: $1"
            echo "Use --help to see available options"
            exit 1
            ;;
        *)
            print_error "Unexpected argument: $1"
            echo "Use -b <branch> to specify a branch name"
            echo "Use --help to see available options"
            exit 1
            ;;
    esac
done

# Extract repository name from REPO (e.g., "github/github" -> "github")
REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)

# Interactive mode: prompt for unspecified options unless immediate mode is enabled
if [ "$IMMEDIATE_MODE" = false ]; then
    # Prompt for repository if not specified
    if [ "$REPO" = "github/github" ]; then
        REPO_INPUT=$(mise x ubi:charmbracelet/gum -- gum input --prompt "Repository: " --placeholder "github/github") || exit 130
        if [ -n "$REPO_INPUT" ]; then
            REPO="$REPO_INPUT"
            REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
        fi
    fi
    
    # Prompt for machine type if not specified
    if [ "$CODESPACE_SIZE" = "xLargePremiumLinux" ]; then
        MACHINE_TYPES=$(_fetch_machine_types "$REPO")
        if [ -n "$MACHINE_TYPES" ]; then
            # Use gum choose with fetched machine types, pre-selecting the default
            CODESPACE_SIZE_INPUT=$(echo "$MACHINE_TYPES" | mise x ubi:charmbracelet/gum -- gum choose --header "Select machine type:" --selected "$CODESPACE_SIZE") || exit 130
            if [ -n "$CODESPACE_SIZE_INPUT" ]; then
                CODESPACE_SIZE="$CODESPACE_SIZE_INPUT"
            fi
        else
            # Fallback to text input if API call fails
            print_warning "Could not fetch machine types from API, using text input"
            CODESPACE_SIZE_INPUT=$(mise x ubi:charmbracelet/gum -- gum input --prompt "Machine type: " --placeholder "xLargePremiumLinux") || exit 130
            if [ -n "$CODESPACE_SIZE_INPUT" ]; then
                CODESPACE_SIZE="$CODESPACE_SIZE_INPUT"
            fi
        fi
    fi
    
    # Prompt for devcontainer path if not specified
    if [ "$DEVCONTAINER_PATH" = ".devcontainer/devcontainer.json" ]; then
        DEVCONTAINER_PATH_INPUT=$(mise x ubi:charmbracelet/gum -- gum input --prompt "Devcontainer path: " --placeholder ".devcontainer/devcontainer.json") || exit 130
        if [ -n "$DEVCONTAINER_PATH_INPUT" ]; then
            DEVCONTAINER_PATH="$DEVCONTAINER_PATH_INPUT"
        fi
    fi
    
    # Prompt for branch name if not specified (optional)
    # Note: Branch name is prompted before display name so we can use it as default
    if [ -z "$BRANCH_NAME" ]; then
        BRANCH_NAME=$(mise x ubi:charmbracelet/gum -- gum input --prompt "Branch name (optional): " --placeholder "Leave empty to skip checkout") || exit 130
    fi
    
    # Prompt for display name if not specified (optional)
    # Default to branch name (truncated to 48 chars) if branch is set
    if [ -z "$DISPLAY_NAME" ]; then
        default_display_name=""
        if [ -n "$BRANCH_NAME" ]; then
            default_display_name="${BRANCH_NAME:0:48}"
        fi
        DISPLAY_NAME=$(mise x ubi:charmbracelet/gum -- gum input --prompt "Display name (optional): " --value "$default_display_name" --placeholder "Leave empty for auto-generated name") || exit 130
    fi
fi

# Auto-set display name from branch name when not specified
# This applies to both immediate mode and when branch was provided via -b flag
if [ -z "$DISPLAY_NAME" ] && [ -n "$BRANCH_NAME" ]; then
    DISPLAY_NAME="${BRANCH_NAME:0:48}"
fi

# Branch name is optional - if not provided, skip checkout step

print_status "Starting codespace creation process..."

# Step 1: Create the codespace and capture the output
# Build display name flag conditionally
DISPLAY_NAME_FLAG=()
if [ -n "$DISPLAY_NAME" ]; then
    DISPLAY_NAME_FLAG=("--display-name" "$DISPLAY_NAME")
fi

print_status "Creating new codespace with $CODESPACE_SIZE machine type..."
if ! CODESPACE_OUTPUT=$(gh cs create -R "$REPO" -m "$CODESPACE_SIZE" --devcontainer-path "$DEVCONTAINER_PATH" "${DISPLAY_NAME_FLAG[@]}" $DEFAULT_PERMISSIONS 2>&1); then
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

if ! retry_until 30 10 "Checking codespace readiness" \
    gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'test -d /workspaces/$REPO_NAME && cd /workspaces/$REPO_NAME && pwd'"; then
    print_error "Codespace failed to become ready after 30 attempts"
    exit 1
fi

print_status "Codespace is ready!"

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

# Step 4: Checkout the branch (optional - skip if no branch name provided)
if [ -n "$BRANCH_NAME" ]; then
    print_status "Checking if branch '$BRANCH_NAME' exists remotely..."
    REMOTE_CHECK=$(gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'cd /workspaces/$REPO_NAME && git ls-remote --heads origin $BRANCH_NAME'" 2>/dev/null || echo "")
    
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
            print_status "Successfully created and checked out branch '$BRANCH_NAME' in codespace '$CODESPACE_NAME'"
        else
            print_error "Failed to create branch '$BRANCH_NAME'"
            print_warning "Codespace '$CODESPACE_NAME' was created but branch creation failed"
            exit 1
        fi
    fi
else
    print_status "No branch name provided, skipping checkout step"
    print_status "Codespace will use the default branch"
fi

# Step 5: Wait for codespace configuration to complete
print_status "Waiting for codespace configuration to complete..."

# Helper function to check if configuration is complete
_check_config_complete() {
    local last_log
    last_log=$(gh cs logs --codespace "$CODESPACE_NAME" 2>/dev/null | tail -n 1 || echo "")
    [[ "$last_log" == *"Finished configuring codespace."* ]]
}

if retry_until 60 10 "Checking configuration status" _check_config_complete; then
    print_status "Codespace configuration complete! ✓"
else
    print_warning "Codespace configuration did not complete after 60 attempts"
    print_warning "The codespace may still be configuring in the background"
fi

if [ -n "$BRANCH_NAME" ]; then
    print_status "Setup complete! Your codespace is ready with branch '$BRANCH_NAME' checked out."
else
    print_status "Setup complete! Your codespace is ready with the default branch."
fi
print_status "Connect with: gh cs ssh -c $CODESPACE_NAME"
