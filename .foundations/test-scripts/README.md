# Demo Repo Scripts

Create and delete demo repositories across GitHub.com and GitHub Enterprise instances. Three zsh scripts handle the lifecycle: **setup** your environment, **create** repos from templates, and **delete** them when done.

## Prerequisites

- **zsh** (default on macOS)
- [**GitHub CLI (`gh`)**](https://cli.github.com/) — `brew install gh`
- Authentication to each GitHub host (see [Authentication](#authentication))

## Quick Start

```zsh
# 1. Configure your targets and templates (one-time)
./setup-demo-env.zsh

# 2. Restart your shell (or source the env file)
source ~/.demo-repos.env

# 3. Create demo repos (interactive)
./create-demo-repos.zsh

# 4. Delete demo repos when done
./delete-demo-repos.zsh
```

## Setup — `setup-demo-env.zsh`

Interactive wizard that writes `~/.demo-repos.env` with two environment variables consumed by the create and delete scripts:

| Variable | Format | Example |
|---|---|---|
| `DEMO_REPO_TARGETS` | Comma-separated `HOST::ACCOUNT` pairs | `github.com::MyOrg,ghe.company.com::MyTeam` |
| `DEMO_REPO_TEMPLATES` | Comma-separated `ORG/REPO` or `HOST::ORG/REPO` | `MyOrg/app-template,github.ibm.com::Team/iac-template` |

The setup script will:
- Load existing entries from `~/.demo-repos.env` (if present) and deduplicate
- Optionally add a `source` line to `~/.zshrc`

Both `DEMO_REPO_TARGETS` and `DEMO_REPO_TEMPLATES` must be set before running the create or delete scripts.

## Authentication

The scripts delegate authentication entirely to the `gh` CLI, which natively resolves tokens per host:

| Variable | Scope |
|---|---|
| `GH_TOKEN` | All hosts (global override) |
| `GITHUB_TOKEN` | github.com only |
| `GH_ENTERPRISE_TOKEN` | Enterprise hosts only |

If none of these are set, `gh` falls back to its own auth store. You can authenticate interactively:

```zsh
gh auth login                              # github.com
gh auth login --hostname your-ghe.com      # GitHub Enterprise
```

## Create — `create-demo-repos.zsh`

Creates demo repositories by cloning a template (all branches and tags) and pushing to a target account.

```zsh
./create-demo-repos.zsh [OPTIONS]
```

### Options

| Flag | Description | Default |
|---|---|---|
| `-t`, `--template NUM\|ORG/REPO` | Template selection (index or direct reference) | Interactive menu |
| `-c`, `--count NUMBER` | Number of repos to create | `1` |
| `-a`, `--account NAME` | Target GitHub account/org | First `DEMO_REPO_TARGETS` entry |
| `-n`, `--name BASE_NAME` | Base repo name | Auto-derived from template (`*-template` → `*-demo`) |
| `-p`, `--path PATH` | Local clone directory | `~/Documents/repos` |
| `-h`, `--host HOST` | GitHub Enterprise hostname | First `DEMO_REPO_TARGETS` entry |
| `-v`, `--visibility TYPE` | `public` or `private` | `public` |
| `--help` | Show help | |

### Examples

```zsh
# Interactive mode — pick template and destination via arrow keys
./create-demo-repos.zsh

# Use template #1, create 5 repos
./create-demo-repos.zsh -t 1 -c 5

# Different account, private repos
./create-demo-repos.zsh -a MyOrg -v private -t 2 -c 3
```

Repos are numbered sequentially (e.g., `ai-iac-consumer-demo01`, `demo02`, ...). The script auto-detects existing repos and starts numbering from the next available slot.

## Delete — `delete-demo-repos.zsh`

Deletes demo repositories both remotely (via `gh`) and locally (the cloned directory).

```zsh
./delete-demo-repos.zsh [OPTIONS] [REPO_NAME ...]
```

### Options

| Flag | Description | Default |
|---|---|---|
| `-a`, `--account NAME` | GitHub account/org | Interactive menu |
| `-H`, `--host HOST` | GitHub hostname | Interactive menu |
| `-p`, `--path PATH` | Local base path | `~/Documents/repos` |
| `-f`, `--file FILE` | Read repo names from file (one per line) | |
| `-y`, `--yes` | Skip confirmation prompt | `false` |
| `--dry-run` | Show what would be deleted without doing it | `false` |
| `--help` | Show help | |

### Examples

```zsh
# Interactive mode — pick target and repo via arrow keys
./delete-demo-repos.zsh

# Delete specific repos
./delete-demo-repos.zsh -a MyOrg -H github.example.com ai-iac-consumer-demo01 ai-iac-consumer-demo02

# Delete a range (zsh brace expansion)
./delete-demo-repos.zsh ai-iac-consumer-demo{01..10}

# Dry run first, then delete
./delete-demo-repos.zsh --dry-run ai-iac-consumer-demo{01..05}
./delete-demo-repos.zsh -y ai-iac-consumer-demo{01..05}

# Delete from a file
./delete-demo-repos.zsh -f repos-to-delete.txt
```

## Environment Variables

| Variable | Used by | Description | Default |
|---|---|---|---|
| `DEMO_REPO_TARGETS` | create, delete | `HOST::ACCOUNT` pairs (comma-separated) | *Required* — set via `setup-demo-env.zsh` |
| `DEMO_REPO_TEMPLATES` | create | Template repos (comma-separated) | *Required* — set via `setup-demo-env.zsh` |
| `GH_TOKEN` | gh CLI | Auth token for all hosts (global override) | |
| `GITHUB_TOKEN` | gh CLI | Auth token for github.com | |
| `GH_ENTERPRISE_TOKEN` | gh CLI | Auth token for enterprise hosts | |
| `GITHUB_HOST` | create | Default GitHub Enterprise hostname | First `DEMO_REPO_TARGETS` entry |
| `GITHUB_ACCOUNT` | create | Default target account | First `DEMO_REPO_TARGETS` entry |
| `CLONE_BASE_PATH` | create, delete | Local directory for cloned repos | `~/Documents/repos` |
| `REPO_COUNT` | create | Number of repos to create | `1` |
| `REPO_VISIBILITY` | create | Repo visibility (`public`/`private`) | `public` |
