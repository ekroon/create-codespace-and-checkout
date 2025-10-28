#!/bin/bash

# Script to create a new codespace and checkout a git branch
# Usage: ./create-codespace-and-checkout.sh [options] [branch-name]
# Options:
#   -R <repo>               Repository (default: github/github, env: REPO)
#   -m <machine-type>       Codespace machine type (default: xLargePremiumLinux, env: CODESPACE_SIZE)
#   --devcontainer-path <path>  Path to devcontainer (default: .devcontainer/devcontainer.json, env: DEVCONTAINER_PATH)
#   --default-permissions   Use default permissions without authorization prompt

# set -e  # Exit on any error

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the library modules
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
# shellcheck source=create-codespace.sh
source "$SCRIPT_DIR/create-codespace.sh"
# shellcheck source=codespace-commands.sh
source "$SCRIPT_DIR/codespace-commands.sh"

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
  --devcontainer-path <path>   Path to devcontainer (default: .devcontainer/devcontainer.json, env: DEVCONTAINER_PATH)
  --default-permissions        Use default permissions without authorization prompt
  -x, --immediate              Skip interactive prompts for unspecified options (use defaults)
  -h, --help                   Show this help message and exit

Environment Variables:
  REPO                         Override default repository
  CODESPACE_SIZE              Override default machine type
  DEVCONTAINER_PATH           Override default devcontainer path
  GUM_LOG_*                   Customize log formatting (see gum log documentation)

Examples:
  ./create-codespace-and-checkout.sh -b my-branch
  ./create-codespace-and-checkout.sh -R myorg/myrepo -m large -b my-branch
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
init_gum_logging

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
        CODESPACE_SIZE_INPUT=$(mise x ubi:charmbracelet/gum -- gum input --prompt "Machine type: " --placeholder "xLargePremiumLinux") || exit 130
        if [ -n "$CODESPACE_SIZE_INPUT" ]; then
            CODESPACE_SIZE="$CODESPACE_SIZE_INPUT"
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
    if [ -z "$BRANCH_NAME" ]; then
        BRANCH_NAME=$(mise x ubi:charmbracelet/gum -- gum input --prompt "Branch name (optional): " --placeholder "Leave empty to skip checkout") || exit 130
    fi
fi

# Branch name is optional - if not provided, skip checkout step

print_status "Starting codespace creation process..."

# Step 1: Create the codespace
if ! CODESPACE_NAME=$(create_codespace "$REPO" "$CODESPACE_SIZE" "$DEVCONTAINER_PATH" "$DEFAULT_PERMISSIONS"); then
    exit 1
fi

# Step 2: Wait for the codespace to be fully ready
if ! wait_for_codespace_ready "$CODESPACE_NAME" "$REPO_NAME"; then
    exit 1
fi

# Step 3: Fetch latest remote information (silently with progress indicator)
if ! fetch_remote "$CODESPACE_NAME" "$REPO_NAME"; then
    exit 1
fi

# Upload terminfo for terminal compatibility
upload_terminfo "$CODESPACE_NAME" "xterm-ghostty"

# Step 4: Checkout the branch (optional - skip if no branch name provided)
if [ -n "$BRANCH_NAME" ]; then
    if ! checkout_branch "$CODESPACE_NAME" "$REPO_NAME" "$BRANCH_NAME"; then
        exit 1
    fi
else
    print_status "No branch name provided, skipping checkout step"
    print_status "Codespace will use the default branch"
fi

# Step 5: Wait for codespace configuration to complete
wait_for_configuration_complete "$CODESPACE_NAME"

if [ -n "$BRANCH_NAME" ]; then
    print_status "Setup complete! Your codespace is ready with branch '$BRANCH_NAME' checked out."
else
    print_status "Setup complete! Your codespace is ready with the default branch."
fi
print_status "Connect with: gh cs ssh -c $CODESPACE_NAME"
