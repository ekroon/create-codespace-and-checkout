# create-codespace-and-checkout

A tool to quickly create a GitHub Codespace and check out a branch for instant development.

## Installation

Install globally using [mise](https://mise.jdx.dev):

```sh
mise use -g ubi:ekroon/create-codespace-and-checkout
```

## Usage

```sh
./create-codespace-and-checkout.sh [options] [branch-name]
```

### Options

| Option | Environment Variable | Default | Description |
|--------|---------------------|---------|-------------|
| `-R <repo>` | `REPO` | `github/github` | Repository to create codespace for |
| `-m <machine-type>` | `CODESPACE_SIZE` | `xLargePremiumLinux` | Codespace machine type |
| `--devcontainer-path <path>` | `DEVCONTAINER_PATH` | `.devcontainer/devcontainer.json` | Path to devcontainer configuration |

Command-line options override environment variables when both are provided.

### Examples

#### Basic usage
```sh
./create-codespace-and-checkout.sh my-branch
```

#### Custom repository and machine type
```sh
./create-codespace-and-checkout.sh -R myorg/myrepo -m large my-branch
```

#### Custom devcontainer path
```sh
./create-codespace-and-checkout.sh --devcontainer-path .devcontainer/custom.json my-branch
```

#### All options together
```sh
./create-codespace-and-checkout.sh -R myorg/myrepo -m xlarge --devcontainer-path .custom/dev.json feature-branch
```

#### Using environment variables
```sh
REPO=myorg/myrepo CODESPACE_SIZE=medium ./create-codespace-and-checkout.sh my-branch
```

#### Environment variables with command-line override
```sh
REPO=default/repo ./create-codespace-and-checkout.sh -R override/repo my-branch
```

### Available Machine Types

Common machine types include:
- `basicLinux` (2 cores, 8 GB RAM, 32 GB storage)
- `standardLinux` (4 cores, 16 GB RAM, 32 GB storage)
- `largeLinux` (8 cores, 32 GB RAM, 64 GB storage)
- `xLargeLinux` (16 cores, 64 GB RAM, 128 GB storage)
- `xLargePremiumLinux` (16 cores, 64 GB RAM, 128 GB storage, premium hardware)

For the most up-to-date list, check the [GitHub Codespaces documentation](https://docs.github.com/en/codespaces/setting-up-your-project-for-codespaces/setting-a-minimum-specification-for-codespace-machines).

