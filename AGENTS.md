# AGENTS.md

This file provides guidance for AI coding agents working in this repository.

## Project Overview

A single Bash script (`create-codespace-and-checkout.sh`) that automates GitHub Codespace creation and branch checkout with an interactive CLI using [gum](https://github.com/charmbracelet/gum).

### Key Dependencies

- `gh` - GitHub CLI for codespace operations
- `mise` - Tool version manager (used to run gum)
- `infocmp` - Terminal info compiler (for terminfo upload)
- `gum` - Charm CLI tool for styled output (installed via mise)

## Commands

### Running the Script

```bash
./create-codespace-and-checkout.sh                    # Interactive mode
./create-codespace-and-checkout.sh -b my-branch       # With branch name
./create-codespace-and-checkout.sh -x -b my-branch    # Skip prompts (use defaults)
./create-codespace-and-checkout.sh -R owner/repo -m machineType -b branch-name
```

### Linting

```bash
shellcheck create-codespace-and-checkout.sh
shellcheck -s bash create-codespace-and-checkout.sh   # Explicit dialect
```

### Testing

**IMPORTANT**: Use small codespace to minimize resource usage:

```bash
# Test with ekroon repository and small machine type
./create-codespace-and-checkout.sh -R github/ekroon -m standardLinux32gb -b test-branch
./create-codespace-and-checkout.sh -x -R github/ekroon -m standardLinux32gb -b test-branch
./create-codespace-and-checkout.sh -x -R github/ekroon -m standardLinux32gb
./create-codespace-and-checkout.sh -x -R github/ekroon -m standardLinux32gb -d "test-display-name"
```

After testing, clean up:

```bash
gh cs list                           # List codespaces
gh cs delete -c <codespace-name>     # Delete test codespace
```

**Do NOT test with large machine types** - use `standardLinux32gb` (4 cores, 16 GB RAM).

## Code Style Guidelines

### Shell Dialect

- Use Bash (`#!/bin/bash` shebang)
- Target Bash 4.0+ features when needed
- Avoid bashisms that don't work in older Bash versions without good reason

### Variable Naming

```bash
# Global/environment variables: UPPER_SNAKE_CASE
REPO="github/github"
CODESPACE_SIZE="xLargePremiumLinux"

# Local variables in functions: lower_snake_case
local max_attempts=$1
local sleep_seconds=$2
```

### Function Naming

- Public functions: `snake_case` (e.g., `print_status`, `retry_until`)
- Internal/helper functions: prefix with underscore (e.g., `_gum_set_default`, `_check_config_complete`)

### Function Structure

Document function purpose and usage in comments above the function. Use `local` for all function-scoped variables.

### Error Handling

Use the structured logging functions for all user-facing output:

```bash
print_status "Starting codespace creation process..."   # info level
print_warning "Branch doesn't exist remotely..."        # warn level
print_error "Failed to create codespace"                # error level
```

Exit codes:
- `0` - Success
- `1` - General error
- `130` - Interrupted (SIGINT/Ctrl+C)

### Command Output Handling

```bash
# Capture output and check exit code
if ! OUTPUT=$(some_command 2>&1); then
    print_error "Command failed"
    print_error "$OUTPUT"
    exit 1
fi
```

Use `gum spin` for silent commands with progress indicator.

### Argument Parsing

Use a `while` loop with `case` statement for `-h|--help`, `-b`, `-*` (unknown), and `*` (unexpected) cases. Use `shift 2` for options with arguments.

### Quoting

Always quote variables to prevent word splitting and glob expansion:

```bash
# Good
gh cs ssh -c "$CODESPACE_NAME" -- "bash -l -c 'cd /workspaces/$REPO_NAME'"

# Bad - unquoted variables
gh cs ssh -c $CODESPACE_NAME -- bash -l -c cd /workspaces/$REPO_NAME
```

### Signal Handling

Trap SIGINT and SIGTERM for clean exit with code 130.

### Dependency Checks

Check for required commands at script start using `command -v`. Collect missing deps in an array and report all at once before exiting.

## File Structure

```
.
├── create-codespace-and-checkout.sh  # Main script
├── README.md                          # User documentation
├── AGENTS.md                          # This file (agent guidance)
└── .github/
    └── workflows/
        └── release.yml                # GitHub Actions release workflow
```

## Release Process

Releases are automated via GitHub Actions when a tag matching `v*` is pushed:

```bash
git tag v1.4.0
git push origin v1.4.0
```

The workflow creates a GitHub Release with the script as a downloadable asset.
