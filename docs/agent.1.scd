agent(1)

# NAME

agent - synchronize agent memory across AI coding agents

# SYNOPSIS

*agent* sync [--synthesizer MODE] [--dry-run]++
*agent* status++
*agent* diff++
*agent* targets++
*agent* doctor++
*agent* migrate AGENT++
*agent* gather [DIR]++
*agent* apply [DIR] [--synthesizer MODE] [--dry-run]++
*agent* link [DIR]++
*agent* revert

# DESCRIPTION

agent keeps every AI coding agent on a machine reading the same synthesized
memory file, so you can stop working in one agent and pick up in another.

*sync* is a round trip: it gathers every agent's own memory stores, folds
them into the synthesized memory file under managed markers, optionally runs
a semantic synthesizer over the result, and redistributes the file to every
installed agent's global instructions slot.

# COMMANDS

*sync*
	Gather, synthesize, redistribute. The first time a pre-existing file
	agent-sync did not write would be overwritten, it is preserved beside
	the target as <file>.orig.

*status*
	Per-agent parity check. Exits 1 when anything is stale (cron friendly).

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

*link* [DIR]
	Make one project-scope AGENTS.md readable by every agent working in a
	repository: seeds AGENTS.md, bridges CLAUDE.md via an @AGENTS.md
	import, and configures Gemini CLI's context.fileName.

*revert*
	Restore targets from their .orig adoption backups and the synthesized
	file from its .bak.

# ENVIRONMENT

*AGENT_SYNC_SOURCE*
	Location of the synthesized memory file
	(default ~/.claude/CLAUDE.md).

*AGENT_SYNC_HOME*
	Agent configuration root (default $HOME). Used by the test suite.

*AGENT_SYNC_SYNTHESIZER*
	Synthesis mode (auto, claude, codex, deterministic) or a custom
	command that reads a merge prompt on stdin and prints the merged
	document on stdout.

# SEE ALSO

Project page: https://github.com/hibeekaey/agent-sync
