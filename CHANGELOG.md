# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project adheres to [Semantic Versioning](https://semver.org/).

## [1.3.1] - 2026-08-16

### Added

| Feature | Behaviour |
| --- | --- |
| Skill license metadata | Declares the bundled coordinator skill under MIT |
| Codex interface metadata | Provides display text and a default invocation prompt |
| Skill publication gate | Validates the Agent Skills package with GitHub CLI in CI |

## [1.3.0] - 2026-08-16

### Added

| Feature | Behaviour |
| --- | --- |
| Automatic synthesis | Claude, then Codex, then deterministic fallback |
| `--synthesizer MODE` | Select `auto`, `claude`, `codex`, or `deterministic` for `sync` and `apply` |
| Built-in environment modes | `AGENT_SYNC_SYNTHESIZER` accepts the same names while retaining custom-command support |
| Constrained model execution | Claude is non-persistent; Codex is ephemeral and read-only |

## [1.2.2] - 2026-08-16

### Fixed

- Use an explicit POSIX conditional in `apply` so the Linux ShellCheck gate
  accepts the release.

## [1.2.1] - 2026-08-16

### Fixed

| Issue | Resolution |
| --- | --- |
| Private memory in predictable temporary files | Private `mktemp` files, restrictive permissions and signal cleanup |
| Deleted source memories remaining in imported sections | Empty sources now remove their managed sections |
| Canon truncation from malformed import markers | Full marker preflight before any sync mutation |
| Custom synthesized sources leaving Claude stale | Claude becomes a sync target when the source lives elsewhere |
| Unsafe `apply` manifest destinations | Preflight restricts writes to supported memory stores and rejects staged symlinks |

## [1.2.0] - 2026-08-16

### Added

- `agent apply [DIR]`: push edited staged files from a gather directory
  back to their original stores, then run the full sync, completing the
  gather, edit, apply loop.
- `gather` now writes a `.agent-manifest` mapping each staged file to its
  source path (with collision-safe staged names), which is what makes
  `apply` possible.

## [1.1.0] - 2026-08-16

### Changed

- `sync` is now a full round trip: it gathers every agent's own memory
  stores, folds them into the synthesized memory file under managed
  markers, optionally runs a semantic synthesizer
  (`AGENT_SYNC_SYNTHESIZER`), then redistributes to all installed agents.
- `migrate` folds a single agent's stores in and redistributes.
- Claude's per-project `MEMORY.md` index files are excluded from gathering
  (indexes, not memories).

### Added

- `AGENT_SYNC_SYNTHESIZER`: a command reading a merge prompt on stdin and
  printing the merged document on stdout (for example `claude -p`); the
  previous file is kept at `<file>.bak`.
- Recursion guard so a synthesizer-spawned agent never re-enters agent-sync.
- Community health files, issue/PR templates, `.editorconfig`, this
  changelog.

## [1.0.0] - 2026-08-16

### Added

- `agent sync`, `agent status`, `agent targets`, `agent migrate`,
  `agent gather`.
- Targets: Codex, Gemini, Qwen, Continue, Windsurf, Cursor (generated
  `.mdc`).
- `make install` (macOS and Linux, POSIX sh), CI (shellcheck + smoke on
  ubuntu and macos), MIT license.
- `docs/coordination.md`: cross-agent task coordination protocol (headless
  invocation, task directories, mkdir locks, git worktrees), with a
  verified Claude Code to Codex round trip.
