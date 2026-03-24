# puma-release

Automate Puma releases from a local Puma checkout.

`puma-release` handles the repeatable parts of the Puma release process: checking repo state, proposing the version bump, updating release files, opening the release PR, building gems, and publishing the GitHub release.

It follows the upstream [`Release.md`](https://github.com/puma/puma/blob/main/Release.md) workflow, but runs against your local Puma clone.

## What it does

The CLI moves through Puma's release flow in three steps:

1. **`prepare`**
   - verifies your checkout is ready
   - checks CI by default
   - recommends the next version
   - updates `History.md` and `lib/puma/const.rb`
   - opens a release PR
   - creates a draft GitHub release
2. **`build`**
   - creates and pushes the release tag
   - builds the MRI gem
   - builds the JRuby gem when possible
3. **`github`**
   - publishes the GitHub release
   - uploads the built gem artifacts

`run` detects the next step automatically and runs the right command.

## Safety model

This tool is designed to make fork-based release prep the default.

- `metadata_repo` is used for read-only operations such as CI checks, commit links, and PR metadata.
- `release_repo` is used for writes such as pushing branches and tags, opening PRs, and editing releases.
- Without `--live`, `puma-release` prefers a fork remote from your checkout.
- Writing to `puma/puma` requires an explicit `--live` opt-in.
- When `--live` is set, the CLI prints a prominent warning before write steps.

## Requirements

Install the project dependencies:

```sh
bundle install
```

You will also need these tools available in your shell:

- `git`
- `gh`
- `bundle`
- the agent binary configured by `AGENT_CMD` for version/changelog generation

## Quickstart

Run the executable directly from this repository:

```sh
exe/puma-release --repo-dir /path/to/puma run
```

That is the safe default: it uses upstream Puma for metadata and prefers a fork for release writes.

### Common workflows

#### Prepare a release against your fork

```sh
exe/puma-release \
  --repo-dir /path/to/puma \
  --release-repo yourname/puma \
  run
```

#### Run the real release against `puma/puma`

```sh
exe/puma-release \
  --repo-dir /path/to/puma \
  --live \
  --release-repo puma/puma \
  run
```

#### Skip CI during `prepare`

```sh
exe/puma-release \
  --repo-dir /path/to/puma \
  --skip-ci-check \
  prepare
```

## Usage

```sh
puma-release [options] [command]
```

### Commands

- `prepare` — open the release PR and create the draft GitHub release
- `build` — create the release tag and build gem artifacts
- `github` — publish the GitHub release and upload assets
- `run` — detect the next step and run it

### Options

- `--repo-dir PATH` — path to the Puma checkout
- `--release-repo OWNER/REPO` — repo where branches, tags, PRs, and releases are written
- `--metadata-repo OWNER/REPO` — repo used for commit links, CI, and PR metadata. Defaults to `puma/puma`
- `--live` — allow writes to the metadata repo for the real release
- `--allow-unknown-ci` — continue if GitHub does not expose CI state for `HEAD`
- `--skip-ci-check` — skip the CI check entirely during `prepare`
- `--changelog-backend auto|agent|communique` — choose the changelog generation backend
- `-y`, `--yes` — skip interactive confirmations
- `--debug` — enable debug logging

## Environment

- `AGENT_CMD` — command used for structured AI calls. Defaults to `claude`
- `PUMA_RELEASE_JRUBY_BUILD_COMMAND` — optional override for building the JRuby gem
- `CHANGELOG_MAX_ATTEMPTS` — retry count for changelog generation

## Development

Run the test suite:

```sh
bundle exec rake test
```

Optional fork smoke test:

```sh
PUMA_RELEASE_SMOKE=1 bundle exec ruby -Itest test/integration/fork_smoke_test.rb
```

## Contributing

Issues and pull requests are welcome.

When making changes:

1. keep behavior changes covered by tests
2. run `bundle exec rake test`
3. update `README.md` when the CLI behavior or safety model changes

## License

MIT. See [LICENSE](LICENSE).
