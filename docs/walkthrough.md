# Walkthrough

Every command, with real output. Paths and content are from a demo setup,
so substitute your own.

Output here is shown plain, which is what a pipe or a redirect gets. On a
terminal the same lines are coloured: `synced` green, `STALE` bold yellow,
paths cyan, synthesis magenta, failures red. `--no-color` turns that off and
`--color=always` keeps it through a pipe or a pager.

The examples assume three agents installed and a memory file at
`~/.claude/CLAUDE.md` reading:

```markdown
# My memory

Always run tests before pushing.
```

## agent sync

The core round trip: gather, synthesize, redistribute.

```console
$ agent sync
claude: folded 1 memory file(s) in
codex: folded 1 memory file(s) in
goose: folded 1 memory file(s) in
synthesis: deterministic merge
codex: synced -> ~/.codex/AGENTS.md
gemini: synced -> ~/.gemini/GEMINI.md
cursor: synced -> ~/.cursor/rules/best-practices.mdc
goose: synced -> ~/.config/goose/.goosehints
qwen: skipped (not installed)
...
```

**Gather** read each agent's own memory stores. **Synthesize** folded them
into the memory file. **Redistribute** wrote the result everywhere. Absent
tools are skipped, so the same binary serves every machine.

The file afterwards, with each agent's memories in a managed section:

```markdown
# My memory

Always run tests before pushing.

<!-- agent-sync:begin imported:codex -->
## Memories imported from codex

### ~/.codex/memories/prefs.md

User prefers tables over prose.

<!-- agent-sync:end imported:codex -->
```

Those markers are why syncing twice is safe: the next run replaces the
section in place rather than appending a second copy. Delete the source
memory and the section disappears on the next sync.

Targets receive whatever shape they need. Cursor gets frontmatter it
requires and nothing else does:

```console
$ head -4 ~/.cursor/rules/best-practices.mdc
---
description: Global agent memory managed by agent-sync (run: agent sync)
alwaysApply: true
---
```

`--synthesizer deterministic` above skips the model call. Plain
`agent sync` hands the whole document to Claude, or Codex as fallback, to
dedupe and fold imported blocks into your curated sections.

## agent status

Parity check, built for cron.

```console
$ agent status
codex: synced
gemini: synced
cursor: synced
amp: not installed
$ echo $?
0
```

With drift:

```console
$ agent status
gemini: STALE
1 target(s) stale; run: agent sync
$ echo $?
1
```

The exit code is the feature:

```sh
0 9 * * *  agent status || agent sync    # self-heal daily
```

## agent diff

What drifted, not just that something did.

```console
$ agent diff
=== gemini: ~/.gemini/GEMINI.md
--- ~/.gemini/GEMINI.md
+++ ~/.claude/CLAUDE.md
@@ -1 +1,39 @@
-hand-edited junk
+# My memory
...
$ echo $?
1
```

Minus is what the agent has, plus is what the memory file says it should
have. Clean setups print `all targets in sync` and exit 0, so this works
as a CI gate.

## agent doctor

Diagnosis without changes.

```console
$ agent doctor
agent v1.5.5
synthesized file: ~/.claude/CLAUDE.md
ok: synthesized file exists (120 lines)
ok: 13 sync target(s) detected (agent targets lists them)
ok: claude CLI available for semantic synthesis
note: codex CLI not installed (auto synthesis skips it)
doctor: no problems found
```

A broken setup, exit 1:

```console
$ agent doctor
PROBLEM: malformed import markers for codex in ~/.claude/CLAUDE.md
PROBLEM: targets are stale (agent diff shows details; agent sync fixes)
doctor: 2 problem(s) found
```

Missing model CLIs are a `note`, not a problem, because deterministic
synthesis works without them. The marker check matters most: agent-sync
refuses to modify a file whose managed sections are corrupted, and doctor
tells you before you hit that.

## agent targets

Where memory goes, and what was detected.

```console
$ agent targets
codex: installed (~/.codex/AGENTS.md)
gemini: installed (~/.gemini/GEMINI.md)
cursor: installed (~/.cursor/rules/best-practices.mdc)
goose: installed (~/.config/goose/.goosehints)
kiro: installed (~/.kiro/steering/agent-sync.md)
amp: not installed (would be ~/.config/amp/AGENTS.md)
```

Detection is by config directory, never configuration: install a tool and
the next sync includes it. Absent tools still show their path, so you can
see what would be written.

Claude Code is absent from this list because its file *is* the memory
file. Point `AGENT_SYNC_SOURCE` elsewhere and `claude` appears as an
ordinary target.

## agent gather

Stage every agent's memory in one place.

```console
$ agent gather /tmp/mem
gathered 5 memory file(s) into /tmp/mem
edit the staged files, then push edits everywhere with: agent apply /tmp/mem
note: gathered files can contain private context; do not commit them

$ ls /tmp/mem
claude__memory__api-notes.md
codex__memories__MEMORY.md
codex__memories__prefs.md
```

Names encode origin, and collisions get a numeric prefix rather than
overwriting. The `.agent-manifest` maps each staged file back to its
source:

```console
$ cat /tmp/mem/.agent-manifest
claude__memory__api-notes.md	~/.claude/projects/service/memory/api-notes.md
codex__memories__prefs.md	~/.codex/memories/prefs.md
```

That manifest is what makes the next command possible.

## agent apply

Push staged edits back, then sync.

```console
$ printf 'Deploys need the VPN.\n' >> /tmp/mem/codex__memories__prefs.md
$ agent apply /tmp/mem
updated store: ~/.codex/memories/prefs.md
1 store file(s) updated from /tmp/mem
codex: folded 2 memory file(s) in
codex: synced -> ~/.codex/AGENTS.md
gemini: synced -> ~/.gemini/GEMINI.md
```

One edit travels three hops: into the agent's own store, into the memory
file, then out to every agent. It reported one update from several staged
files because it compares checksums and writes only what changed.

Removal propagates the same way: delete the line, apply, and it leaves
every copy.

Before writing, `apply` validates every manifest entry against the
supported memory-store paths and rejects path traversal and symlinked
staged files, because the manifest is plain text you could hand-edit into
pointing anywhere.

## agent link

Project scope. One repository file, readable by every agent.

```console
$ agent link .
link: seeded AGENTS.md from the existing CLAUDE.md
link: CLAUDE.md now imports AGENTS.md (content was identical)
link: created .gemini/settings.json so Gemini CLI reads AGENTS.md
link: note: .clinerules shadows AGENTS.md in Zed (first-match order)
link: done; AGENTS.md is the single project instructions file
```

Four tools, four different needs:

| Tool | Need | What link did |
| --- | --- | --- |
| Codex, Cursor, Copilot, Zed, Amp, OpenCode, Junie, Goose | Read `AGENTS.md` natively | Seeded it, nothing else |
| Claude Code | Reads `CLAUDE.md` only | Wrote the documented `@AGENTS.md` import stub |
| Gemini CLI | Ignores `AGENTS.md` by default | Set `context.fileName` in `.gemini/settings.json` |
| Zed | First match across nine filenames | Warned that `.clinerules` shadows `AGENTS.md` |

That warning is the kind of thing worth automating: Zed reads the first
matching file, so a stray `.clinerules` silently wins over instructions
you carefully wrote.

If `CLAUDE.md` had contained Claude-specific content rather than being
identical, it would have been left alone with a note instead.

## agent link --import

Migrate a repository whose instructions are scattered across per-tool
files.

```console
$ agent link . --import
link: imported 2 native config file(s) into AGENTS.md
```

```markdown
<!-- agent-sync:begin imported:project -->
## Imported project agent configs

### .cursor/rules/validation.mdc

---
globs: ["*.ts"]
---
Use zod for all request validation.

### .clinerules

Run make test before every commit.

<!-- agent-sync:end imported:project -->
```

Verbatim, frontmatter intact. Re-running is byte-identical, and editing a
source file refreshes the section in place. Your original files are never
touched, so those tools keep working; delete them on your own schedule.

This is one-way: the managed section belongs to the tool, the curated part
above it belongs to you.

## agent mcp

Register an MCP server once, push it everywhere.

```console
$ agent mcp add fetch --env API_KEY=secret -- uvx mcp-server-fetch --strict
mcp: registered fetch (stdio); run: agent mcp sync

$ agent mcp add linear --url https://mcp.linear.app/sse --header 'Authorization: Bearer tok'
mcp: registered linear (http); run: agent mcp sync

$ agent mcp list
fetch: stdio uvx
linear: http https://mcp.linear.app/sse
```

```console
$ agent mcp sync
claude: fetch configured
claude: linear configured
codex: fetch configured
codex: note: the codex CLI takes no custom headers; header(s) omitted for linear
mcp: ~/.cursor/mcp.json exists and is not agent-sync managed; add servers there yourself
mcp: wrote ~/.codeium/windsurf/mcp_config.json
kiro: linear skipped (kiro's user MCP file is documented for stdio servers only)
note: zed, opencode, goose and continue keep MCP in shared config files;
agent-sync will not edit those. See: agent mcp snippet NAME
```

One registration, several native formats:

| Tool | How | Format |
| --- | --- | --- |
| Claude Code, Codex, Gemini, Qwen, Amp | Their own CLI | Codex is TOML, the rest JSON |
| Cursor, Windsurf, Kiro | agent-sync writes the file | Windsurf uses `serverUrl`, not `url` |
| Zed, OpenCode, Goose, Continue | Printed snippet | OpenCode needs `command` as an array and `environment`, not `env` |

Those differences are the reason to automate this. Getting one wrong
produces a config that silently does nothing.

Three refusals in that output, all deliberate: a pre-existing Cursor
config is never rewritten because agent-sync did not create it, Kiro takes
only the stdio server because its user-level file is documented for stdio,
and Codex drops the header loudly rather than shipping broken auth.

### agent mcp snippet

For tools whose MCP settings live in shared files agent-sync will not
edit:

```console
$ agent mcp snippet fetch
# zed (~/.config/zed/settings.json)
"context_servers": { "fetch": {"type": "stdio", "command": "uvx", "args": ["mcp-server-fetch", "--strict"]} }

# opencode (~/.config/opencode/opencode.json)
"mcp": { "fetch": { "type": "local", "command": ["uvx", "mcp-server-fetch", "--strict"] } }

# goose (~/.config/goose/config.yaml)
extensions:
  fetch:
    enabled: true
    type: stdio
    cmd: uvx
    args:
      - mcp-server-fetch
```

### Removal

```console
$ agent mcp remove fetch
mcp: fetch removed from the registry; next mcp sync removes agent-sync-managed copies.

$ agent mcp sync
claude: fetch removed
codex: fetch removed
mcp: wrote ~/.codeium/windsurf/mcp_config.json
```

CLI-managed tools have it removed through their own CLI; owned files are
rewritten without it. Files agent-sync never owned stay untouched
throughout, including any servers you added yourself.

## agent skills sync

Mirror your canonical skills into every agent's skills directory.

```console
$ agent skills sync
skills: skipping remotion-docs (symbolic link in source)
codex: 12 skill(s) -> ~/.codex/skills
gemini: 12 skill(s) -> ~/.gemini/skills
cursor: 12 skill(s) -> ~/.cursor/skills
zed: 12 skill(s) -> ~/.agents/skills
source: ~/.claude/skills (12 skill(s); 1 skipped as symbolic links)
```

Symlinked source skills are skipped rather than copied, since a symlink
can resolve anywhere, but they do not block the rest: plugin-installed
skills are routinely symlinks into a shared directory.

Propagation is additive. A skill that exists only in one agent stays, and
a same-named skill agent-sync did not create is reported as a collision
and left alone rather than overwritten.

## agent pack

Shareable memory packs from any GitHub repository, pinned to a commit.

```console
$ agent pack add acme/team-conventions
pack acme-team-conventions: 3 file(s) pinned at acme/team-conventions@a1b2c3d4e5f6
run: agent sync (folds the pack into the synthesized file)

$ agent pack list
acme-team-conventions: acme/team-conventions@HEAD (pinned a1b2c3d4e5f6)
```

After `agent sync` the pack appears in the memory file under its own
managed section, so it reaches every agent. `agent pack update` re-pins,
and `agent pack remove` deletes the content and its section.

Packs are untrusted input: a subdirectory that resolves outside the
downloaded repository is refused, markdown symlinks are never followed,
and a refetch that yields no markdown keeps the existing content rather
than destroying it.

## agent hooks

Verified automation snippets, printed rather than installed.

```console
$ agent hooks claude
# Claude Code (~/.claude/settings.json): sync when the session ends
{
  "hooks": {
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "agent sync --synthesizer deterministic" } ] }
    ]
  }
}
```

`agent hooks` alone prints every tool. Codex uses `Stop` rather than
`SessionEnd` because its `SessionEnd` timeout is too short for a sync, and
OpenCode gets a plugin because it has no JSON hook format. Settings files
belong to you, so nothing is written.

## agent revert

Undo adoption.

```console
$ agent revert
zed: restored ~/.config/zed/AGENTS.md from its .orig backup
synthesized file restored from ~/.claude/CLAUDE.md.bak
```

The first time sync would overwrite a pre-existing file it did not write,
it keeps the original as `<file>.orig`. `revert` puts them back and
restores the memory file from the backup that semantic synthesis leaves.

## Filtering and dry runs

Every destructive command can be scoped or previewed:

```console
$ agent sync --dry-run
dry-run: would refresh section imported:codex in ~/.claude/CLAUDE.md
codex: would sync -> ~/.codex/AGENTS.md

$ agent sync --only codex,cursor
$ agent sync --skip qwen
$ AGENT_SYNC_ONLY=codex agent status
```

`--only` and `--skip` work on `sync` and `apply`; the environment
variables additionally apply to `status`, `diff`, `skills sync` and
`mcp sync`.

## Environment

| Variable | Effect |
| --- | --- |
| `AGENT_SYNC_SOURCE` | Where the synthesized memory file lives |
| `AGENT_SYNC_HOME` | Agent configuration root, used by the test suite for isolation |
| `AGENT_SYNC_SYNTHESIZER` | `auto`, `claude`, `codex`, `deterministic`, or a custom command |
| `AGENT_SYNC_SKILLS_SOURCE` | Canonical skills directory |
| `AGENT_SYNC_ONLY` / `AGENT_SYNC_SKIP` | Comma-separated target filters |
