# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project adheres to [Semantic Versioning](https://semver.org/).

## [1.10.0] - 2026-09-04

### Changed

- A sync keeps the file under budget. When a model synthesis leaves the
  file over `AGENT_SYNC_BUDGET`, the same run trims it back: never on the
  deterministic path (a hook stays fast), never touching an imported block
  or archiving a store, and the `.bak` the synthesis wrote stays the
  pre-sync file. `--no-compact` or `AGENT_SYNC_COMPACT=0` skips it.
- Compaction plans largest-first instead of shaving every section by the
  same percentage. Round one asks the biggest candidates for at most a 30%
  cut until the deficit is covered (an import, when `compact` is run by
  hand, is always promoted, with a lighter first ask and never planned below
  a quarter of its size); only when that is not enough does round two deepen
  the same sections toward the floors. A small overrun costs one or two
  large appendices a light trim and leaves the dense small sections alone,
  where the old plan took 8% off every section including the rule tables.

## [1.9.0] - 2026-09-04

### Changed

- A sync folds instead of rewriting. The model sees the file as read-only
  context and the newly imported memories, and answers with only the
  sections that change (an existing `## ` heading copied exactly, or
  `## Promoted from <agent>`); agent-sync splices them in. A whole-document
  rewrite made the model re-emit 148 KB to absorb a few lines and took ten
  minutes; a fold answers in a fraction of that. An import block folded on an
  earlier sync (same fingerprint, every identifier still in the curated text)
  is dropped with no model call, so a sync with nothing new is free, and a
  fact removed from the curated text by hand brings its block back for
  folding. The answer is refused, and the next rung tried, when it is not
  sections, echoes an import block, repeats a heading, shrinks a section past
  70% (a fold adds), or drops an identifier; the whole-document identifier
  guard and size floor still apply to the spliced result. `--rewrite` (or
  `AGENT_SYNC_REWRITE=1`) asks for the old whole-document rewrite; a custom
  synthesizer command keeps its whole-document contract.

## [1.8.1] - 2026-09-04

### Added

- Progress and a stop clock for the model call. A whole-document rewrite
  prints nothing until its last token, so an eight-minute synthesis read as
  a hang; `sync` now says what it is doing, a dot lands on stderr every 30
  seconds on a terminal (`AGENT_SYNC_SYNTH_HEARTBEAT`), and a model still
  running after `AGENT_SYNC_SYNTH_TIMEOUT` seconds (default 1200) is stopped
  so the fallback chain runs instead of the sync hanging.
- The script decides the model. Claude tries `fable`, `opus`, `sonnet` at
  `low` effort and Codex tries `gpt-5.6-terra`, `gpt-5.5`, `gpt-5.4` at
  `low`, instead of whatever each CLI is set to interactively, so a sync
  behaves the same on every machine. A rung that is out of credits,
  rate-limited or unknown fails in seconds and the next runs; one whose
  answer fails the guard hands over too; the deterministic merge is the last
  resort. Each hand-over is one plain line naming the model, the elapsed
  time and the vendor's own reason. Override for one run with
  `--claude-model`, `--claude-effort`, `--codex-model`, `--codex-effort`
  (sync, apply, compact) or standing with `AGENT_SYNC_CLAUDE_MODEL`,
  `AGENT_SYNC_CLAUDE_EFFORT`, `AGENT_SYNC_CODEX_MODEL`,
  `AGENT_SYNC_CODEX_EFFORT`. Both vendors run with their MCP servers off,
  so a broken or login-prompting server on the user's side cannot slow or
  break the rewrite.
- One sync writes at a time. A second run started while another holds
  `~/.config/agent-sync/sync.lock` exits 1 naming the holder's pid; a lock
  left by a killed run is reclaimed. Dry runs are not blocked.

### Fixed

- The keep rules never reached the synthesizer: `$(compact_keep_rules)` sat
  inside a quoted heredoc, so the prompt carried that literal text instead
  of the rules on what to keep and what may be forgotten.
- A file edited while the model ran (a hook firing, an editor) was
  overwritten by a rewrite that never saw the edit. The edited file is now
  kept and distributed, and the message says to run `agent sync` again.

## [1.8.0] - 2026-09-04

### Added

- `compact` rewrites sections concurrently, `--jobs` at a time (default 4,
  `AGENT_SYNC_COMPACT_JOBS`). Each rewrite is a model call of a minute or
  more and they ran strictly one after another, so a 19-section file took
  about 25 minutes a pass; four in flight bring that to about 8. Results are
  still reported in document order once every worker has finished.

### Fixed

- Two temporary files were shared between rewrites (the prompt and the
  preamble-trimming scratch file); each rewrite now has its own.
- Compaction archives only store versions captured by the preceding sync. A
  store created or changed while model rewrites run stays live for the next
  sync instead of being dropped from the canonical file.
- The default identifier guard now recognizes unbackticked hostnames,
  environment variables and long ids. Markdown rules after imported YAML
  frontmatter no longer hide the identifiers that follow.
- The concurrent worker queue now retains every PID after a full job window.

## [1.7.0] - 2026-09-03

### Added

- `agent compact` keeps the synthesized file under a byte budget
  (`AGENT_SYNC_BUDGET`, default 150000, or `--budget`). The deterministic
  merge re-imports every memory store verbatim on every sync, so a file that
  started at 900 curated lines had reached 4,900 with 82% of it raw imports,
  and the curated part alone stood at 195 KB against a 150 KB ceiling. When
  over budget, compact promotes each raw imported section into curated notes
  and archives its store files to `~/.config/agent-sync/archive/`, so the
  next sync has nothing to re-import; then it rewrites every curated section
  of 2 KB or more shorter with the model, one section at a time. A rewrite
  is refused and the section kept unless it starts with the same heading, is
  at least a quarter of the original, and still contains every backtick
  span, URL and letter-and-digit token the original had. The command exits at
  once while the file is within budget, so it is cheap to schedule, and it
  rejects `--synthesizer deterministic` because a merge cannot summarize. A
  rewrite that drops identifiers gets one more attempt that names exactly what
  it lost; a second drop keeps the section as it was. By default a rewrite may
  forget how a lesson was learned, items marked settled, refuted, muted or
  parked, one-off references (commit shas, PR numbers, run ids, past
  versions) and anything else of low value, while every real URL, hostname,
  environment variable and long id must survive (paths, commands and code
  words are asked for but may go with a story the rewrite forgets, which is
  where they mostly sat); `--keep-all` forbids forgetting and
  protects every backtick span and bare letter-and-digit token. Four strict
  passes on a 195 KB file stalled at 164 KB because the text had reached the
  floor that keeping every token allows.
- `sync` reports the file's size against the budget after every run;
  `status` and `doctor` fail while it is over budget.
- The whole-document semantic synthesis is now held to the same identifier
  guard: a merge that no longer contains every backtick span, URL and
  letter-and-digit token of the document is refused and the deterministic
  merge kept. The size floor alone let a merge through that had summarised
  away 919 of a 195 KB document's 1,116 identifiers while keeping 43% of its
  lines. The merge prompt also now asks for identifiers to survive verbatim.
  The guard was falsified against a real run: a section without a URL was
  unguarded because the script's `set -e` aborted the extractor at the URL
  grep, and a two-line backtick span produced a phantom identifier; both are
  pinned by tests.
- `agent hooks launchd` prints a macOS LaunchAgent that runs `agent compact`
  daily; the cron fallback gains a weekly compact line.

## [1.6.2] - 2026-08-17

### Fixed

- A synthesizer's refusal was accepted as the new memory file whenever it
  happened to open with a heading. Nothing else about the output was checked,
  so three lines of "I cannot rewrite this document" replaced the whole file
  and were redistributed to every agent, recoverable only from the `.bak`.
  A synthesis must now be at least a quarter of the document it was given.
  Shrinking is the job -- folding the imported sections away is most of it,
  and a measured real merge came in at 45% -- so the floor sits an order of
  magnitude above a refusal and well under a genuine merge.

## [1.6.1] - 2026-08-17

### Fixed

- A semantic synthesis was discarded whenever the model opened with a line of
  chat before the document. `valid_synth_output` required the very first line
  to be a heading, so one sentence of preamble threw away an otherwise correct
  merge of a 60 KB file and sent `auto` on to the next multi-minute fallback.
  Prose above the first heading is now dropped, bounded to ten lines: anything
  longer is a refusal rather than a document, and the deterministic merge
  already in place is the better answer.

## [1.6.0] - 2026-08-17

### Added

- Colour in status output: `synced` green, `STALE` bold yellow, paths cyan,
  synthesis magenta, counts bright green, failures red, and unified diffs
  painted like a diff. This is the terminal the showcase video depicts.
- `--color[=auto|always|never]` and `--no-color`, honoured on every command,
  plus `NO_COLOR`, `FORCE_COLOR` and `CLICOLOR_FORCE`. The flags are global
  and stop at a literal `--`, so a server's own `--no-color` still reaches it
  through `mcp add`.

Colour is additive: it appears only when standard output is a terminal, so
piped and redirected output, exit codes, generated markdown and JSON, hook
recipes and MCP snippets are byte-for-byte unchanged.

### Fixed

- The test harness could escape its fixture. `AGENT_SYNC_HOME` isolates the
  files agent-sync writes itself, but `mcp sync` delegates to whichever
  vendor CLI is on `PATH`, so a suite that forgot to prefix a mock `PATH`
  registered its probe server in the developer's real configuration. Every
  runner in `tests/lib.sh` now pins `PATH` to the fixture's mock directory,
  and a policy test fails the build if one stops doing so.

## [1.5.6] - 2026-08-17

### Fixed

- `skills sync` refused the entire run when any source skill was a
  symbolic link, which made the command unusable on machines where a
  plugin had installed skills as links into a shared skills directory. A
  symlinked source skill is still never copied, but it is now skipped by
  name and counted in the summary while the rest propagate.

### Added

- `docs/walkthrough.md`: every command with real output, including the
  refusals and safety behaviours that are easy to miss.

## [1.5.5] - 2026-08-17

### Fixed

- Recovery guidance for a broken release was wrong and would have destroyed
  a version number: GitHub permanently retires the tag name of a deleted
  immutable release, so `release-guard` and CONTRIBUTING now say to bump to
  the next patch instead of deleting and retrying the tag.

### Changed

- Compatibility grammar matching is boundary-aware and unit tested. Substring matching let `--scope` satisfy a check for `-s` and `additional` satisfy `add`, so the short-flag assertions could not fail; the matcher now lives in `scripts/check-cli-grammar.sh` with fixtures in `tests/compat_test.sh` pinning exactly those false positives. ShellCheck now covers `scripts/` and `tests/` as well as `bin/agent`.
- The weekly compatibility job covers every CLI grammar `agent mcp` depends
  on. Qwen Code and Amp were named in the contract but never checked, and
  the checked CLIs asserted one representative flag rather than all of
  them. Every flag and subcommand agent-sync passes is now asserted
  individually, and a package that cannot be installed after three attempts
  fails the job rather than being skipped, since a renamed or withdrawn
  package is itself a compatibility break.
- `release-guard` now requires both release assets, verifies the published
  binary's build-provenance attestation, and checks `SHA256SUMS` against
  the binary it ships with. Asset presence alone said nothing about where
  the binary came from.

## [1.5.4] - 2026-08-17

### Changed

| Area | Change |
| --- | --- |
| Releases | Merging the version bump is the release. Every push to main compares `VERSION` in `bin/agent` against the current release and cuts a new one when it changes, so there is no tag to push and no button to click. |
| Release notes | Taken from the matching `CHANGELOG.md` section, always followed by the commit log, diffstat and compare link since the previous release. A missing changelog entry falls back to the commit log alone. |
| Release integrity | The release is assembled as a draft and published only once its attested assets are attached, which is the precondition for GitHub's immutable releases. |
| Release safety | A new `release-guard` workflow fails when a release is published without its assets, which is what happens if a release is created by hand. |
| Tests | The behavioral suite is split by surface into `tests/*_test.sh` over a shared `tests/lib.sh`, each with its own isolated fixture, so a single suite can run alone. |

### Added

- `docs/compatibility.md`: supported platforms, what agent-sync depends on
  in each tool and how each dependency fails, agent version support,
  semantic-versioning scope, stable on-disk state formats, and the
  deprecation policy for removing a target.

## [1.5.3] - 2026-08-17

### Changed

| Area | Change |
| --- | --- |
| Release integrity | Publishing a release verifies it, attaches attested assets, bumps the formula, then smoke tests what shipped. Immutable releases stay off: GitHub does not run workflows when a draft is saved, so a hand-published release cannot have its assets in place beforehand. |
| Provenance | Release assets carry a signed build-provenance attestation, verifiable with `gh attestation verify`. |
| Release testing | The behavioral suite and ShellCheck run again at release time, so a commit merged with an administrator override cannot ship untested. |
| Distribution testing | Publishing smoke tests the real artifacts: the checksum-verifying installer on ubuntu and macos, attestation verification, and a Homebrew install from the tap. |
| Supply chain | GitHub Actions are pinned to commit SHAs, with Dependabot keeping the pins and their version comments current. This reverses the previous major-tag policy; Dependabot removes the readability cost that motivated it. |
| Compatibility | A weekly job checks that the CLI flag grammars `agent mcp` drives (Claude, Codex, Gemini) still exist, rather than discovering a break through a user's broken config. |

## [1.5.2] - 2026-08-17

### Fixed

| Area | Resolution |
| --- | --- |
| Memory packs | Reject selected subdirectories whose physical path escapes the downloaded repository, including directory symlinks |
| MCP file writes | Replace predictable temporary names with private adjacent `mktemp` files and atomically track ownership |
| MCP CLI updates | Track successfully applied specs, validate changed specs before replacement, restore the previous spec on failure, propagate removals and return nonzero on any failure |
| Apply options | Accept separated and equals forms of `--synthesizer`, `--only` and `--skip` before or after the gather directory |
| Project imports | Escape agent-sync control markers in native project configuration before importing it |
| Hook recipes | Use OpenCode's singular global `plugin` directory and Gemini's awaited `AfterAgent` event instead of best-effort `SessionEnd` |
| Skills | Define additive synchronization, adopt identical copies, update only agent-sync-owned copies atomically and refuse unmanaged collisions |
| Privacy | Document automatic model synthesis and MCP credential storage and output |
| Workflows | Limit release write permission to the asset-building job while retaining approved major-version action tags |

### Changed

- `agent mcp remove NAME` is propagated to CLI-managed tools on the next
  `agent mcp sync` when agent-sync recorded the applied entry.
- `agent skills sync` preserves target-only skills by contract rather than
  claiming an exact mirror.

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
