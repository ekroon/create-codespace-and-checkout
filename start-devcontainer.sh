#!/bin/bash
#
# Start a devcontainer with dotfiles support using the devcontainer CLI.
# This script wraps `devcontainer up` to provide the same dotfiles functionality
# that was previously handled in post-create.sh.
#
# Usage:
#   ./start-devcontainer.sh                           # Interactive mode
#   ./start-devcontainer.sh -w /path/to/workspace     # Specify workspace
#   ./start-devcontainer.sh -r owner/dotfiles-repo    # Custom dotfiles repo
#   ./start-devcontainer.sh -x                        # Skip prompts (use defaults)
#
set -e

# Default configuration
DEFAULT_DOTFILES_REPO="ekroon/dotfiles"
# Note: Keep ~/dotfiles as literal string - devcontainer CLI expands it inside the container
# shellcheck disable=SC2088
DEFAULT_DOTFILES_TARGET='~/dotfiles'
DEFAULT_DOTFILES_INSTALL_COMMAND="install.sh"

# Script variables
WORKSPACE_FOLDER=""
DOTFILES_REPO=""
DOTFILES_TARGET=""
DOTFILES_INSTALL_CMD=""
SKIP_PROMPTS=false
EXTRA_ARGS=()

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

print_status() {
    echo "==> $1"
}

print_error() {
    echo "ERROR: $1" >&2
}

print_warning() {
    echo "WARNING: $1" >&2
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Start a devcontainer with dotfiles support using the devcontainer CLI.

Options:
    -w, --workspace-folder PATH    Workspace folder path (default: current directory)
    -r, --dotfiles-repo REPO       Dotfiles repository (default: $DEFAULT_DOTFILES_REPO)
                                   Can be a full URL or owner/repo shorthand
    -t, --dotfiles-target PATH     Path to clone dotfiles to (default: $DEFAULT_DOTFILES_TARGET)
    -i, --dotfiles-install CMD     Install command to run (default: $DEFAULT_DOTFILES_INSTALL_COMMAND)
    -n, --no-dotfiles              Skip dotfiles installation
    -x, --skip-prompts             Use defaults without prompting
    -h, --help                     Show this help message

Examples:
    $(basename "$0")
    $(basename "$0") -w ./my-project
    $(basename "$0") -r https://github.com/myuser/dotfiles.git
    $(basename "$0") -r myuser/dotfiles -i bootstrap.sh
    $(basename "$0") -x -w ./my-project

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

    if ! command -v docker &>/dev/null; then
        missing_deps+=("docker")
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
            -r|--dotfiles-repo)
                DOTFILES_REPO="$2"
                shift 2
                ;;
            -t|--dotfiles-target)
                DOTFILES_TARGET="$2"
                shift 2
                ;;
            -i|--dotfiles-install)
                DOTFILES_INSTALL_CMD="$2"
                shift 2
                ;;
            -n|--no-dotfiles)
                DOTFILES_REPO="SKIP"
                shift
                ;;
            -x|--skip-prompts)
                SKIP_PROMPTS=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            -*)
                # Pass unknown flags to devcontainer
                EXTRA_ARGS+=("$1")
                shift
                ;;
            *)
                # Assume positional arg is workspace folder
                if [ -z "$WORKSPACE_FOLDER" ]; then
                    WORKSPACE_FOLDER="$1"
                else
                    EXTRA_ARGS+=("$1")
                fi
                shift
                ;;
        esac
    done

    # Set defaults
    WORKSPACE_FOLDER="${WORKSPACE_FOLDER:-.}"
    
    if [ "$DOTFILES_REPO" != "SKIP" ]; then
        DOTFILES_REPO="${DOTFILES_REPO:-$DEFAULT_DOTFILES_REPO}"
        DOTFILES_TARGET="${DOTFILES_TARGET:-$DEFAULT_DOTFILES_TARGET}"
        DOTFILES_INSTALL_CMD="${DOTFILES_INSTALL_CMD:-$DEFAULT_DOTFILES_INSTALL_COMMAND}"
    fi
}

# -----------------------------------------------------------------------------
# Interactive prompts
# -----------------------------------------------------------------------------

prompt_configuration() {
    if [ "$SKIP_PROMPTS" = true ]; then
        return
    fi

    # Check if gum is available for nicer prompts
    if command -v gum &>/dev/null; then
        prompt_with_gum
    else
        prompt_basic
    fi
}

prompt_with_gum() {
    echo ""
    gum style --bold "Devcontainer Configuration"
    echo ""

    # Workspace folder
    WORKSPACE_FOLDER=$(gum input \
        --placeholder "$WORKSPACE_FOLDER" \
        --value "$WORKSPACE_FOLDER" \
        --header "Workspace folder:")
    
    if [ "$DOTFILES_REPO" != "SKIP" ]; then
        # Ask if user wants dotfiles
        if gum confirm "Install dotfiles?"; then
            DOTFILES_REPO=$(gum input \
                --placeholder "$DOTFILES_REPO" \
                --value "$DOTFILES_REPO" \
                --header "Dotfiles repository (owner/repo or URL):")
            
            DOTFILES_INSTALL_CMD=$(gum input \
                --placeholder "$DOTFILES_INSTALL_CMD" \
                --value "$DOTFILES_INSTALL_CMD" \
                --header "Install command (leave empty for auto-detect):")
            
            DOTFILES_TARGET=$(gum input \
                --placeholder "$DOTFILES_TARGET" \
                --value "$DOTFILES_TARGET" \
                --header "Dotfiles target path:")
        else
            DOTFILES_REPO="SKIP"
        fi
    fi
}

prompt_basic() {
    echo ""
    echo "Devcontainer Configuration"
    echo "=========================="
    echo ""

    read -r -p "Workspace folder [$WORKSPACE_FOLDER]: " input
    WORKSPACE_FOLDER="${input:-$WORKSPACE_FOLDER}"

    if [ "$DOTFILES_REPO" != "SKIP" ]; then
        read -r -p "Install dotfiles? [Y/n]: " input
        if [[ "${input,,}" == "n" ]]; then
            DOTFILES_REPO="SKIP"
        else
            read -r -p "Dotfiles repository [$DOTFILES_REPO]: " input
            DOTFILES_REPO="${input:-$DOTFILES_REPO}"

            read -r -p "Install command [$DOTFILES_INSTALL_CMD]: " input
            DOTFILES_INSTALL_CMD="${input:-$DOTFILES_INSTALL_CMD}"

            read -r -p "Dotfiles target path [$DOTFILES_TARGET]: " input
            DOTFILES_TARGET="${input:-$DOTFILES_TARGET}"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Main logic
# -----------------------------------------------------------------------------

start_devcontainer() {
    local cmd=(devcontainer up --workspace-folder "$WORKSPACE_FOLDER")

    # Add dotfiles configuration if not skipped
    if [ "$DOTFILES_REPO" != "SKIP" ]; then
        cmd+=(--dotfiles-repository "$DOTFILES_REPO")
        
        if [ -n "$DOTFILES_INSTALL_CMD" ]; then
            cmd+=(--dotfiles-install-command "$DOTFILES_INSTALL_CMD")
        fi
        
        if [ -n "$DOTFILES_TARGET" ]; then
            cmd+=(--dotfiles-target-path "$DOTFILES_TARGET")
        fi
    fi

    # Add any extra arguments
    if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
        cmd+=("${EXTRA_ARGS[@]}")
    fi

    print_status "Starting devcontainer..."
    echo "Command: ${cmd[*]}"
    echo ""

    "${cmd[@]}"
}

main() {
    check_dependencies
    parse_args "$@"
    prompt_configuration
    start_devcontainer
}

main "$@"
