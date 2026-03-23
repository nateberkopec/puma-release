# puma-release

Standalone CLI for running Puma's release process against a Puma checkout.

## What it does

It follows `Release.md` in `puma/puma`:

1. `prepare` checks out a clean `main`, verifies CI, recommends the next version,
   updates `History.md` and `lib/puma/const.rb`, opens a release PR, and creates a
   draft GitHub release.
2. `build` tags the merged release, builds the gem artifacts, and stops before the
   manual `gem push` step.
3. `github` publishes the GitHub release and uploads the built gems.
4. `run` detects the next step and runs it interactively.

The tool operates on a Puma checkout, not on this repository.

## Installation

```sh
bundle install
```

Then run the executable directly:

```sh
exe/puma-release --repo-dir /path/to/puma run
```

## Usage

```sh
puma-release [options] [command]
```

Commands:

- `prepare`
- `build`
- `github`
- `run` (default)

Useful options:

- `--repo-dir PATH`: path to the Puma checkout
- `--release-repo OWNER/REPO`: repo where PRs, tags, and releases should be created
- `--metadata-repo OWNER/REPO`: repo used for PR metadata and commit links (defaults to `puma/puma`)
- `--allow-unknown-ci`: continue if GitHub does not expose CI state for `HEAD`
- `--changelog-backend auto|agent|communique`: pick changelog generation backend
- `-y`, `--yes`: skip interactive confirmation prompts

## Environment

- `AGENT_CMD`: command used for structured AI calls. Defaults to `claude`.
- `PUMA_RELEASE_JRUBY_BUILD_COMMAND`: optional override for building the JRuby gem.
- `CHANGELOG_MAX_ATTEMPTS`: retry count for changelog generation.

## Tests

```sh
bundle exec rake test
```

Optional fork smoke test:

```sh
PUMA_RELEASE_SMOKE=1 bundle exec ruby -Itest test/integration/fork_smoke_test.rb
```
