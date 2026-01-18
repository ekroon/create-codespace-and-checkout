#!/bin/bash
#
# Connect to a running devcontainer with GH_TOKEN set for GitHub authentication.
# This script ensures the GH_TOKEN environment variable is available inside the container.
#
# Usage:
#   ./connect-devcontainer.sh                    # Connect to devcontainer in current directory
#   ./connect-devcontainer.sh -w /path/to/workspace  # Specify workspace folder
#   ./connect-devcontainer.sh -s                 # Start container if not running, then connect
#
set -e

# Script variables
WORKSPACE_FOLDER="."
START_IF_NEEDED=false

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

print_status() {
    echo "==> $1"
}

print_error() {
    echo "ERROR: $1" >&2
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Connect to a running devcontainer with GitHub authentication configured.

Options:
    -w, --workspace-folder PATH    Workspace folder path (default: current directory)
    -s, --start                    Start the container if not running
    -h, --help                     Show this help message

Examples:
    $(basename "$0")
    $(basename "$0") -w ./my-project
    $(basename "$0") -s -w ./my-project

EOF
    exit 0
}

# -----------------------------------------------------------------------------
# Dependency checks
# -----------------------------------------------------------------------------

check_dependencies() {
    local missing_deps=()

    if ! command -v devcontainer &>/dev/null; then
        missing_deps+=("devcontainer (install via: npm install -g @devcontainers/cli)")
    fi

    if ! command -v gh &>/dev/null; then
        missing_deps+=("gh (GitHub CLI)")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -w|--workspace-folder)
                WORKSPACE_FOLDER="$2"
                shift 2
                ;;
            -s|--start)
                START_IF_NEEDED=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                ;;
            *)
                # Assume positional arg is workspace folder
                WORKSPACE_FOLDER="$1"
                shift
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Main logic
# -----------------------------------------------------------------------------

get_gh_token() {
    if ! gh auth status &>/dev/null; then
        print_error "Not logged in to GitHub CLI. Run 'gh auth login' first."
        exit 1
    fi
    gh auth token
}

start_container() {
    print_status "Starting devcontainer..."
    export GH_TOKEN
    GH_TOKEN=$(get_gh_token)
    devcontainer up --workspace-folder "$WORKSPACE_FOLDER"
}

connect_to_container() {
    local gh_token
    gh_token=$(get_gh_token)

    print_status "Connecting to devcontainer in $WORKSPACE_FOLDER..."
    
    # Use devcontainer exec with remote-env to pass GH_TOKEN and start zsh
    devcontainer exec \
        --workspace-folder "$WORKSPACE_FOLDER" \
        --remote-env "GH_TOKEN=$gh_token" \
        zsh -l
}

main() {
    check_dependencies
    parse_args "$@"

    # Resolve workspace folder to absolute path
    WORKSPACE_FOLDER=$(cd "$WORKSPACE_FOLDER" && pwd)

    if [ "$START_IF_NEEDED" = true ]; then
        start_container
    fi

    connect_to_container
}

main "$@"
