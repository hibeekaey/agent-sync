# agent-sync

Synchronize your AI coding agents' memory, so you can stop in one agent and
pick up in another.

Every coding agent accumulates knowledge about you and your projects: Claude
Code writes memory files, Codex keeps a memory store, Cursor and Continue
collect rules, Windsurf keeps memories. Each lives in its own silo, so
switching agents means starting over. `agent` fixes that with one canonical
memory file and three verbs:

| Verb | What it does |
| --- | --- |
| `agent sync` | Distributes the canonical file to every installed agent's global instructions slot |
| `agent migrate <agent>` | Imports an agent's own memory stores into the canonical file (under managed markers), then syncs, so every other agent picks them up |
| `agent gather [dir]` | Stages every agent's memory stores into a directory for a manual consolidation pass |

The canonical file is the interchange format because a markdown steering file
is the one memory surface every agent can read. Native proprietary stores
(sqlite databases, cloud memories) cannot be written portably, so knowledge
flows one way: out of each agent's store, into the canon, out to everyone.

## Supported agents

| Agent | Reads the synced canon at | Memory stores `migrate`/`gather` read |
| --- | --- | --- |
| Claude Code | `~/.claude/CLAUDE.md` (the canon itself) | `~/.claude/projects/*/memory/*.md` |
| Codex CLI | `~/.codex/AGENTS.md` | `~/.codex/memories/*.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` | (steering only) |
| Qwen Code | `~/.qwen/QWEN.md` | (steering only) |
| Continue | `~/.continue/rules/best-practices.md` | `~/.continue/rules/*.md` |
| Windsurf | `~/.codeium/windsurf/memories/global_rules.md` | `~/.codeium/windsurf/memories/*.md` |
| Cursor | `~/.cursor/rules/best-practices.mdc` (generated with frontmatter) | `~/.cursor/rules/*.mdc` |

Tools are detected by their config directory. Absent tools are skipped, so
the same binary serves every machine.

## Install

```sh
make install                 # /usr/local/bin (may need sudo)
make install PREFIX=~/.local # per-user, no sudo
```

POSIX sh only, no dependencies beyond coreutils. Works on macOS and Linux.

## Workflow

1. Keep one canonical memory file at `~/.claude/CLAUDE.md` (or point
   `AGENT_SYNC_SOURCE` anywhere). Put your durable preferences, practices,
   and project facts there.
2. `agent sync` after editing it. `agent status` is a parity check that
   exits 1 when anything is stale (cron-friendly).
3. When another agent has learned something worth keeping, `agent migrate
   codex` (or `cursor`, `windsurf`, ...) pulls its stores into a
   marker-delimited section of the canon and re-syncs. Re-running a migrate
   refreshes the section instead of duplicating it. Then ask your agent to
   consolidate the imported block into the curated sections and prune it.

## Automating with Claude Code

A PostToolUse hook keeps everything in sync whenever Claude Code edits the
canon:

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

## Notes

- Memory files can contain private context. Keep the canon and anything
  `gather` produces out of public repositories.
- `agent help` for the full usage text.

## License

MIT
