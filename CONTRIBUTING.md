# Contributing

Thanks for your interest in agent-sync.

## Ground rules

- `bin/agent` is POSIX sh: no bashisms or language-runtime dependencies, and
  it must behave identically on macOS and Linux. `shellcheck` must pass.
- Never add a dependency to satisfy tooling; the zero-dependency install is
  the point.
- New sync targets belong in the `targets()` table; new memory sources
  belong in `sources_for()`. Exclude any file agent-sync itself generates,
  or sync loops will feed the tool its own output. Cite the tool's official
  documentation for every path, and read
  [docs/compatibility.md](docs/compatibility.md) before removing or moving
  an existing target.
- Code comments are sparse and single-line, stating non-obvious constraints
  only.
- Intentional deviations from the shared oss-engineering-standards
  templates: `.gitignore` (the template ignores `bin/`, which is this
  project's product) and `.editorconfig` (no Go section; there is no Go
  here). Do not "fix" these back to the templates.

## Developing

```sh
make test              # syntax check + every behavioral suite
sh tests/mcp_test.sh   # or one suite on its own
shellcheck bin/agent
```

The suites live in `tests/*_test.sh`, one per surface (sync, mcp, skills,
pack, link, hooks, workflow policy). Each sources `tests/lib.sh`, which
builds its own throwaway fixture, so they are independent and can run in
any order. A new suite is picked up by `make test` automatically.

`make test` uses `AGENT_SYNC_HOME` and `AGENT_SYNC_SOURCE` to build an isolated
fixture. It never reads or mutates your real agent configuration. For manual
testing against a scratch agent root:

```sh
AGENT_SYNC_HOME=/tmp/scratch-agents \
  AGENT_SYNC_SOURCE=/tmp/scratch-canon.md \
  bin/agent sync --synthesizer deterministic
```

## Releases

Every change lands through a pull request; the required checks are the
behavioral suite on ubuntu and macos plus skill validation. To release,
bump `VERSION` in `bin/agent` and add a `CHANGELOG.md` entry in that pull
request, then publish a release on the GitHub Releases page with the
matching `vX.Y.Z` tag. Saving it as a draft first is fine; the automation
runs on publication either way.

Publishing reruns the suite and ShellCheck (a release can be cut from a
commit that bypassed the pull-request checks), verifies the binary declares
the released version, validates the bundled skill, attaches `agent` and
`SHA256SUMS` with a signed build-provenance attestation, bumps the Homebrew
formula, then smoke tests the published artifacts: the checksum-verifying
installer on ubuntu and macos, `gh attestation verify`, and a Homebrew
install from the tap. Nothing is published by hand.

GitHub's immutable releases are **not** enabled, and cannot be while
releases are published by hand. Immutability requires every asset to exist
before publication, but GitHub does not run workflows when a draft is
saved (only `published` fires for drafts), so assets can only be attached
after the release goes public. Enabling immutability would mean giving up
the Releases-page ritual in favour of a `workflow_dispatch` release that
creates the draft, uploads, and publishes in one automated run.

The bundled skill rides the same release tags: `gh skill install` resolves
`--pin vX.Y.Z` against them directly, so the skill needs no release of its
own and no second version line. CI validates it on every pull request with
`gh skill publish --dry-run`; the repository's `agent-skills` topic is what
makes it discoverable.

## Pull requests

- Keep PRs small and focused; one behavior change per PR.
- A behavior change needs a regression test.
- CI runs shellcheck (Linux) and the behavioral suite on ubuntu and macos; both
  must be green.
- GitHub Actions are pinned to full-commit SHAs with the version in a
  trailing comment (`@11bd719... # v4.2.2`). Dependabot rewrites both on
  update, so pinning costs no readability and a compromised upstream tag
  cannot silently change what CI runs.
