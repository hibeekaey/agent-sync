# Walkthrough

Every command, with real output. Paths and content are from a demo setup,
so substitute your own.

Output here is shown plain, which is what a pipe or a redirect gets. On a
terminal the same lines are coloured: `synced` green, `STALE` bold yellow,
paths cyan, synthesis magenta, failures red. `--no-color` turns that off and
`--color=always` keeps it through a pipe or a pager.

The examples assume five agents installed (Codex, Gemini CLI, Cursor, Goose
and Kiro), three of which have written memories of their own (a Claude Code
project memory, two Codex memory files, one Goose memory), and a memory
file at `~/.claude/CLAUDE.md` reading:

```markdown
# My memory

Always run tests before pushing.
```

## agent sync

The core round trip: gather, synthesize, redistribute. First without a
model, which is what a hook runs:

```console
$ agent sync --synthesizer deterministic
claude: folded 1 memory file(s) in
codex: folded 2 memory file(s) in
goose: folded 1 memory file(s) in
synthesis: deterministic merge
codex: synced -> ~/.codex/AGENTS.md
gemini: synced -> ~/.gemini/GEMINI.md
qwen: skipped (not installed)
...
cursor: synced -> ~/.cursor/rules/best-practices.mdc
...
goose: synced -> ~/.config/goose/.goosehints
...
kiro: synced -> ~/.kiro/steering/agent-sync.md
...
synthesized file: 1552 of 150000 bytes
```

**Gather** read each agent's own memory stores. **Synthesize** folded them
into the memory file. **Redistribute** wrote the result everywhere. Absent
tools are skipped, so the same binary serves every machine. The last line
is the file's size against its budget; `agent compact` below is what keeps
it there.

The file afterwards, with each agent's memories in a managed section:

```markdown
# My memory

Always run tests before pushing.

<!-- agent-sync:begin imported:claude -->
## Memories imported from claude

Raw import, refreshed on every sync. Ask your agent to consolidate
the durable parts into the curated sections and prune duplicates.

### ~/.claude/projects/service/memory/api-notes.md

The staging API is https://api.staging.example.com; export STAGING_TOKEN before the smoke tests.

<!-- agent-sync:end imported:claude -->

<!-- agent-sync:begin imported:codex -->
## Memories imported from codex
...
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

### Folding with a model

Plain `agent sync` hands the new memories to a model. It does not rewrite
the file: the model sees the curated text as read-only context and the
newly imported blocks, and answers with only the sections that change,
which agent-sync splices in.

```console
$ agent sync
claude: folded 1 memory file(s) in
codex: folded 2 memory file(s) in
goose: folded 1 memory file(s) in
synthesis: stops after 1200s (AGENT_SYNC_SYNTH_TIMEOUT)
synthesis via claude (fable, effort low): folding 3 new import block(s); the answer is only the sections that change, so this is quick
synthesized via: claude (fable) (previous file at ~/.claude/CLAUDE.md.bak)
codex: pre-existing file preserved at ~/.codex/AGENTS.md.orig
codex: synced -> ~/.codex/AGENTS.md
...
synthesized file: 293 of 150000 bytes
```

Ten seconds on this file. On a terminal a dot lands on stderr every 30
seconds while the model runs, and a model still running after 1200 seconds
is stopped so the next one can try. The file afterwards: the three raw
blocks are gone, what they said lives in curated sections, and the URL and
the variable name survived verbatim.

```markdown
# My memory

Always run tests before pushing.

## Promoted from claude

- Staging API: `https://api.staging.example.com`; export `STAGING_TOKEN` before the smoke tests.

## Promoted from codex

- User prefers tables over prose.

## Promoted from goose

- Prefer bun over npm in every project.
```

A memory that fits an existing `##` section is folded into it; one that
fits nowhere goes under `## Promoted from <agent>`. The answer is refused,
and the next model tried, when it is not sections, echoes an import block,
repeats a heading, shrinks a section past 70% (a fold adds) or drops a
URL, hostname, environment variable or long id the document carries; a
model that dropped one is first retried once, told exactly what it lost.

The script decides the model, so a sync behaves the same on every machine:
Claude tries `fable`, then `opus`, then `sonnet` at low effort, then Codex
tries its own ladder, and the deterministic merge already in place is the
last resort. Each hand-over is one line naming the model, the elapsed time
and the vendor's own reason. `--claude-model`, `--claude-effort`,
`--codex-model` and `--codex-effort` change that for one run.

### A sync with nothing new

```console
$ agent sync
claude: folded 1 memory file(s) in
codex: folded 2 memory file(s) in
goose: folded 1 memory file(s) in
synthesis: nothing new to fold (3 import block(s) were folded before and their stores still exist)
removed: 3 import block(s) folded earlier (previous file at ~/.claude/CLAUDE.md.bak)
codex: synced -> ~/.codex/AGENTS.md
...
synthesized file: 293 of 150000 bytes
```

No model was called: each re-imported block had the same fingerprint as
the one folded before and every identifier it carried was still in the
curated text, so the blocks were dropped again and the file is byte for
byte what it was. Delete a fact from the curated text by hand and its
block comes back for folding on the next sync. `agent sync --rewrite` asks
for a rewrite of the whole document instead, which is the tool for a
deliberate tidy and takes minutes.

One sync writes at a time: a second run started while another holds
`~/.config/agent-sync/sync.lock` exits 1 naming the holder's pid.

## agent status

Parity check, built for cron.

```console
$ agent status
codex: synced
gemini: synced
qwen: not installed
...
kiro: synced
...
synthesized file: 1552 of 150000 bytes
$ echo $?
0
```

With drift:

```console
$ agent status
codex: synced
gemini: STALE
...
synthesized file: 1552 of 150000 bytes
1 target(s) stale; run: agent sync
$ echo $?
1
```

The exit code is the feature, and it also goes to 1 while the file is over
its budget:

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
@@ -1 +1,46 @@
-hand-edited junk
+# My memory
...
1 stale target(s); run: agent sync
$ echo $?
1
```

Minus is what the agent has, plus is what the memory file says it should
have. Clean setups print `all targets in sync` and exit 0, so this works
as a CI gate.

The sync that heals it keeps the hand-edited file:

```console
$ agent sync --synthesizer deterministic
...
gemini: pre-existing file preserved at ~/.gemini/GEMINI.md.orig
gemini: synced -> ~/.gemini/GEMINI.md
...
```

## agent doctor

Diagnosis without changes.

```console
$ agent doctor
agent v1.10.1
synthesized file: ~/.claude/CLAUDE.md
ok: synthesized file exists (46 lines)
ok: 5 sync target(s) detected (agent targets lists them)
ok: claude CLI available for semantic synthesis
ok: codex CLI available for semantic synthesis
doctor: no problems found
```

A broken setup, exit 1:

```console
$ agent doctor
agent v1.10.1
synthesized file: ~/.claude/CLAUDE.md
ok: synthesized file exists (38 lines)
PROBLEM: malformed import markers for codex in ~/.claude/CLAUDE.md
ok: 5 sync target(s) detected (agent targets lists them)
ok: claude CLI available for semantic synthesis
ok: codex CLI available for semantic synthesis
PROBLEM: targets are stale (agent diff shows details; agent sync fixes)
doctor: 2 problem(s) found
```

Missing model CLIs are a `note`, not a problem, because deterministic
synthesis works without them. The marker check matters most: agent-sync
refuses to modify a file whose managed sections are corrupted, and doctor
tells you before you hit that. A file over its budget is a third kind of
problem, and the fix it names is `agent compact`.

## agent targets

Where memory goes, and what was detected.

```console
$ agent targets
codex: installed (~/.codex/AGENTS.md)
gemini: installed (~/.gemini/GEMINI.md)
qwen: not installed (would be ~/.qwen/QWEN.md)
...
cursor: installed (~/.cursor/rules/best-practices.mdc)
...
goose: installed (~/.config/goose/.goosehints)
...
kiro: installed (~/.kiro/steering/agent-sync.md)
...
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
gathered 4 memory file(s) into /tmp/mem
edit the staged files, then push edits everywhere with: agent apply /tmp/mem
note: gathered files can contain private context; do not commit them

$ ls /tmp/mem
claude__memory__api-notes.md
codex__memories__MEMORY.md
codex__memories__prefs.md
goose__memory__preferences.txt
```

Names encode origin, and collisions get a numeric prefix rather than
overwriting. The `.agent-manifest` maps each staged file back to its
source:

<!-- markdownlint-disable MD010 -->
```console
$ cat /tmp/mem/.agent-manifest
claude__memory__api-notes.md	~/.claude/projects/service/memory/api-notes.md
codex__memories__MEMORY.md	~/.codex/memories/MEMORY.md
codex__memories__prefs.md	~/.codex/memories/prefs.md
goose__memory__preferences.txt	~/.config/goose/memory/preferences.txt
```
<!-- markdownlint-enable MD010 -->

That manifest is what makes the next command possible.

## agent apply

Push staged edits back, then sync.

```console
$ printf 'Deploys need the VPN.\n' >> /tmp/mem/codex__memories__prefs.md
$ agent apply /tmp/mem
updated store: ~/.codex/memories/prefs.md
1 store file(s) updated from /tmp/mem
claude: folded 1 memory file(s) in
codex: folded 2 memory file(s) in
goose: folded 1 memory file(s) in
synthesis: 2 import block(s) folded before will be dropped with the fold
synthesis: stops after 1200s (AGENT_SYNC_SYNTH_TIMEOUT)
synthesis via claude (fable, effort low): folding 1 new import block(s); the answer is only the sections that change, so this is quick
synthesized via: claude (fable) (previous file at ~/.claude/CLAUDE.md.bak)
codex: synced -> ~/.codex/AGENTS.md
gemini: synced -> ~/.gemini/GEMINI.md
...
synthesized file: 317 of 150000 bytes
```

One edit travels three hops: into the agent's own store, into the memory
file, then out to every agent. It reported one update from four staged
files because it compares checksums and writes only what changed, and the
fold that followed had one new block to work on: the other two were folded
before and were dropped unasked. Nine seconds, and the section reads:

```markdown
## Promoted from codex

- User prefers tables over prose.
- Deploys need the VPN.
...
```

Removal propagates the same way: delete the line, apply, and it leaves
every copy.

Before writing, `apply` validates every manifest entry against the
supported memory-store paths and rejects path traversal and symlinked
staged files, because the manifest is plain text you could hand-edit into
pointing anywhere.

## agent compact

The synthesized file is read into every session on every tool, so its size
is paid on every turn. A budget (150 KB by default) keeps that in check:
`sync` reports the size after every run, `status` and `doctor` fail while
the file is over it, and a sync whose model synthesis leaves the file over
budget trims it back in the same run. `compact` does the trim by hand.
Within budget it exits at once, so it is cheap to schedule:

```console
$ agent compact
compact: 1552 of 150000 bytes, within budget; nothing to do (--force compacts anyway)
```

The rest of this section uses a fuller memory file (three curated sections,
4.6 KB) and a deliberately small budget. The plan costs no model call:

```console
$ agent compact --dry-run --budget 3500
compact: 4615 bytes, budget 3500, goal 3325; trimming the largest sections first, 2 of them, via claude (mode: stable, jobs: 4)
dry-run: would rewrite "## Deploy runbook" (2254 bytes) to about 1578
dry-run: would rewrite "## Billing service notes" (2163 bytes) to about 1549
dry-run: no model was called and nothing was written
```

Largest first: the two big sections are asked for a cut and the small
`## Working style` section is left alone. Only sections of 2 KB or more are
candidates, and the goal sits 5% under the budget so the next import fits.

```console
$ agent compact --budget 3500
compact: 4615 bytes, budget 3500, goal 3325; trimming the largest sections first, 2 of them, via claude (mode: stable, jobs: 4)
## Deploy runbook: 2254 -> 1639 bytes
## Billing service notes: 2163 -> 1789 bytes
codex: synced -> ~/.codex/AGENTS.md
gemini: synced -> ~/.gemini/GEMINI.md
...
compact: 4615 -> 3627 bytes (previous file at ~/.claude/CLAUDE.md.bak)
still 127 bytes over the 3500-byte budget; run agent compact again
$ echo $?
1
```

Both sections were rewritten at once, four at a time being the default,
in 18 seconds. A rewrite is accepted only if it starts with the same
heading, is smaller, is at least a quarter of the original and still
contains every URL, hostname, environment variable and long id the
original had; all sixteen in this file survived. A rewrite that lands
within 25% over its target is accepted rather than re-asked, which is why
this pass stopped 127 bytes short and said so with exit 1.

What a rewrite keeps and what it may forget, from the runbook:

```markdown
## Deploy runbook

Billing API deploys from GitHub Actions on every merge to `main` via `.github/workflows/deploy.yml`: builds the image, pushes to `europe-west1-docker.pkg.dev/acme-prod/billing/api`, rolls Cloud Run service `billing-api-7f3e9a2c1b` in `europe-west1` (~6 min). Deploys are frozen on the last two business days of each quarter (invoicing) — enforced by branch protection.

- **Migrations**: dry-run first against the replica. `DATABASE_URL` = `db-replica.internal.example.com` for dry run, `db-primary.internal.example.com` for real. Never run from a laptop; only the workflow's migration job has write credentials. Follow expand → migrate → contract; PR template asks whether the migration takes a lock (non-nullable column without default locks the table).
- **Secrets**: `DEPLOY_TOKEN` (Doppler project `billing`, config `prd`) and `GCP_WORKLOAD_IDENTITY_PROVIDER` as repository secrets. On rotation: update Doppler first, then re-run the failed job. Never paste the token into the workflow file. `continue-on-error` is forbidden in deploy jobs (masks an expired token).
...
```

The two dated incident stories are gone and the rules they taught survive
as a clause each; the service id, both database hostnames and every URL
stayed.
`--keep-all` forbids forgetting and protects every backtick span and bare
letter-and-digit token as well. Run by hand, `compact` also promotes raw
imported blocks into curated notes and archives their store files to
`~/.config/agent-sync/archive/`, so the next sync has nothing to re-import;
the budget pass inside `sync` never does that.

When the file is over budget, `status` and `doctor` say so and exit 1:

```console
$ AGENT_SYNC_BUDGET=1000 agent status
...
synthesized file is 1343 bytes, over the 1000-byte budget; run: agent compact
$ echo $?
1
```

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
link: CLAUDE.md already imports AGENTS.md
link: Gemini CLI already configured for AGENTS.md
link: note: .clinerules shadows AGENTS.md in Zed (first-match order)
link: imported 2 native config file(s) into AGENTS.md
link: done; AGENTS.md is the single project instructions file
```

```markdown
<!-- agent-sync:begin imported:project -->
## Imported project agent configs

Folded verbatim by agent link --import; re-run it to refresh.

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
      { "hooks": [ { "type": "command", "command": "agent sync --synthesizer deterministic >&2" } ] }
    ]
  }
}
```

`agent hooks` alone prints every tool. Codex uses `Stop` rather than
`SessionEnd` because its `SessionEnd` timeout is too short for a sync, and
OpenCode gets a plugin because it has no JSON hook format. `agent hooks
launchd` prints a macOS LaunchAgent that runs `agent compact` daily at
09:00, which costs a model call only once the file has grown past its
budget. Settings files belong to you, so nothing is written.

## agent revert

Undo the last synthesis and the adoption backups.

```console
$ agent revert
codex: restored ~/.codex/AGENTS.md from its .orig backup
gemini: restored ~/.gemini/GEMINI.md from its .orig backup
cursor: restored ~/.cursor/rules/best-practices.mdc from its .orig backup
goose: restored ~/.config/goose/.goosehints from its .orig backup
kiro: restored ~/.kiro/steering/agent-sync.md from its .orig backup
synthesized file restored from ~/.claude/CLAUDE.md.bak
```

The first time a sync overwrites a target whose content differs from what
it is about to write, it keeps the original beside it as `<file>.orig` and
never replaces that backup. Gemini's is the hand-edited file from the
`diff` example; the other four are the deterministic merge each target
held before the first model fold changed it. `revert` puts every `.orig`
back and restores the memory file from the `.bak` the last synthesis
left.

## Filtering and dry runs

Every destructive command can be scoped or previewed:

```console
$ agent sync --dry-run
dry-run: would refresh section imported:claude in ~/.claude/CLAUDE.md
claude: folded 1 memory file(s) in
dry-run: would refresh section imported:codex in ~/.claude/CLAUDE.md
codex: folded 2 memory file(s) in
dry-run: would refresh section imported:goose in ~/.claude/CLAUDE.md
goose: folded 1 memory file(s) in
dry-run: would synthesize (mode: auto)
codex: would sync -> ~/.codex/AGENTS.md
gemini: would sync -> ~/.gemini/GEMINI.md
...
synthesized file: 46 of 150000 bytes

$ agent sync --only codex,cursor
$ agent sync --skip qwen
$ AGENT_SYNC_ONLY=codex agent status
```

`--only` and `--skip` work on `sync`, `apply` and `compact`; the
environment variables additionally apply to `status`, `diff`, `skills
sync` and `mcp sync`. `agent compact --dry-run` prints the plan without a
model call, as shown above.

## Environment

| Variable | Effect |
| --- | --- |
| `AGENT_SYNC_SOURCE` | Where the synthesized memory file lives |
| `AGENT_SYNC_HOME` | Agent configuration root, used by the test suite for isolation |
| `AGENT_SYNC_SYNTHESIZER` | `auto`, `claude`, `codex`, `deterministic`, or a custom command |
| `AGENT_SYNC_CLAUDE_MODEL` / `AGENT_SYNC_CODEX_MODEL` | Comma-separated model ladder for each vendor |
| `AGENT_SYNC_CLAUDE_EFFORT` / `AGENT_SYNC_CODEX_EFFORT` | Effort level for each vendor |
| `AGENT_SYNC_REWRITE` | `1` asks for a whole-document rewrite instead of a fold |
| `AGENT_SYNC_SYNTH_TIMEOUT` | Seconds before a running model is stopped (default 1200; 0 for none) |
| `AGENT_SYNC_SYNTH_HEARTBEAT` | Seconds between progress dots on a terminal (default 30; 0 for none) |
| `AGENT_SYNC_BUDGET` | Byte budget for the synthesized file (default 150000) |
| `AGENT_SYNC_COMPACT` | `0` skips the budget pass at the end of a sync |
| `AGENT_SYNC_COMPACT_JOBS` | Sections `compact` rewrites concurrently (default 4) |
| `AGENT_SYNC_SKILLS_SOURCE` | Canonical skills directory |
| `AGENT_SYNC_ONLY` / `AGENT_SYNC_SKIP` | Comma-separated target filters |
| `NO_COLOR` / `FORCE_COLOR` | Colour off everywhere, or on through a pipe |
