# agent-sync

Synchronize your AI coding agents' memory, so you can stop in one agent and
pick up in another.

Every coding agent accumulates knowledge about you and your projects: Claude
Code writes memory files, Codex keeps a memory store, Cursor and Continue
collect rules, Windsurf keeps memories. Each lives in its own silo, so
switching agents means starting over. `agent sync` breaks the silos with a
three-stage round trip:

1. **Gather**: read every agent's own memory stores.
2. **Synthesize**: fold them into one synthesized memory file. Mechanically
   by default (each agent's memories land in a marker-delimited section that
   refreshes in place), or semantically when you configure a synthesizer.
3. **Redistribute**: write the result to every installed agent's global
   instructions slot.

After a sync, every agent knows what every agent has learned.

| Verb | What it does |
| --- | --- |
| `agent sync` | The full round trip: gather, synthesize, redistribute |
| `agent status` | Parity check; exit 1 if any agent is stale (cron-friendly) |
| `agent migrate <agent>` | Fold just one agent's stores in, then redistribute |
| `agent gather [dir]` | Stage all stores into a directory for manual review |
| `agent targets` | List targets and detection state |

## Install

With curl (single file, no clone):

```sh
# to /usr/local/bin (may need sudo)
curl -fsSL https://raw.githubusercontent.com/hibeekaey/agent-sync/main/bin/agent \
  -o /usr/local/bin/agent && chmod +x /usr/local/bin/agent

# per-user, no sudo
mkdir -p ~/.local/bin && \
curl -fsSL https://raw.githubusercontent.com/hibeekaey/agent-sync/main/bin/agent \
  -o ~/.local/bin/agent && chmod +x ~/.local/bin/agent
```

From a clone:

```sh
make install                 # /usr/local/bin (may need sudo)
make install PREFIX=~/.local # per-user, no sudo
```

POSIX sh only, no dependencies beyond coreutils. Works on macOS and Linux.

## Supported agents

| Agent | Reads the synced file at | Memory stores gathered from |
| --- | --- | --- |
| Claude Code | `~/.claude/CLAUDE.md` (the synthesized file itself) | `~/.claude/projects/*/memory/*.md` (excluding `MEMORY.md` indexes) |
| Codex CLI | `~/.codex/AGENTS.md` | `~/.codex/memories/*.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` | (steering only) |
| Qwen Code | `~/.qwen/QWEN.md` | (steering only) |
| Continue | `~/.continue/rules/best-practices.md` | `~/.continue/rules/*.md` |
| Windsurf | `~/.codeium/windsurf/memories/global_rules.md` | `~/.codeium/windsurf/memories/*.md` |
| Cursor | `~/.cursor/rules/best-practices.mdc` (generated with frontmatter) | `~/.cursor/rules/*.mdc` |

Tools are detected by their config directory; absent tools are skipped, so
the same binary serves every machine. Files agent-sync generates are never
gathered, so the tool cannot feed on its own output.

## Semantic synthesis

The mechanical merge is deterministic but keeps imported sections raw. For a
real merge (dedupe, conflict resolution, folding into your curated
structure), point `AGENT_SYNC_SYNTHESIZER` at any command that reads a merge
prompt on stdin and prints the merged markdown document on stdout:

```sh
AGENT_SYNC_SYNTHESIZER='claude -p' agent sync
```

The previous file is kept at `<file>.bak`. Output is validated (non-empty,
starts with a heading) and the mechanical merge is kept if the synthesizer
fails. A recursion guard stops a synthesizer-spawned agent from re-entering
agent-sync.

## Automating with Claude Code

A PostToolUse hook keeps everything in sync whenever Claude Code edits the
synthesized file:

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "f=$(jq -r \".tool_input.file_path // empty\"); if [ \"$f\" = \"$HOME/.claude/CLAUDE.md\" ]; then agent sync; fi"
      }]
    }]
  }
}
```

## Coordinating agents on one task

Shared memory makes cross-agent handoffs coherent; the file-mediated
protocol for actually splitting work between two agents (headless
invocation, task directories, mkdir locks, git worktrees) is documented in
[docs/coordination.md](docs/coordination.md), including a verified
Claude Code to Codex round trip.

The same protocol ships as an installable coordinator skill at
[skills/coordinate-agents](skills/coordinate-agents/SKILL.md). Install it
into whichever agent should play coordinator, for example:

```sh
cp -R skills/coordinate-agents ~/.claude/skills/   # Claude Code
cp -R skills/coordinate-agents ~/.codex/skills/    # Codex CLI
```

## Notes

- Memory files can contain private context. Keep the synthesized file and
  anything `gather` produces out of public repositories.
- `AGENT_SYNC_SOURCE` overrides the synthesized file location.
- `agent help` for the full usage text.

## License

MIT
