# create-codespace-and-checkout

A tool to quickly create a GitHub Codespace and check out a branch for instant development.

## Installation

Install globally using [mise](https://mise.jdx.dev):

```sh
mise use -g ubi:ekroon/create-codespace-and-checkout
```

## Usage

```sh
./create-codespace-and-checkout.sh [options]
```

The script runs in interactive mode by default, prompting for unspecified options. Use `-x` for non-interactive mode with defaults.

### Options

| Option | Environment Variable | Default | Description |
|--------|---------------------|---------|-------------|
| `-b <branch>` | - | - | Branch name to checkout (optional) |
| `-R <repo>` | `REPO` | `github/github` | Repository to create codespace for |
| `-m <machine-type>` | `CODESPACE_SIZE` | `xLargePremiumLinux` | Codespace machine type |
| `--devcontainer-path <path>` | `DEVCONTAINER_PATH` | `.devcontainer/devcontainer.json` | Path to devcontainer configuration |
| `--default-permissions` | - | - | Use default permissions without authorization prompt |
| `-x, --immediate` | - | - | Skip interactive prompts, use defaults |
| `-h, --help` | - | - | Show help message and exit |

Command-line options override environment variables when both are provided.

### Examples

#### Interactive mode (default)
```sh
./create-codespace-and-checkout.sh
```
The script will prompt for repository, machine type, devcontainer path, and branch name.

#### Basic usage with branch
```sh
./create-codespace-and-checkout.sh -b my-branch
```

#### Non-interactive mode with branch
```sh
./create-codespace-and-checkout.sh -x -b my-branch
```

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

### Available Machine Types

Common machine types include:
- `basicLinux` (2 cores, 8 GB RAM, 32 GB storage)
- `standardLinux` (4 cores, 16 GB RAM, 32 GB storage)
- `largeLinux` (8 cores, 32 GB RAM, 64 GB storage)
- `xLargeLinux` (16 cores, 64 GB RAM, 128 GB storage)
- `xLargePremiumLinux` (16 cores, 64 GB RAM, 128 GB storage, premium hardware)

For the most up-to-date list, check the [GitHub Codespaces documentation](https://docs.github.com/en/codespaces/setting-up-your-project-for-codespaces/setting-a-minimum-specification-for-codespace-machines).

## Development

### Project Structure

The script has been modularized into separate components:
- `create-codespace-and-checkout.sh` - Main script with argument parsing and orchestration
- `lib.sh` - Common library functions (logging, retry logic)
- `create-codespace.sh` - Codespace creation module
- `codespace-commands.sh` - Module for running commands in codespaces with retry logic
- `tests/` - Test suite for all modules

This modular structure makes the code easier to maintain, test, and extend.

### Testing

The project includes a comprehensive test suite. To run the tests:

```bash
./tests/run_tests.sh
```

See [tests/README.md](tests/README.md) for more details about the test suite.


