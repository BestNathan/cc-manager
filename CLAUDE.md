# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**cc-manager** (`ccm`) is a zero-dependency Bash CLI that manages multiple Claude Code environments. Each "profile" stores a different API gateway URL, auth token, and model mapping (Opus/Sonnet/Haiku/subagent) in a `.env` file. `ccm run <profile>` sources that profile and `exec`s the `claude` CLI.

Repo: https://github.com/BestNathan/cc-manager

## Directory Structure

```
ccm                  # Main CLI script (entry point, ~272 lines)
install.sh           # Cross-platform installer (local/clone/curl-pipe)
template.env         # Profile template (placeholder values)
completions/_ccm     # zsh tab completion
tests/
  helpers.sh         # Test harness: assert_eq, assert_contains, setup/teardown, fake claude stub
  test_ccm.sh        # Main integration test suite (~27 assertions)
  test_install.sh    # Tests for install.sh detect_bin_dir()
  run_all.sh         # Test runner (executes all test_*.sh)
```

The project is flat — no `src/`, `lib/`, or `bin/` subdirectory. All source lives at the root.

## Development Commands

```bash
# Run all tests
bash tests/run_all.sh

# Syntax check
bash -n ccm

# Install locally (creates symlink + zsh completion)
./install.sh
```

### Running a single test

Edit `tests/run_all.sh` to source only the desired `test_*.sh`, or run directly:

```bash
bash tests/test_ccm.sh        # main suite
bash tests/test_install.sh    # install tests
```

The test harness (`helpers.sh`) uses a sandbox `CCM_HOME` (temp dir) and a fake `claude` stub that writes relevant env vars and argv to a temp file. Set `CCM_BIN` to the `ccm` absolute path before sourcing `helpers.sh`.

## Architecture

### Main CLI (`ccm`)

Self-contained Bash script with no external dependencies (beyond `bash`). Structure:

1. **Constants** (top): `CCM_VERSION`, `CCM_HOME`, `PROFILES_DIR`, `TEMPLATE`
2. **Helpers**:
   - `_die <code> <msg>` — error + exit
   - `_ensure_skeleton` — creates `~/.cc-manager/` and `template.env` on first run
   - `_profile_path <name>` — resolves `~/.cc-manager/profiles/<name>.env`
   - `_check_settings_anthropic` — scans `.claude/settings.json` and `~/.claude/settings.json` for `env.ANTHROPIC_*` conflicts (uses `jq` if available, falls back to `grep`)
   - `_mask` — redacts secrets for display
3. **Subcommands** (`cmd_*`): `list`, `new`, `edit`, `show`, `env`, `rm`, `backup-list`, `backup-restore`, `run`
4. **`main`** (bottom): dispatches on `$1` (default: `help`)

### `ccm run` flow

1. Resolve profile → `~/.cc-manager/profiles/<name>.env`
2. Source it: `set -a; . "$pf"; set +a`
3. Apply model overrides (`--opus`, `--sonnet`, `--haiku`, `--subagent`) — sets both `ANTHROPIC_DEFAULT_<TIER>_MODEL` and `..._MODEL_NAME`
4. Check for `settings.json` conflicts → print warning if found
5. `exec claude "${passthrough[@]}"` — replaces the shell with `claude`, passing through any args after `--`

### Profile files

- Location: `~/.cc-manager/profiles/<name>.env` (permission 600)
- Format: `export KEY=VAL` lines
- Contains: `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, model mappings, optional `CLAUDE_CODE_SUBAGENT_MODEL`
- Names cannot contain `/` or `..` (path traversal prevention)

### Install flow (`install.sh`)

Three modes: local (from repo), piped (`curl | bash`), clone (`--clone` flag). Creates symlink in detected `bin/` dir, copies `template.env` and zsh completion, prompts for PATH/fpath if needed.

## Key Constraints

- Pure Bash, zero external dependencies (no `npm`, `pip`, etc.)
- Profile files stored as plaintext `.env` (file-permission protected, not encrypted)
- Settings conflict detection requires `jq` for full precision; falls back to `grep`
- Linux/macOS only

## Autocompletion Constraint

**When adding or modifying any command/subcommand, you MUST also update `completions/_ccm` accordingly.** This is a hard requirement — never commit command changes without updating zsh autocompletion in the same commit.
