#!/bin/bash

# Test helpers for mocking commands

# Mock the gh command
gh() {
    if [ -n "$GH_MOCK_OUTPUT" ]; then
        echo "$GH_MOCK_OUTPUT"
        return ${GH_MOCK_EXIT_CODE:-0}
    fi
    
    # Default mock behavior
    case "$1" in
        cs)
            case "$2" in
                create)
                    echo "test-codespace-123"
                    return 0
                    ;;
                ssh)
                    return 0
                    ;;
                logs)
                    if [ -n "$GH_MOCK_LOGS" ]; then
                        echo "$GH_MOCK_LOGS"
                    else
                        echo "Finished configuring codespace."
                    fi
                    return 0
                    ;;
            esac
            ;;
    esac
    return 0
}

# Mock the mise command
mise() {
    # Skip actual mise execution in tests
    shift 3  # Skip "x ubi:charmbracelet/gum --"
    # Just echo the message for print_status, print_warning, print_error
    if [ "$1" = "gum" ] && [ "$2" = "log" ]; then
        shift 5  # Skip "gum log --structured --level X --time rfc822"
        echo "$@"
    elif [ "$1" = "gum" ] && [ "$2" = "spin" ]; then
        # For gum spin, just run the command
        shift
        while [ "$1" != "--" ] && [ $# -gt 0 ]; do
            shift
        done
        shift  # Skip the --
        "$@"
    fi
    return 0
}

# Mock the infocmp command
infocmp() {
    echo "xterm-ghostty terminfo data"
    return 0
}

# Export mocked functions so they're available to sourced scripts
export -f gh
export -f mise
export -f infocmp
