# Contributing

Thanks for your interest in agent-sync.

## Ground rules

- `bin/agent` is POSIX sh: no bashisms, no dependencies beyond coreutils,
  and it must behave identically on macOS and Linux. `shellcheck` must pass.
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
  bin/agent sync
```

## Pull requests

- Keep PRs small and focused; one behavior change per PR.
- A behavior change needs a regression test.
- CI runs shellcheck (Linux) and the behavioral suite on ubuntu and macos; both
  must be green.
