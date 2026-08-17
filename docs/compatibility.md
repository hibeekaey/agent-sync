# Compatibility and support

What agent-sync promises, what it depends on, and how things get removed.

## Platforms

| Platform | Status |
| --- | --- |
| macOS | Supported and tested in CI on every change |
| Linux | Supported and tested in CI on every change |
| Windows via WSL | Supported, not tested in CI. See [windows.md](windows.md) |
| Windows native | Unsupported |

`bin/agent` is POSIX sh with no language runtime. It uses only utilities
present in a default macOS or Linux install: `awk`, `sed`, `grep`, `find`,
`cksum`, `mktemp`, `cmp`, `diff`, `tar`. Two features need more: memory
packs need `curl` and `tar`, and semantic synthesis needs a configured
Claude Code or Codex CLI. Everything else works with coreutils alone.

## What agent-sync depends on in other tools

Two kinds of dependency, with different failure modes.

**Filesystem paths.** Every target's global instructions path and every
memory store location was taken from that tool's official documentation.
A tool that moves its path breaks quietly: agent-sync writes a file nobody
reads. Guard: `agent doctor` reports what it detected, and `agent targets`
lists every path so a change is visible.

**CLI flag grammar.** `agent mcp sync` executes other vendors' CLIs
(`claude mcp add-json --scope`, `codex mcp add --url`, `gemini mcp add
--transport`, and the Qwen and Amp equivalents). A tool that changes its
flags breaks loudly, mid-run. Guard: the weekly `compat` workflow installs
those CLIs and asserts the flags still exist in their help output, so a
break surfaces as a failed scheduled run rather than a user's broken
configuration.

Neither contract is ours to control. Where a vendor removes a capability we
depend on, the affected target is deprecated per the policy below.

## Supported versions of the agents

agent-sync tracks each tool's **current stable release**. It does not
pin, detect, or branch on agent versions, because these tools ship
continuously and their config locations are stable across releases far more
often than not.

In practice this means: if a tool is installed and its config directory
exists, agent-sync writes the documented path. If that tool later changes
the path, the fix ships in the next agent-sync release rather than being
version-gated.

## Versioning

Semantic versioning, where the public surface is: the command line
(verbs, flags, exit codes), the environment variables, the on-disk state
formats listed below, and which paths get written.

| Change | Bump |
| --- | --- |
| Removing or renaming a verb, flag or environment variable | Major |
| Removing a sync target, or changing where an existing target is written | Major |
| Changing a state-file format incompatibly | Major |
| Adding a target, verb, flag or memory source | Minor |
| Fixing behavior without changing the surface | Patch |

Exit codes are part of the contract: `status` and `diff` exit 1 when
anything is stale, so they are usable as cron and CI gates.

## Stable on-disk state

These are read and written across versions and will not change format
without a major bump:

| Path | Contents |
| --- | --- |
| The synthesized memory file | Markdown, with agent-sync's sections delimited by `<!-- agent-sync:begin imported:NAME -->` markers |
| `<gather dir>/.agent-manifest` | Tab-separated staged filename and source path |
| `~/.config/agent-sync/packs.lock` | Tab-separated pack name, source, ref and pinned commit |
| `~/.config/agent-sync/mcp.d/*.spec` | Line-based `key=value` MCP server specifications |
| `~/.config/agent-sync/mcp-owned`, `skills-owned` | Newline-separated paths agent-sync created and may rewrite |

Not stable, and safe to change at any time: internal function names, log
wording, and the layout of temporary files.

## Deprecating a target

When a tool is discontinued, renames its configuration, or removes a
capability agent-sync uses:

1. The next release documents it in `CHANGELOG.md` and keeps the target
   working if it still can.
2. The target remains for at least one more minor release, where practical
   emitting a note when it is used.
3. Removal lands in a major release.

Removal is never silent. A target disappearing without a changelog entry is
a bug worth reporting.

## Reporting a break

A path or grammar that no longer matches its tool is a normal bug: open an
issue with the tool, its version, and the documentation showing the current
location. Security-relevant reports follow [SECURITY.md](../SECURITY.md)
instead.
