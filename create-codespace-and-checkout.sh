#!/bin/bash

# Script to create a new codespace and checkout a git branch, or run setup on existing codespace
# Usage: ./create-codespace-and-checkout.sh [options]
#        ./create-codespace-and-checkout.sh -c <codespace-name> [options]  # Setup existing
#        ./create-codespace-and-checkout.sh --test-e2e [options]           # Create + cleanup test codespace
# Options:
#   -R <repo>               Repository (default: github/github, env: REPO)
#   -m <machine-type>       Codespace machine type (default: xLargePremiumLinux, env: CODESPACE_SIZE)
#   -d <display-name>       Display name for codespace (48 chars max, env: CODESPACE_DISPLAY_NAME)
#   -c <codespace-name>     Target existing codespace (skip creation)
#   --devcontainer-path <path>  Path to devcontainer (default: .devcontainer/devcontainer.json, env: DEVCONTAINER_PATH)
#   --default-permissions   Use default permissions without authorization prompt
#   --skip-hooks            Skip all hook execution
#   --test-e2e              Run an end-to-end test (auto-cleanup codespace)

# set -e  # Exit on any error

# =============================================================================
# Configuration System
# =============================================================================

# Configuration file location (XDG Base Directory spec)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/create-codespace-and-checkout"
CONFIG_FILE="$CONFIG_DIR/config.sh"

# Default configuration values
CONFIG_DEFAULT_REPO="github/github"
CONFIG_DEFAULT_CODESPACE_SIZE="xLargePremiumLinux"
CONFIG_DEFAULT_DEVCONTAINER_PATH=".devcontainer/devcontainer.json"

# Retry/timeout configuration
READY_MAX_ATTEMPTS=${READY_MAX_ATTEMPTS:-30}
READY_SLEEP_SECONDS=${READY_SLEEP_SECONDS:-10}
CONFIG_MAX_ATTEMPTS=${CONFIG_MAX_ATTEMPTS:-60}
CONFIG_SLEEP_SECONDS=${CONFIG_SLEEP_SECONDS:-10}

# Hook arrays (commands to run at each stage)
CONFIG_DEFAULT_LOCAL_PRE_HOOKS=()              # Run locally before anything
CONFIG_DEFAULT_LOCAL_POST_READY_HOOKS=()       # Run locally after codespace is ready
CONFIG_DEFAULT_REMOTE_PRE_CHECKOUT_HOOKS=()    # Run remotely before branch checkout
CONFIG_DEFAULT_REMOTE_POST_CHECKOUT_HOOKS=()   # Run remotely after branch checkout
CONFIG_DEFAULT_REMOTE_POST_CONFIG_HOOKS=()     # Run remotely after config complete

# Environment variables to inject into remote hooks
CONFIG_DEFAULT_REMOTE_ENV_VARS=()
CONFIG_DEFAULT_REMOTE_SECRET_VARS=()

# Skip built-in operations (default: false)
CONFIG_SKIP_GIT_CREDENTIAL_SETUP=${CONFIG_SKIP_GIT_CREDENTIAL_SETUP:-false}
CONFIG_SKIP_GIT_FETCH=${CONFIG_SKIP_GIT_FETCH:-false}

# Per-repo override arrays (populated by config_apply_repo_overrides)
CONFIG_REPO_CODESPACE_SIZE=""
CONFIG_REPO_DEVCONTAINER_PATH=""
CONFIG_REPO_LOCAL_PRE_HOOKS=()
CONFIG_REPO_LOCAL_POST_READY_HOOKS=()
CONFIG_REPO_REMOTE_PRE_CHECKOUT_HOOKS=()
CONFIG_REPO_REMOTE_POST_CHECKOUT_HOOKS=()
CONFIG_REPO_REMOTE_POST_CONFIG_HOOKS=()
CONFIG_REPO_REMOTE_ENV_VARS=()
CONFIG_REPO_REMOTE_SECRET_VARS=()

# Helper function for glob-based repo matching
repo_matches() {
    local repo="$1"
    local pattern="$2"
    # shellcheck disable=SC2053
    [[ "$repo" == $pattern ]]
}

# Load configuration file if it exists
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi
}

# Apply configuration with repo-specific overrides
apply_config() {
    local repo="$1"
    
    # Reset repo-specific overrides before applying
    CONFIG_REPO_CODESPACE_SIZE=""
    CONFIG_REPO_DEVCONTAINER_PATH=""
    CONFIG_REPO_LOCAL_PRE_HOOKS=()
    CONFIG_REPO_LOCAL_POST_READY_HOOKS=()
    CONFIG_REPO_REMOTE_PRE_CHECKOUT_HOOKS=()
    CONFIG_REPO_REMOTE_POST_CHECKOUT_HOOKS=()
    CONFIG_REPO_REMOTE_POST_CONFIG_HOOKS=()
    CONFIG_REPO_REMOTE_ENV_VARS=()
    CONFIG_REPO_REMOTE_SECRET_VARS=()
    
    # Start with defaults from config (or built-in defaults if not set)
    REPO="${REPO:-${CONFIG_DEFAULT_REPO:-github/github}}"
    CODESPACE_SIZE="${CODESPACE_SIZE:-${CONFIG_DEFAULT_CODESPACE_SIZE:-xLargePremiumLinux}}"
    DEVCONTAINER_PATH="${DEVCONTAINER_PATH:-${CONFIG_DEFAULT_DEVCONTAINER_PATH:-.devcontainer/devcontainer.json}}"
    
    # Call repo override function if defined in config
    if declare -F config_apply_repo_overrides >/dev/null 2>&1; then
        config_apply_repo_overrides "$repo"
    fi
    
    # Apply repo-specific overrides if set
    [ -n "$CONFIG_REPO_CODESPACE_SIZE" ] && CODESPACE_SIZE="$CONFIG_REPO_CODESPACE_SIZE"
    [ -n "$CONFIG_REPO_DEVCONTAINER_PATH" ] && DEVCONTAINER_PATH="$CONFIG_REPO_DEVCONTAINER_PATH"
}

# Merge arrays with repo values appended, preferring the last occurrence
_merge_array_prefer_last() {
    local -n result_array_ref="$1"
    shift
    local -a merged_items=()
    local item
    for item in "$@"; do
        if [ -n "$item" ]; then
            local -a filtered=()
            local existing
            for existing in "${merged_items[@]}"; do
                if [ "$existing" != "$item" ]; then
                    filtered+=("$existing")
                fi
            done
            merged_items=("${filtered[@]}" "$item")
        fi
    done
    result_array_ref=("${merged_items[@]}")
}

_cleanup_codespace_if_needed() {
    local codespace="$1"
    local result_code="$2"
    if [ "$TEST_E2E_MODE" = true ] && [ "$CREATED_CODESPACE" = true ] && [ -n "$codespace" ]; then
        print_status "Cleaning up codespace '$codespace'..."
        if ! gh cs delete -c "$codespace" >/dev/null 2>&1; then
            print_warning "Failed to delete codespace '$codespace'. Please remove it manually."
        fi
    fi
    return "$result_code"
}

# Get effective hooks (defaults + repo-specific)
# shellcheck disable=SC2178
get_hooks() {
    local hook_type="$1"
    local -n result_array_ref="$2"
    
    case "$hook_type" in
        local_pre)
            result_array_ref=("${CONFIG_DEFAULT_LOCAL_PRE_HOOKS[@]}" "${CONFIG_REPO_LOCAL_PRE_HOOKS[@]}")
            ;;
        local_post_ready)
            result_array_ref=("${CONFIG_DEFAULT_LOCAL_POST_READY_HOOKS[@]}" "${CONFIG_REPO_LOCAL_POST_READY_HOOKS[@]}")
            ;;
        remote_pre_checkout)
            result_array_ref=("${CONFIG_DEFAULT_REMOTE_PRE_CHECKOUT_HOOKS[@]}" "${CONFIG_REPO_REMOTE_PRE_CHECKOUT_HOOKS[@]}")
            ;;
        remote_post_checkout)
            result_array_ref=("${CONFIG_DEFAULT_REMOTE_POST_CHECKOUT_HOOKS[@]}" "${CONFIG_REPO_REMOTE_POST_CHECKOUT_HOOKS[@]}")
            ;;
        remote_post_config)
            result_array_ref=("${CONFIG_DEFAULT_REMOTE_POST_CONFIG_HOOKS[@]}" "${CONFIG_REPO_REMOTE_POST_CONFIG_HOOKS[@]}")
            ;;
        *)
            result_array_ref=()
            ;;
    esac
}

# Get effective environment variables for remote hooks
get_remote_env_vars() {
    # shellcheck disable=SC2178
    local -n result_array_ref="$1"
    _merge_array_prefer_last result_array_ref "${CONFIG_DEFAULT_REMOTE_ENV_VARS[@]}" "${CONFIG_REPO_REMOTE_ENV_VARS[@]}"
    : "${result_array_ref[@]}"
}

# Get effective secret variables for remote hooks
get_remote_secret_vars() {
    # shellcheck disable=SC2178
    local -n result_array_ref="$1"
    _merge_array_prefer_last result_array_ref "${CONFIG_DEFAULT_REMOTE_SECRET_VARS[@]}" "${CONFIG_REPO_REMOTE_SECRET_VARS[@]}"
    : "${result_array_ref[@]}"
}

_validate_required_arg() {
    local flag="$1"
    local value="$2"
    if [ -z "$value" ] || [[ "$value" == -* ]]; then
        print_error "Missing value for $flag"
        exit 1
    fi
}

_validate_repo_format() {
    local repo="$1"
    if [[ ! "$repo" =~ ^[^/]+/[^/]+$ ]]; then
        print_error "Invalid repository format: $repo"
        print_warning "Expected format: owner/name"
        exit 1
    fi
}

_validate_branch_name() {
    local branch="$1"
    if [[ -n "$branch" && "$branch" =~ [[:space:]] ]]; then
        print_error "Invalid branch name (contains whitespace): $branch"
        exit 1
    fi
}

# =============================================================================
# Hook Execution Functions
# =============================================================================

# Run local hooks (executed on the local machine)
run_local_hooks() {
    local stage="$1"
    local -a hooks
    get_hooks "$stage" hooks
    
    if [ ${#hooks[@]} -eq 0 ]; then
        return 0
    fi
    
    print_status "Running local $stage hooks..."
    local hook_index=1
    local hook_total=${#hooks[@]}
    for hook in "${hooks[@]}"; do
        print_status "Executing local $stage hook $hook_index/$hook_total..."
        if ! eval "$hook"; then
            print_error "Local $stage hook $hook_index failed"
            return 1
        fi
        hook_index=$((hook_index + 1))
    done
}

# Run local post-ready hooks (has CODESPACE_NAME and REPO_NAME available)
run_local_post_ready_hooks() {
    local codespace="$1"
    local repo_name="$2"
    local -a hooks
    get_hooks "local_post_ready" hooks
    
    if [ ${#hooks[@]} -eq 0 ]; then
        return 0
    fi
    
    print_status "Running local post-ready hooks..."
    # Export for subshells
    export CODESPACE_NAME="$codespace"
    export REPO_NAME="$repo_name"
    
    local hook_index=1
    local hook_total=${#hooks[@]}
    for hook in "${hooks[@]}"; do
        print_status "Executing local post-ready hook $hook_index/$hook_total..."
        if ! eval "$hook"; then
            print_error "Local post-ready hook $hook_index failed"
            return 1
        fi
        hook_index=$((hook_index + 1))
    done
}

# Build environment export string for remote commands
_build_remote_env_string() {
    local env_string=""
    local -a env_vars secret_vars
    get_remote_env_vars env_vars
    get_remote_secret_vars secret_vars
    
    # Add regular environment variables
    for var in "${env_vars[@]}"; do
        if _is_valid_env_var_name "$var"; then
            if [ -n "${!var+x}" ]; then
                env_string+="export ${var}=$(printf %q "${!var}"); "
            fi
        else
            print_warning "Skipping invalid environment variable name: $var"
        fi
    done
    
    # Add secret variables (prompt if not set in non-immediate mode)
    for var in "${secret_vars[@]}"; do
        if ! _is_valid_env_var_name "$var"; then
            print_warning "Skipping invalid secret variable name: $var"
            continue
        fi
        if [ -z "${!var+x}" ]; then
            if [ "$IMMEDIATE_MODE" = false ]; then
                print_status "Secret variable $var is not set. Please provide a value:"
                local secret_value
                secret_value=$(mise x ubi:charmbracelet/gum -- gum input --password --prompt "$var: ") || continue
                env_string+="export ${var}=$(printf %q "$secret_value"); "
                continue
            else
                print_warning "Secret variable $var is not set (skipping in immediate mode)"
                continue
            fi
        fi
        env_string+="export ${var}=$(printf %q "${!var}"); "
    done
    
    echo "$env_string"
}

_is_valid_env_var_name() {
    local name="$1"
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

# Run remote hooks (executed inside the codespace via SSH)
run_remote_hooks() {
    local stage="$1"
    local codespace="$2"
    local repo_name="$3"
    local -a hooks
    get_hooks "$stage" hooks
    
    if [ ${#hooks[@]} -eq 0 ]; then
        return 0
    fi
    
    print_status "Running remote $stage hooks..."
    local env_string
    env_string=$(_build_remote_env_string)
    
    local hook_index=1
    local hook_total=${#hooks[@]}
    for hook in "${hooks[@]}"; do
        print_status "Executing remote $stage hook $hook_index/$hook_total..."
        if ! _run_remote_repo_command "$codespace" "$repo_name" "$env_string" "$hook" >/dev/null 2>&1; then
            print_error "Remote $stage hook $hook_index failed"
            return 1
        fi
        hook_index=$((hook_index + 1))
    done
}

_run_remote_command() {
    local codespace="$1"
    local command="$2"
    gh cs ssh -c "$codespace" -- bash -l -c "$command"
}

_run_remote_command_quiet() {
    local codespace="$1"
    local command="$2"
    gh cs ssh -c "$codespace" -- bash -l -c "$command" >/dev/null 2>&1
}

_run_remote_repo_command() {
    local codespace="$1"
    local repo_name="$2"
    local env_string="$3"
    local command="$4"
    local full_cmd="${env_string}cd /workspaces/$repo_name && $command"
    printf '%s' "$full_cmd" | gh cs ssh -c "$codespace" -- bash -l -s
}

_ensure_remote_mise() {
    local codespace="$1"

    if _run_remote_command_quiet "$codespace" "command -v mise"; then
        return 0
    fi

    if ! _run_remote_command_quiet "$codespace" "command -v curl"; then
        print_error "curl is required to install mise in the codespace"
        return 1
    fi

    if ! _run_remote_command_quiet "$codespace" "curl -fsSL https://mise.run -o /tmp/mise-install.sh"; then
        print_error "Failed to download mise installer"
        return 1
    fi

    if ! _run_remote_command_quiet "$codespace" "bash /tmp/mise-install.sh"; then
        print_error "Failed to install mise in the codespace"
        return 1
    fi

    if ! _run_remote_command_quiet "$codespace" "[ -x \"\$HOME/.local/bin/mise\" ]"; then
        print_error "mise installation did not provide \$HOME/.local/bin/mise"
        return 1
    fi

    return 0
}

_ensure_remote_gh() {
    local codespace="$1"
    local gh_path_cmd="export PATH=\"\$HOME/.local/share/mise/shims:\$HOME/.local/bin:\$PATH\"; command -v gh"

    if _run_remote_command_quiet "$codespace" "$gh_path_cmd"; then
        return 0
    fi

    print_status "gh not found in codespace. Installing with mise..."

    if ! _ensure_remote_mise "$codespace"; then
        return 1
    fi

    if ! _run_remote_command_quiet "$codespace" "export PATH=\"\$HOME/.local/share/mise/shims:\$HOME/.local/bin:\$PATH\"; mise use -g ubi:cli/cli"; then
        print_error "Failed to install gh via mise"
        return 1
    fi

    if ! _run_remote_command_quiet "$codespace" "$gh_path_cmd"; then
        print_error "gh installation did not succeed"
        return 1
    fi

    print_status "gh installed in codespace."
}

# =============================================================================
# Signal Handling & Help
# =============================================================================

# Signal handler for clean exit on CTRL-C (SIGINT) and SIGTERM
cleanup_on_exit() {
    echo ""
    echo "Interrupted. Exiting..."
    exit 130
}

# Trap SIGINT (CTRL-C) and SIGTERM
trap cleanup_on_exit SIGINT SIGTERM
trap '_cleanup_codespace_if_needed "$CODESPACE_NAME" "$?"' EXIT

# Function to show help/usage information (defined early so it can be called before dependency checks)
show_help() {
    cat << EOF
Usage: ./create-codespace-and-checkout.sh [options]
       ./create-codespace-and-checkout.sh -c <codespace-name> [options]  # Setup existing

Create a GitHub Codespace and optionally checkout a git branch, or run setup on existing codespace.

Options:
  -b <branch>                  Branch name to checkout (optional, if not provided uses default branch)
  -c <codespace-name>          Target existing codespace (skip creation, run setup only)
  -R <repo>                    Repository (default: github/github, env: REPO)
  -m <machine-type>            Codespace machine type (default: xLargePremiumLinux, env: CODESPACE_SIZE; ignored with -c)
  -d <display-name>            Display name for the codespace (48 characters or less, env: CODESPACE_DISPLAY_NAME; ignored with -c)
  --devcontainer-path <path>   Path to devcontainer (default: .devcontainer/devcontainer.json, env: DEVCONTAINER_PATH; ignored with -c)
  --default-permissions        Use default permissions without authorization prompt
  --skip-hooks                 Skip hook execution only
  --test-e2e                    Run end-to-end test (create, configure, delete)
  -x, --immediate              Skip interactive prompts for unspecified options (use defaults)

Notes:
  Using -c skips interactive prompts and uses the existing codespace repository.
  If gh is missing inside the codespace, the script attempts to install it using mise.
  --test-e2e forces immediate mode and auto-deletes the codespace when finished.
  -h, --help                   Show this help message and exit

Configuration:
  Config file: \${XDG_CONFIG_HOME:-~/.config}/create-codespace-and-checkout/config.sh
  
  Hooks (arrays of commands to run at each stage):
    CONFIG_DEFAULT_LOCAL_PRE_HOOKS            Run locally before codespace creation
    CONFIG_DEFAULT_LOCAL_POST_READY_HOOKS     Run locally after codespace ready (has \$CODESPACE_NAME)
    CONFIG_DEFAULT_REMOTE_PRE_CHECKOUT_HOOKS  Run remotely before branch checkout
    CONFIG_DEFAULT_REMOTE_POST_CHECKOUT_HOOKS Run remotely after branch checkout
    CONFIG_DEFAULT_REMOTE_POST_CONFIG_HOOKS   Run remotely after config complete
  
  Skip built-in operations:
    CONFIG_SKIP_GIT_CREDENTIAL_SETUP=true     Skip 'gh auth setup-git' in codespace
    CONFIG_SKIP_GIT_FETCH=true                Skip 'git fetch origin' in codespace
  
  Environment injection for remote hooks:
    CONFIG_DEFAULT_REMOTE_ENV_VARS           Regular environment variables
    CONFIG_DEFAULT_REMOTE_SECRET_VARS        Secret variables (prompted if not set)
  
  Per-repo overrides via config_apply_repo_overrides() function with repo_matches() (defaults and repo arrays are merged; repo values appended).

Environment Variables:
  REPO                         Override default repository
  CODESPACE_SIZE              Override default machine type
  CODESPACE_DISPLAY_NAME      Override display name for codespace
  DEVCONTAINER_PATH           Override default devcontainer path
  READY_MAX_ATTEMPTS          Max attempts for readiness check (default: 30)
  READY_SLEEP_SECONDS         Sleep between readiness checks (default: 10)
  CONFIG_MAX_ATTEMPTS         Max attempts for config check (default: 60)
  CONFIG_SLEEP_SECONDS        Sleep between config checks (default: 10)
  GUM_LOG_*                   Customize log formatting (see gum log documentation)

Examples:
  ./create-codespace-and-checkout.sh -b my-branch
  ./create-codespace-and-checkout.sh -R myorg/myrepo -m large -b my-branch
  ./create-codespace-and-checkout.sh -d "my-feature-work" -b my-branch
  ./create-codespace-and-checkout.sh -x -b my-branch  # Skip interactive prompts
  ./create-codespace-and-checkout.sh  # Interactive mode, branch optional
  ./create-codespace-and-checkout.sh -c my-existing-codespace -b feature  # Setup existing
  ./create-codespace-and-checkout.sh -c my-codespace --skip-hooks  # Setup without hooks
  ./create-codespace-and-checkout.sh --test-e2e -R github/ekroon -m standardLinux32gb -b test-branch
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

# Generic retry function for waiting on conditions
# Usage: retry_until <max_attempts> <sleep_seconds> <description> <command>
retry_until() {
    local max_attempts=$1
    local sleep_seconds=$2
    local description=$3
    shift 3
    local command=("$@")
    
    local attempt=1
    local output
    while [ $attempt -le "$max_attempts" ]; do
        print_status "$description (attempt $attempt/$max_attempts)..."
        
        if output=$("${command[@]}" 2>&1); then
            return 0
        else
            # Log the failure reason for debugging (omit for sensitive operations)
            if [ -n "$output" ]; then
                print_warning "  └─ $output"
            fi
        fi
        
        if [ $attempt -eq "$max_attempts" ]; then
            return 1
        fi
        
        sleep "$sleep_seconds"
        attempt=$((attempt + 1))
    done
}

# =============================================================================
# Initialization
# =============================================================================

# Load configuration file (before parsing args so config provides defaults)
load_config

REPO_ENV_VALUE=${REPO-}
CODESPACE_SIZE_ENV_VALUE=${CODESPACE_SIZE-}
DEVCONTAINER_PATH_ENV_VALUE=${DEVCONTAINER_PATH-}
DISPLAY_NAME_ENV_VALUE=${CODESPACE_DISPLAY_NAME-}

# Set defaults from environment variables, config, or use built-in defaults
REPO=${REPO:-""}  # Will be set after config is applied
CODESPACE_SIZE=${CODESPACE_SIZE:-""}  # Will be set after config is applied
DEVCONTAINER_PATH=${DEVCONTAINER_PATH:-""}  # Will be set after config is applied
DISPLAY_NAME=${CODESPACE_DISPLAY_NAME:-""}
DEFAULT_PERMISSIONS=""
BRANCH_NAME=""
CODESPACE_NAME=""  # For existing codespace mode (-c flag)
IMMEDIATE_MODE=false
SKIP_HOOKS=false
TEST_E2E_MODE=false
CREATED_CODESPACE=false
CODESPACE_INFO=""
CODESPACE_REPO=""
CODESPACE_STATE=""
REPO_CLI=false
CODESPACE_SIZE_CLI=false
DEVCONTAINER_PATH_CLI=false
DISPLAY_NAME_CLI=false
REMOTE_GH_READY=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -b)
            _validate_required_arg "-b" "$2"
            BRANCH_NAME="$2"
            shift 2
            ;;
        -c)
            _validate_required_arg "-c" "$2"
            CODESPACE_NAME="$2"
            shift 2
            ;;
        -R)
            _validate_required_arg "-R" "$2"
            REPO="$2"
            REPO_CLI=true
            shift 2
            ;;
        -m)
            _validate_required_arg "-m" "$2"
            CODESPACE_SIZE="$2"
            CODESPACE_SIZE_CLI=true
            shift 2
            ;;
        -d)
            _validate_required_arg "-d" "$2"
            DISPLAY_NAME="$2"
            DISPLAY_NAME_CLI=true
            shift 2
            ;;
        --devcontainer-path)
            _validate_required_arg "--devcontainer-path" "$2"
            DEVCONTAINER_PATH="$2"
            DEVCONTAINER_PATH_CLI=true
            shift 2
            ;;
        --default-permissions)
            DEFAULT_PERMISSIONS="--default-permissions"
            shift
            ;;
        --skip-hooks)
            SKIP_HOOKS=true
            shift
            ;;
        --test-e2e)
            TEST_E2E_MODE=true
            IMMEDIATE_MODE=true
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

if [ "$TEST_E2E_MODE" = true ] && [ -n "$CODESPACE_NAME" ]; then
    print_error "--test-e2e cannot be used with -c"
    exit 1
fi

REPO_ENV_SET=false
if [ -n "$REPO_ENV_VALUE" ]; then
    REPO_ENV_SET=true
fi

CODESPACE_SIZE_ENV_SET=false
if [ -n "$CODESPACE_SIZE_ENV_VALUE" ]; then
    CODESPACE_SIZE_ENV_SET=true
fi

DEVCONTAINER_PATH_ENV_SET=false
if [ -n "$DEVCONTAINER_PATH_ENV_VALUE" ]; then
    DEVCONTAINER_PATH_ENV_SET=true
fi

DISPLAY_NAME_ENV_SET=false
if [ -n "$DISPLAY_NAME_ENV_VALUE" ]; then
    DISPLAY_NAME_ENV_SET=true
fi

# Apply configuration (sets defaults from config file with repo-specific overrides)
# First set REPO default if not specified
REPO=${REPO:-${CONFIG_DEFAULT_REPO:-"github/github"}}
apply_config "$REPO"

_validate_repo_format "$REPO"

# Extract repository name from REPO (e.g., "github/github" -> "github")
REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)

# Interactive mode: prompt for unspecified options unless immediate mode is enabled
# Skip prompts if targeting an existing codespace (already know the codespace)
if [ "$IMMEDIATE_MODE" = false ] && [ -z "$CODESPACE_NAME" ]; then
    # Prompt for repository if using default
    default_repo="${CONFIG_DEFAULT_REPO:-github/github}"
    if [ "$REPO" = "$default_repo" ]; then
        REPO_INPUT=$(mise x ubi:charmbracelet/gum -- gum input --prompt "Repository: " --placeholder "$default_repo") || exit 130
        if [ -n "$REPO_INPUT" ]; then
            REPO="$REPO_INPUT"
            _validate_repo_format "$REPO"
            REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
            # Re-apply config for new repo
            apply_config "$REPO"
        fi
    fi
    
    # Prompt for machine type if using default
    default_size="${CONFIG_DEFAULT_CODESPACE_SIZE:-xLargePremiumLinux}"
    if [ "$CODESPACE_SIZE" = "$default_size" ]; then
        CODESPACE_SIZE_INPUT=$(mise x ubi:charmbracelet/gum -- gum input --prompt "Machine type: " --placeholder "$default_size") || exit 130
        if [ -n "$CODESPACE_SIZE_INPUT" ]; then
            CODESPACE_SIZE="$CODESPACE_SIZE_INPUT"
        fi
    fi
    
    # Prompt for devcontainer path if using default
    default_devcontainer="${CONFIG_DEFAULT_DEVCONTAINER_PATH:-.devcontainer/devcontainer.json}"
    if [ "$DEVCONTAINER_PATH" = "$default_devcontainer" ]; then
        DEVCONTAINER_PATH_INPUT=$(mise x ubi:charmbracelet/gum -- gum input --prompt "Devcontainer path: " --placeholder "$default_devcontainer") || exit 130
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

_validate_branch_name "$BRANCH_NAME"

# Auto-set display name from branch name when not specified
# This applies to both immediate mode and when branch was provided via -b flag
if [ -z "$DISPLAY_NAME" ] && [ -n "$BRANCH_NAME" ]; then
    DISPLAY_NAME="${BRANCH_NAME:0:48}"
fi

# =============================================================================
# Main Execution
# =============================================================================

# Run local pre-setup hooks (unless skipped)
if [ "$SKIP_HOOKS" = false ]; then
    run_local_hooks "local_pre" || exit 1
fi

# Determine if we're creating a new codespace or using an existing one
if [ -n "$CODESPACE_NAME" ]; then
    # Existing codespace mode: validate the codespace exists
    print_status "Using existing codespace: $CODESPACE_NAME"
    
    # Verify the codespace exists and get its repo info
    CODESPACE_INFO=$(gh cs list --json name,repository,state -q ".[] | select(.name==\"$CODESPACE_NAME\") | [.repository, .state] | @tsv")
    if [ -z "$CODESPACE_INFO" ]; then
        print_error "Codespace '$CODESPACE_NAME' not found"
        print_status "Available codespaces:"
        gh cs list
        exit 1
    fi
    
    IFS=$'\t' read -r CODESPACE_REPO CODESPACE_STATE <<< "$CODESPACE_INFO"
    if [ -z "$CODESPACE_REPO" ] || [ "$CODESPACE_REPO" = "null" ]; then
        print_error "Unable to resolve repository for codespace '$CODESPACE_NAME'"
        exit 1
    fi
    
    if [ "$REPO_CLI" = true ] || [ "$REPO_ENV_SET" = true ]; then
        if [ "$REPO" != "$CODESPACE_REPO" ]; then
            print_error "Codespace repo mismatch: expected $REPO, found $CODESPACE_REPO"
            exit 1
        fi
    fi
    
    REPO="$CODESPACE_REPO"
    apply_config "$REPO"
    _validate_repo_format "$REPO"
    REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
    print_status "Resolved codespace repo: $REPO"
    
    if [ "$CODESPACE_STATE" = "Stopped" ] || [ "$CODESPACE_STATE" = "Shutdown" ]; then
        print_status "Starting codespace '$CODESPACE_NAME'..."
        if ! gh cs start -c "$CODESPACE_NAME" >/dev/null 2>&1; then
            print_error "Failed to start codespace '$CODESPACE_NAME'"
            exit 1
        fi
        if ! retry_until "$READY_MAX_ATTEMPTS" "$READY_SLEEP_SECONDS" "Waiting for codespace start" \
            _run_remote_command "$CODESPACE_NAME" "true"; then
            print_error "Codespace did not become reachable after starting"
            exit 1
        fi
    fi
    
    if [ "$CODESPACE_STATE" != "Available" ] && [ "$CODESPACE_STATE" != "Running" ]; then
        print_warning "Codespace '$CODESPACE_NAME' is in state '$CODESPACE_STATE'"
    fi
    
    if [ "$DISPLAY_NAME_CLI" = true ] || [ "$CODESPACE_SIZE_CLI" = true ] || [ "$DEVCONTAINER_PATH_CLI" = true ] || [ "$DISPLAY_NAME_ENV_SET" = true ] || [ "$CODESPACE_SIZE_ENV_SET" = true ] || [ "$DEVCONTAINER_PATH_ENV_SET" = true ]; then
        print_warning "Options -d, -m, and --devcontainer-path are ignored when using -c"
    fi
    
    print_status "Running setup on existing codespace..."
else
    # Create mode: create a new codespace
    print_status "Starting codespace creation process..."

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
    CREATED_CODESPACE=true
fi

# Wait for the codespace to be fully ready
print_status "Waiting for codespace to be fully ready..."

if ! retry_until "$READY_MAX_ATTEMPTS" "$READY_SLEEP_SECONDS" "Checking codespace readiness" \
    _run_remote_repo_command "$CODESPACE_NAME" "$REPO_NAME" "" "pwd"; then
    print_error "Codespace failed to become ready after $READY_MAX_ATTEMPTS attempts"
    exit 1
fi

print_status "Codespace is ready!"

# Run local post-ready hooks (unless skipped)
if [ "$SKIP_HOOKS" = false ]; then
    run_local_post_ready_hooks "$CODESPACE_NAME" "$REPO_NAME" || exit 1
fi

REMOTE_GH_READY=true
if ! _ensure_remote_gh "$CODESPACE_NAME"; then
    print_warning "Skipping git credential setup and remote hooks because gh is unavailable"
    REMOTE_GH_READY=false
fi

# Setup git credential helper to use gh (if gh is available in the codespace)
if [ "$CONFIG_SKIP_GIT_CREDENTIAL_SETUP" != true ]; then
    if [ "$REMOTE_GH_READY" = true ]; then
        mise x ubi:charmbracelet/gum -- gum spin --spinner dot --title "Setting up git credentials..." -- gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'export PATH=\"\$HOME/.local/share/mise/shims:\$HOME/.local/bin:\$PATH\"; gh auth setup-git'" >/dev/null 2>&1
    else
        print_warning "gh not available in codespace; skipping gh auth setup-git"
    fi
fi

# Fetch latest remote information (silently with progress indicator)
if [ "$CONFIG_SKIP_GIT_FETCH" != true ]; then
    mise x ubi:charmbracelet/gum -- gum spin --spinner dot --title "Fetching latest remote information..." -- _run_remote_repo_command "$CODESPACE_NAME" "$REPO_NAME" "" "git fetch origin"
    FETCH_EXIT_CODE=$?

    if [ $FETCH_EXIT_CODE -ne 0 ]; then
        print_warning "Failed to fetch from remote. Git authentication may not be ready yet."
        print_warning "You may need to run 'git fetch origin' manually after connecting."
    fi
fi

# Run remote pre-checkout hooks (unless skipped)
if [ "$SKIP_HOOKS" = false ]; then
    if [ "$REMOTE_GH_READY" = true ]; then
        run_remote_hooks "remote_pre_checkout" "$CODESPACE_NAME" "$REPO_NAME" || exit 1
    else
        print_warning "Skipping remote pre-checkout hooks because gh is unavailable"
    fi
fi

# Checkout the branch (optional - skip if no branch name provided)
if [ -n "$BRANCH_NAME" ]; then
    print_status "Checking if branch '$BRANCH_NAME' exists remotely..."
    REMOTE_CHECK=$(_run_remote_repo_command "$CODESPACE_NAME" "$REPO_NAME" "" "git ls-remote --heads origin $(printf %q "$BRANCH_NAME")" 2>/dev/null || echo "")
    
    if [ -n "$REMOTE_CHECK" ]; then
        print_status "Branch '$BRANCH_NAME' exists remotely, checking out..."
        if _run_remote_repo_command "$CODESPACE_NAME" "$REPO_NAME" "" "git checkout $(printf %q "$BRANCH_NAME")" >/dev/null 2>&1; then
            print_status "Successfully checked out branch '$BRANCH_NAME' in codespace '$CODESPACE_NAME'"
        else
            print_error "Failed to checkout branch '$BRANCH_NAME'"
            print_warning "Codespace '$CODESPACE_NAME' was created but branch checkout failed"
            exit 1
        fi
    else
        print_warning "Branch '$BRANCH_NAME' doesn't exist remotely. Creating new branch..."
        if _run_remote_repo_command "$CODESPACE_NAME" "$REPO_NAME" "" "git checkout -b $(printf %q "$BRANCH_NAME")" >/dev/null 2>&1; then
            print_status "Successfully created and checked out branch '$BRANCH_NAME' in codespace '$CODESPACE_NAME'"
        else
            print_error "Failed to create branch '$BRANCH_NAME'"
            print_warning "Codespace '$CODESPACE_NAME' was created but branch creation failed"
            exit 1
        fi
    fi
    
    # Run remote post-checkout hooks (unless skipped)
    if [ "$SKIP_HOOKS" = false ]; then
        if [ "$REMOTE_GH_READY" = true ]; then
            run_remote_hooks "remote_post_checkout" "$CODESPACE_NAME" "$REPO_NAME" || exit 1
        else
            print_warning "Skipping remote post-checkout hooks because gh is unavailable"
        fi
    fi
else
    print_status "No branch name provided, skipping checkout step"
    print_status "Codespace will use the default branch"
fi

# Wait for codespace configuration to complete
print_status "Waiting for codespace configuration to complete..."

# Helper function to check if configuration is complete
_check_config_complete() {
    local last_log
    last_log=$(gh cs logs --codespace "$CODESPACE_NAME" 2>/dev/null | tail -n 1 || echo "")
    [[ "$last_log" == *"Finished configuring codespace."* ]]
}

if retry_until "$CONFIG_MAX_ATTEMPTS" "$CONFIG_SLEEP_SECONDS" "Checking configuration status" _check_config_complete; then
    print_status "Codespace configuration complete! ✓"
else
    print_warning "Codespace configuration did not complete after $CONFIG_MAX_ATTEMPTS attempts"
    print_warning "The codespace may still be configuring in the background"
fi

# Run remote post-config hooks (unless skipped)
if [ "$SKIP_HOOKS" = false ]; then
    if [ "$REMOTE_GH_READY" = true ]; then
        run_remote_hooks "remote_post_config" "$CODESPACE_NAME" "$REPO_NAME" || exit 1
    else
        print_warning "Skipping remote post-config hooks because gh is unavailable"
    fi
fi

if [ -n "$BRANCH_NAME" ]; then
    print_status "Setup complete! Your codespace is ready with branch '$BRANCH_NAME' checked out."
else
    print_status "Setup complete! Your codespace is ready."
fi

print_status "Connect with: gh cs ssh -c $CODESPACE_NAME"
