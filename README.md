# puma-release

Automate Puma releases from a local Puma checkout.

`puma-release` handles the repeatable parts of the Puma release process: checking repo state, proposing the version bump, updating release files, opening the release PR, building gems, and publishing the GitHub release. It follows the upstream [`Release.md`](https://github.com/puma/puma/blob/main/Release.md) workflow.

## Requirements

- `git`, `gh`, `bundle`
- GPG signing configured for commits and tags
- An AI agent set via `AGENT_CMD` (defaults to `claude`) for changelog generation

```sh
bundle install
```

## Quickstart

```sh
exe/puma-release --repo-dir /path/to/puma run
```

`run` detects the current release stage and executes the right step. If nothing needs doing, it says so.

## Common workflows

**Prepare against your fork:**

```sh
exe/puma-release --repo-dir /path/to/puma --release-repo yourname/puma run
```

**Real release to `puma/puma`:**

```sh
exe/puma-release --repo-dir /path/to/puma --live --release-repo puma/puma run
```

**Stable branch (patch) release:**

Check out the stable branch in your Puma clone first, then:

```sh
exe/puma-release --repo-dir /path/to/puma --live --release-repo puma/puma run
```

`puma-release` auto-detects the base branch from your current git branch. Pass `--base-branch` to override:

```sh
exe/puma-release --repo-dir /path/to/puma --base-branch 6-1-stable --live --release-repo puma/puma run
```

**Skip CI during prepare:**

```sh
exe/puma-release --repo-dir /path/to/puma --skip-ci-check prepare
```

## Commands

```sh
puma-release [options] [command]
```

| Command | What it does |
|---------|-------------|
| `prepare` | Verifies checkout, recommends version, updates `History.md` and `lib/puma/const.rb`, opens release PR, creates draft GitHub release on a `vX.Y.Z-proposal` tag |
| `build` | Creates and pushes the final `vX.Y.Z` tag, builds MRI and JRuby gems |
| `github` | Promotes draft release to final, uploads gem artifacts, publishes |
| `run` | Detects current stage and runs the right command |

## Options

| Flag | Description |
|------|-------------|
| `--repo-dir PATH` | Path to the Puma checkout |
| `--base-branch BRANCH` | Base branch for the release (default: current git branch) |
| `--release-repo OWNER/REPO` | Repo for writes (branches, tags, PRs, releases) |
| `--metadata-repo OWNER/REPO` | Repo for CI and commit metadata. Defaults to `puma/puma` |
| `--live` | Allow writes to the metadata repo for a real release |
| `--skip-ci-check` | Skip CI check during `prepare` |
| `--allow-unknown-ci` | Continue when GitHub can't report CI state for `HEAD` |
| `--changelog-backend auto\|agent\|communique` | Changelog generation backend |
| `--codename NAME` | Set the release codename directly |
| `-y`, `--yes` | Skip interactive confirmations |
| `--debug` | Enable debug logging |

## Environment

| Variable | Description |
|----------|-------------|
| `AGENT_CMD` | AI agent command. Defaults to `claude`. Set to `pi` to use pi with `--thinking xhigh` |
| `PUMA_RELEASE_JRUBY_BUILD_COMMAND` | Override for building the JRuby gem |
| `CHANGELOG_MAX_ATTEMPTS` | Retry count for changelog generation |

## Safety model

Writes are fork-first by default:

- `metadata_repo` is read-only (CI checks, commit links, PR metadata).
- `release_repo` is where writes go (branches, tags, PRs, releases).
- Without `--live`, `puma-release` prefers your authenticated fork, then a non-upstream `origin`. If it can't find a plausible fork, it refuses writes unless you pass `--release-repo` or `--live`.
- Writing to `puma/puma` requires `--live`.
- In live mode, every mutating git command and GitHub write shows the exact command and asks for confirmation unless you pass `--yes`.
- `prepare` uses a `vX.Y.Z-proposal` tag for the draft; the real `vX.Y.Z` tag is only created during `build`.

## Development

```sh
bundle exec rake test
```

## License

MIT. See [LICENSE](LICENSE).
