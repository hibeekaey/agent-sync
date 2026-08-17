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
behavioral suite on ubuntu and macos plus skill validation.

**Merging the version bump is the release.** To ship one, put two things in
the pull request: a new `VERSION` in `bin/agent`, and a matching
`CHANGELOG.md` entry. Nothing else. On merge, the release workflow compares
`VERSION` against the current release and, when it differs, cuts the
release itself.

That means no tag to push and no button to click. A merge that does not
change `VERSION` releases nothing, so ordinary changes need no thought at
all.

What the workflow does, in order: reruns the suite and ShellCheck (a
release can be cut from a commit that bypassed the pull-request checks),
composes the notes, creates a **draft**, validates the bundled skill,
attaches `agent` and `SHA256SUMS` with a signed build-provenance
attestation, publishes the draft, bumps the Homebrew formula, then smoke
tests what shipped: the checksum-verifying installer on ubuntu and macos,
`gh attestation verify`, and a Homebrew install from the tap.

Release notes are the `CHANGELOG.md` section for that version, always
followed by the commit log, diffstat and compare link since the previous
release. Without a changelog entry the commit log stands alone, so a
release is never noteless.

Two refusals worth knowing: a `VERSION` that is not newer than the current
release fails rather than tagging history backwards, and a version already
released is a no-op rather than an error.

Do not create releases by hand. Assets must be attached before publication,
because immutable releases are enabled: publishing freezes the release's tag
and assets. A hand-published release ships with no binary, no checksums and
no attestation, and cannot be repaired in place.

**Recovering from a broken release: bump to the next patch version and
merge. Never delete the release and reuse its tag.** GitHub retires the tag
name of a deleted immutable release permanently, even across repository
deletion and recreation, so deleting burns that version number forever. The
`release-guard` workflow fails loudly and says the same thing.

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
