agent(1)

# NAME

agent - synchronize agent memory across AI coding agents

# SYNOPSIS

*agent* sync [--synthesizer MODE] [--rewrite] [--dry-run] [--only LIST] [--skip LIST]++
*agent* status++
*agent* diff++
*agent* targets++
*agent* doctor++
*agent* migrate AGENT++
*agent* gather [DIR]++
*agent* apply [DIR] [--synthesizer MODE] [--rewrite] [--dry-run] [--only LIST] [--skip LIST]++
*agent* link [DIR] [--import]++
*agent* revert++
*agent* pack <add|list|update|remove>++
*agent* mcp <add|list|remove|sync|snippet>++
*agent* skills sync++
*agent* hooks [TOOL]

Every command also accepts *--color*[=_WHEN_] and *--no-color*.

# DESCRIPTION

agent keeps every AI coding agent on a machine reading the same synthesized
memory file, so you can stop working in one agent and pick up in another.

*sync* is a round trip: it gathers every agent's own memory stores, folds
them into the synthesized memory file under managed markers, optionally runs
a semantic synthesizer over the result, and redistributes the file to every
installed agent's global instructions slot.

# COMMANDS

*sync*
	Gather, synthesize, redistribute. The model sees the synthesized file
	and the newly imported memories and answers with only the sections that
	change, which agent-sync splices in; a memory block folded on an earlier
	sync is dropped without a model call. *--rewrite* asks for a rewrite of
	the whole file instead. A sync that leaves the file over its byte
	budget trims the largest sections back in the same run (see *compact*;
	never with *deterministic*, never touching an imported block or a store
	file); *--no-compact* or *AGENT_SYNC_COMPACT=0* skips that. The first
	time a pre-existing file agent-sync did not write would be overwritten,
	it is preserved beside the target as <file>.orig.

*compact* [--budget BYTES] [--jobs N] [--synthesizer MODE] [--force] [--keep-all] [--dry-run]
	Keep the synthesized file under a byte budget (default 150000, see
	*AGENT_SYNC_BUDGET*). Exits at once while the file is within budget
	unless *--force*. Otherwise each raw imported section is promoted into
	curated notes under "## Promoted from AGENT" and its store files are
	archived to ~/.config/agent-sync/archive/ and removed, so the next sync
	has nothing to re-import; then curated sections of 2 KB or more are
	rewritten shorter by the model, largest first: each is asked for at
	most a 30% cut until the deficit is covered, and only if that is not
	enough are the same sections asked for more, toward their floors, so a
	small overrun touches one or two large sections and nothing else. A rewrite may
	forget how a lesson was learned, items marked settled, refuted, muted or
	parked, one-off references (commit shas, PR numbers, run ids, past
	versions) and anything else of low value; it is refused, and the section
	kept, unless it starts with the same heading, is at least a quarter of
	the original, and still contains every real URL, hostname, environment
	variable and long id of the original (paths, commands and code words are
	asked for but may go with a story the rewrite forgets). A rewrite that drops one gets a
	second attempt naming what it lost. *--keep-all* forbids forgetting and
	protects every backtick span and bare letter-and-digit token. Sections
	are rewritten *--jobs* at a time (default 4, or *AGENT_SYNC_COMPACT_JOBS*),
	each a model call of a minute or more. Needs a model: *deterministic* is
	rejected. The previous file is kept at <file>.bak. Exits 1 when the file
	is still over budget afterwards.

*status*
	Per-agent parity check. Exits 1 when anything is stale or the
	synthesized file is over its byte budget (cron friendly).

*diff*
	Show stale targets as unified diffs. Exits 1 when anything is stale
	(CI drift gate).

*targets*
	List sync targets and whether each tool is installed.

*doctor*
	Diagnose the setup: file presence, marker integrity, detected agents,
	synthesis availability, staleness.

*migrate* AGENT
	Fold one agent's memory stores in, then redistribute. AGENT is one of
	claude, codex, cursor, continue, windsurf, goose.

*gather* [DIR]
	Stage every agent's memory stores into DIR (default ./agent-memories)
	with a manifest for *apply*.

*apply* [DIR]
	Push edited staged files back to their original stores, then run the
	full sync.

*link* [DIR] [--import]
	Make one project-scope AGENTS.md readable by every agent working in a
	repository: seeds AGENTS.md, bridges CLAUDE.md via an @AGENTS.md
	import, and configures Gemini CLI's context.fileName. With *--import*,
	folds the repository's native per-tool configs (.cursor/rules,
	.cursorrules, .clinerules, .windsurfrules, copilot-instructions,
	.roo/rules, .goosehints) verbatim into AGENTS.md under a managed
	marker.

*revert*
	Restore targets from their .orig adoption backups and the synthesized
	file from its .bak.

*pack* add OWNER/REPO[@REF][:SUBDIR] | list | update [NAME] | remove NAME
	Shareable markdown memory packs pulled from GitHub at a pinned commit,
	recorded in a lockfile, and folded into the synthesized file on every
	sync.

*mcp* <add|list|remove|sync|snippet>
	Add takes NAME [--env K=V]... -- COMMAND [ARGS...] for stdio servers,
	or NAME --url URL with optional --header 'K: V' for remote servers.
	One MCP server registry for every tool. *sync* pushes each server via
	the tool's own CLI (claude, codex, gemini, qwen, amp) or writes an
	agent-sync-owned dedicated config file (cursor, windsurf, kiro).
	Shared config files (zed, opencode, goose, continue) are never edited;
	*snippet* prints what to paste, including configured environment values
	and headers. Successfully applied CLI entries are tracked so updates can
	be validated and rolled back, and registry removals are propagated on the
	next sync. Entries installed before v1.5.2 may need one manual removal.

*skills* sync
	Additively synchronize the canonical skills directory (default
	~/.claude/skills, override with AGENT_SYNC_SKILLS_SOURCE) into every
	agent's user-scope skills directory, per the gh-skill agent registry
	mapping. Target-only skills remain. Unmanaged same-name collisions are
	left untouched and make the command exit nonzero.

*hooks* [TOOL]
	Print verified automation snippets that keep memory fresh: Claude Code
	SessionEnd, Codex Stop, Gemini AfterAgent, an OpenCode plugin, a macOS
	launchd job that runs *compact* daily, and cron fallbacks. Printed,
	never installed.

# OPTIONS

*--color*[=_WHEN_], *--no-color*
	Colour status output. _WHEN_ is *auto* (the default: colour only when
	standard output is a terminal), *always* or *never*; a bare *--color*
	means *always*. The flag is global and may appear anywhere before a
	literal *--*, past which the remaining words belong to the program
	being registered by *mcp add*. Colour is additive: escapes are never
	written to a file, and text, exit codes and piped bytes are identical
	either way.

# ENVIRONMENT

*NO_COLOR*
	Set to any non-empty value to disable colour (see https://no-color.org).

*FORCE_COLOR*, *CLICOLOR_FORCE*
	Set to any non-empty value other than 0 to keep colour on when
	standard output is not a terminal. Both override *NO_COLOR*; an
	explicit *--color* or *--no-color* overrides all three.

*AGENT_SYNC_SOURCE*
	Location of the synthesized memory file
	(default ~/.claude/CLAUDE.md).

*AGENT_SYNC_HOME*
	Agent configuration root (default $HOME). Used by the test suite.

*AGENT_SYNC_SYNTHESIZER*
	Synthesis mode (auto, claude, codex, deterministic) or a custom
	command that reads a merge prompt on stdin and prints the merged
	document on stdout.

*AGENT_SYNC_CLAUDE_MODEL*, *AGENT_SYNC_CLAUDE_EFFORT*
	Claude's model ladder (comma-separated, tried in order; default
	fable,opus,sonnet) and effort (default low) when it synthesizes;
	the *--claude-model* and *--claude-effort* flags override them for
	one run. The script decides the model rather than the CLI's own
	setting so a sync behaves the same on every machine. A model that
	is out of credits, unavailable or answers badly hands over to the
	next; after the last, Codex is tried, then the deterministic merge.

*AGENT_SYNC_CODEX_MODEL*, *AGENT_SYNC_CODEX_EFFORT*
	The same for Codex (default gpt-5.6-terra,gpt-5.5,gpt-5.4 at low),
	passed as *-m* and *-c model_reasoning_effort=*; *--codex-model*
	and *--codex-effort* override them for one run.

*AGENT_SYNC_SYNTH_HEARTBEAT*
	Seconds between progress dots on standard error while a model
	rewrites the file (default 30 when standard error is a terminal,
	otherwise off; 0 turns it off).

*AGENT_SYNC_SYNTH_TIMEOUT*
	Seconds after which a still-running synthesis is stopped and the
	fallback chain continues (default 1200; 0 disables the timeout).
	One sync writes at a time: a run started while another holds
	~/.config/agent-sync/sync.lock exits 1 naming the holder.

*AGENT_SYNC_BUDGET*
	Byte budget for the synthesized file (default 150000). Reported by
	sync, enforced by status and doctor, restored by *compact*; the
	*--budget* flag of *compact* overrides it for one run.

*AGENT_SYNC_COMPACT_JOBS*
	How many sections *compact* rewrites at once (default 4); *--jobs*
	overrides it for one run.

*AGENT_SYNC_ONLY*, *AGENT_SYNC_SKIP*
	Comma-separated target filters used by sync, apply, status, diff, MCP sync
	and skills sync.

# SEE ALSO

Project page: https://github.com/hibeekaey/agent-sync
