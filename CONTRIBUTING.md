# Contributing

Thanks for your interest in agent-sync.

## Ground rules

- `bin/agent` is POSIX sh: no bashisms or language-runtime dependencies, and
  it must behave identically on macOS and Linux. `shellcheck` must pass.
- Never add a dependency to satisfy tooling; the zero-dependency install is
  the point.
- New sync targets belong in the `targets()` table; new memory sources
  belong in `sources_for()`. Exclude any file agent-sync itself generates,
  or sync loops will feed the tool its own output.
- Code comments are sparse and single-line, stating non-obvious constraints
  only.
- Intentional deviations from the shared oss-engineering-standards
  templates: `.gitignore` (the template ignores `bin/`, which is this
  project's product) and `.editorconfig` (no Go section; there is no Go
  here). Do not "fix" these back to the templates.

## Developing

```sh
make test        # syntax check + isolated behavioral regression suite
shellcheck bin/agent
```

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
matching `vX.Y.Z` tag. Publishing runs the release workflow, which verifies
the binary declares the released version, attaches it with `SHA256SUMS`,
and bumps the Homebrew formula. Nothing is published by hand.

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
- GitHub Actions must use approved major-version tags such as `@v4`, not
  full-commit SHA pins.
