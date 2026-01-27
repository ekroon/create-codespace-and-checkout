# create-codespace-and-checkout

A tool to quickly create a GitHub Codespace and check out a branch for instant development, or run setup on an existing codespace.

## Installation

Install globally using [mise](https://mise.jdx.dev):

```sh
mise use -g ubi:ekroon/create-codespace-and-checkout
```

## Usage

```sh
./create-codespace-and-checkout.sh [options]
./create-codespace-and-checkout.sh -c <codespace-name> [options]  # Setup existing
```

The script runs in interactive mode by default, prompting for unspecified options. Use `-x` for non-interactive mode with defaults. When using `-c`, interactive prompts are skipped.

### Options

| Option | Environment Variable | Default | Description |
|--------|---------------------|---------|-------------|
| `-b <branch>` | - | - | Branch name to checkout (optional) |
| `-c <codespace-name>` | - | - | Target existing codespace (skip creation) |
| `-R <repo>` | `REPO` | `github/github` | Repository to create codespace for |
| `-m <machine-type>` | `CODESPACE_SIZE` | `xLargePremiumLinux` | Codespace machine type (ignored with `-c`) |
| `-d <display-name>` | `CODESPACE_DISPLAY_NAME` | - | Display name for codespace (48 chars max, ignored with `-c`) |
| `--devcontainer-path <path>` | `DEVCONTAINER_PATH` | `.devcontainer/devcontainer.json` | Path to devcontainer configuration (ignored with `-c`) |
| `--default-permissions` | - | - | Use default permissions without authorization prompt |
| `--skip-hooks` | - | - | Skip hook execution (built-in git steps still run) |
| `--test-e2e` | - | - | Run end-to-end test (forces `-x`, deletes codespace) |
| `-x, --immediate` | - | - | Skip interactive prompts, use defaults |
| `-h, --help` | - | - | Show help message and exit |

Command-line options override environment variables when both are provided.

### Examples

#### Interactive mode (default)
```sh
./create-codespace-and-checkout.sh
```
The script will prompt for repository, machine type, devcontainer path, and branch name. The display name defaults to the branch name (truncated to 48 characters).

#### Basic usage with branch
```sh
./create-codespace-and-checkout.sh -b my-branch
```

#### Non-interactive mode with branch
```sh
./create-codespace-and-checkout.sh -x -b my-branch
```

#### Run setup on existing codespace
```sh
./create-codespace-and-checkout.sh -c my-existing-codespace -b feature-branch
```
This uses the repository already attached to the codespace. If `-R` is supplied (or `REPO` is set) and does not match, the script exits with an error.

#### End-to-end test with auto cleanup
```sh
./create-codespace-and-checkout.sh --test-e2e -R github/ekroon -m standardLinux32gb -b test-branch
```
This forces `-x` and deletes the codespace at the end of the run.

#### Custom repository and machine type
```sh
./create-codespace-and-checkout.sh -R myorg/myrepo -m large -b my-branch
```

#### Custom devcontainer path
```sh
./create-codespace-and-checkout.sh --devcontainer-path .devcontainer/custom.json -b my-branch
```

#### All options together
```sh
./create-codespace-and-checkout.sh -R myorg/myrepo -m xlarge --devcontainer-path .custom/dev.json -b feature-branch
```

#### Using environment variables
```sh
REPO=myorg/myrepo CODESPACE_SIZE=medium ./create-codespace-and-checkout.sh -b my-branch
```

#### Environment variables with command-line override
```sh
REPO=default/repo ./create-codespace-and-checkout.sh -R override/repo -b my-branch
```

#### Using default permissions (skip authorization prompt)
```sh
./create-codespace-and-checkout.sh --default-permissions -x -b my-branch
```

#### Create codespace without checking out a branch
```sh
./create-codespace-and-checkout.sh -x
```
This creates a codespace using the default branch without checking out a specific branch.

## Configuration

The script supports a configuration file for customizing defaults and adding hooks. Defaults and per-repo arrays are merged, with repo values appended after defaults.

### Config File Location

```
${XDG_CONFIG_HOME:-~/.config}/create-codespace-and-checkout/config.sh
```

### Configuration Options

```bash
# ~/.config/create-codespace-and-checkout/config.sh

# Default settings (applied to all repos)
CONFIG_DEFAULT_REPO="github/github"
CONFIG_DEFAULT_CODESPACE_SIZE="xLargePremiumLinux"
CONFIG_DEFAULT_DEVCONTAINER_PATH=".devcontainer/devcontainer.json"

# Retry/timeout configuration
READY_MAX_ATTEMPTS=30
READY_SLEEP_SECONDS=10
CONFIG_MAX_ATTEMPTS=60
CONFIG_SLEEP_SECONDS=10

# Skip built-in operations
CONFIG_SKIP_GIT_CREDENTIAL_SETUP=false  # Skip 'gh auth setup-git'
CONFIG_SKIP_GIT_FETCH=false             # Skip 'git fetch origin'

# Hook arrays (commands to run at each stage)
CONFIG_DEFAULT_LOCAL_PRE_HOOKS=()              # Run locally before codespace creation
CONFIG_DEFAULT_LOCAL_POST_READY_HOOKS=()       # Run locally after codespace ready (has $CODESPACE_NAME)
CONFIG_DEFAULT_REMOTE_PRE_CHECKOUT_HOOKS=()    # Run remotely before branch checkout
CONFIG_DEFAULT_REMOTE_POST_CHECKOUT_HOOKS=()   # Run remotely after branch checkout
CONFIG_DEFAULT_REMOTE_POST_CONFIG_HOOKS=()     # Run remotely after config complete

# Environment variables to inject into remote hooks
CONFIG_DEFAULT_REMOTE_ENV_VARS=()
CONFIG_DEFAULT_REMOTE_SECRET_VARS=()           # Prompted interactively if not set

# Per-repo overrides (merged with defaults; repo values appended)
CONFIG_REPO_CODESPACE_SIZE=""
CONFIG_REPO_DEVCONTAINER_PATH=""
CONFIG_REPO_LOCAL_PRE_HOOKS=()
CONFIG_REPO_LOCAL_POST_READY_HOOKS=()
CONFIG_REPO_REMOTE_PRE_CHECKOUT_HOOKS=()
CONFIG_REPO_REMOTE_POST_CHECKOUT_HOOKS=()
CONFIG_REPO_REMOTE_POST_CONFIG_HOOKS=()
CONFIG_REPO_REMOTE_ENV_VARS=()
CONFIG_REPO_REMOTE_SECRET_VARS=()

# Remote env/secret vars are de-duped with repo values preferred
```

### Per-Repository Overrides

Use glob patterns to apply different settings per repository. Defaults and repo arrays are merged, with repo hooks appended after defaults (duplicates preserved for hooks).

```bash
# In config.sh
config_apply_repo_overrides() {
  local repo=$1
  
  # Exact match
  if repo_matches "$repo" "github/github"; then
    CONFIG_REPO_REMOTE_POST_CHECKOUT_HOOKS=(
      "script/bootstrap"
    )
  fi
  
  # Glob pattern match
  if repo_matches "$repo" "myorg/*"; then
    CONFIG_REPO_CODESPACE_SIZE="standardLinux32gb"
    CONFIG_REPO_LOCAL_PRE_HOOKS=(
      "echo 'Setting up myorg repo...'"
    )
  fi
}
```

### Hook Stages

Hooks run in this order:

1. **LOCAL_PRE_HOOKS** - Run locally before codespace creation
2. **LOCAL_POST_READY_HOOKS** - Run locally after codespace is ready (has `$CODESPACE_NAME` and `$REPO_NAME` exported)
3. **REMOTE_PRE_CHECKOUT_HOOKS** - Run inside codespace before branch checkout
4. **REMOTE_POST_CHECKOUT_HOOKS** - Run inside codespace after branch checkout
5. **REMOTE_POST_CONFIG_HOOKS** - Run inside codespace after configuration completes

All remote hooks run in `/workspaces/<repo-name>` with injected environment variables.

### Example: Upload Terminal Info

Use `LOCAL_POST_READY_HOOKS` for local-to-remote operations like uploading terminfo:

```bash
CONFIG_DEFAULT_LOCAL_POST_READY_HOOKS=(
  'infocmp -x xterm-ghostty 2>/dev/null | gh cs ssh -c "$CODESPACE_NAME" -- tic -x - || true'
)
```

### Secret Variables

Secret variables (`CONFIG_DEFAULT_REMOTE_SECRET_VARS`) are handled securely:
- If set in environment, they are injected into remote hooks
- If not set and running interactively, you'll be prompted (with hidden input)
- If not set and running with `-x`, a warning is shown and the variable is skipped

`--skip-hooks` only skips hook execution. Built-in git steps (credential setup and fetch) are controlled separately by `CONFIG_SKIP_GIT_CREDENTIAL_SETUP` and `CONFIG_SKIP_GIT_FETCH`. If `gh` is missing inside the codespace, the script attempts to install it with `mise` and skips remote hooks if that fails.

`--test-e2e` forces immediate mode and deletes the codespace after the run completes.

### Available Machine Types

Common machine types include:
- `basicLinux` (2 cores, 8 GB RAM, 32 GB storage)
- `standardLinux` (4 cores, 16 GB RAM, 32 GB storage)
- `largeLinux` (8 cores, 32 GB RAM, 64 GB storage)
- `xLargeLinux` (16 cores, 64 GB RAM, 128 GB storage)
- `xLargePremiumLinux` (16 cores, 64 GB RAM, 128 GB storage, premium hardware)

For the most up-to-date list, check the [GitHub Codespaces documentation](https://docs.github.com/en/codespaces/setting-up-your-project-for-codespaces/setting-a-minimum-specification-for-codespace-machines).

