# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project adheres to [Semantic Versioning](https://semver.org/).

## [1.5.1] - 2026-08-16

### Fixed

- The release workflow now triggers on a published GitHub release rather
  than on a tag push, so publishing from the Releases page always runs the
  automation, including against a tag that already exists.
- Releases fail fast when `bin/agent` does not declare the released
  version, so a mislabeled binary can never reach the release assets or
  the Homebrew formula.

## [1.5.0] - 2026-08-16

### Added

| Feature | Behaviour |
| --- | --- |
| `agent mcp` | One MCP server registry (line-based specs, no JSON parsing) pushed to every tool: CLI-driven for Claude/Codex/Gemini/Qwen/Amp (remove-then-add, idempotent), agent-sync-owned dedicated files for Cursor/Windsurf/Kiro (never rewrites files it did not create), printable snippets for shared-settings tools |
| `agent skills sync` | Mirrors the canonical skills directory into every agent's user-scope skills directory per the gh-skill registry mapping (Codex, Gemini, Qwen, Cursor, Copilot, Continue, Kiro, Roo, OpenCode, Zed via `~/.agents/skills`) |
| `agent hooks [tool]` | Verified automation snippets: Claude SessionEnd, Codex Stop (SessionEnd's 3s cap is too tight), Gemini SessionEnd, OpenCode session.idle plugin, cron fallback |
| `agent pack` | Shareable markdown memory packs from GitHub, pinned by commit in a lockfile, folded on sync, cleanly removable |
| `agent link --import` | Folds native project configs (.cursor/rules with frontmatter, .clinerules, .windsurfrules, copilot-instructions, .roo/rules, .goosehints) verbatim into AGENTS.md |
| Target filtering | `--only`/`--skip` flags and `AGENT_SYNC_ONLY`/`AGENT_SYNC_SKIP` env vars |
| Tap auto-bump | The release workflow updates the Homebrew formula when a `TAP_TOKEN` secret is configured |
| Windows | `docs/windows.md`: WSL supported and documented |

### Notes

- All MCP command grammars and file shapes were adversarially verified
  against official documentation, including the traps: Gemini/Qwen
  `httpUrl` vs `url`, Windsurf `serverUrl`, Claude requiring explicit
  `type` on url entries, Codex TOML via its own CLI only.
- Skills mapping corrections from verification: Codex user scope is
  `~/.codex/skills` (`~/.agents/skills` is project scope); Windsurf was
  removed from the gh-skill registry and is not a skills target.

## [1.4.0] - 2026-08-16

### Added

| Feature | Behaviour |
| --- | --- |
| 10 new sync targets | OpenCode, Amp, Goose, GitHub Copilot CLI, Zed, Junie, Kiro, Crush, Roo Code, Cline — every global-instructions path verified against official documentation |
| Goose memory gathering | `~/.config/goose/memory/` folds into the synthesized file like the other stores |
| Adopt safety + `agent revert` | The first overwrite of a differing pre-existing file keeps it as `<file>.orig`; `revert` restores all `.orig` backups and the `.bak` |
| `agent link [DIR]` | Project scope: seeds a repo-root `AGENTS.md`, bridges Claude Code with an `@AGENTS.md` stub, configures Gemini CLI `context.fileName`, warns about Zed first-match shadowing |
| `agent diff` | Stale targets as unified diffs; exit 1 on drift (CI gate) |
| `agent doctor` | Setup diagnosis: file, markers, detected agents, synthesis availability, staleness |
| `--dry-run` | For `sync` and `apply`: print every action, write nothing |
| Distribution | `install.sh` with SHA256SUMS verification, release-asset workflow, bash + zsh completions, `agent(1)` man page (scdoc source + committed roff) |

### Notes

- Aider is deliberately not a target: it has no global instructions
  mechanism (verified); wire `read:` in `~/.aider.conf.yml` yourself.
- Antigravity is covered via the shared `~/.gemini/GEMINI.md` target.

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
