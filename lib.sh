#!/bin/bash

# Common library functions for codespace management

# Helper function to set gum log style defaults
_gum_set_default() {
    # $1 = var name, $2 = default value
    if [ -z "${!1+x}" ]; then
        export "$1=$2"
    fi
}

# Initialize gum log styling (can be overridden via environment)
init_gum_logging() {
    _gum_set_default GUM_LOG_LEVEL_FOREGROUND 212
    _gum_set_default GUM_LOG_LEVEL_BOLD true
    _gum_set_default GUM_LOG_TIME_FOREGROUND 244
    _gum_set_default GUM_LOG_MESSAGE_FOREGROUND 254
    _gum_set_default GUM_LOG_KEY_FOREGROUND 240
    _gum_set_default GUM_LOG_VALUE_FOREGROUND 118
    _gum_set_default GUM_LOG_SEPARATOR_FOREGROUND 240
}

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
# Usage: retry_until <max_attempts> <sleep_seconds> <description> <command...>
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
