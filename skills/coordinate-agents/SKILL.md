---
name: coordinate-agents
description: Coordinate a task across multiple AI coding agents (Claude Code, Codex, Gemini, and others). Use when the user asks to delegate work to another agent, get a second opinion or review from a different agent, run agents in parallel on one task, or split a task between agents. The invoking agent becomes the coordinator; other agents are workers.
---

# Coordinating work across coding agents

You are the **coordinator**: you own the task definition, review every
deliverable, and decide what happens next. Every other agent is a
**worker**: it receives a spec, produces an artifact, and stops. There is no
cross-vendor message bus, so coordination is turn-based and file-mediated:

```
you write task.md -> worker runs headlessly -> worker writes result.md ->
you read, verify, decide the next turn
```

If agent-sync is installed, run `agent sync` before delegating so every
worker starts with the same synthesized memory you have.

## 1. Write the task directory

```
task/
  task.md      # the spec (see contract below)
  ...inputs... # everything the worker needs; workers get no other context
  result.md    # the worker writes this; its existence signals completion
```

`task.md` is a contractor brief and must contain:

- the goal, in one paragraph;
- the exact deliverable (a file, named);
- a checkable definition of done;
- the instruction to stop after writing the deliverable;
- the lock or worktree rules from section 2 when the worker will edit a
  shared tree.

## 2. Choose the sharing mode BEFORE invoking anyone

Rule zero: two agents must never mutate the same working tree at the same
time.

| Situation | Mode |
| --- | --- |
| Worker only reads (review, analysis, second opinion) | Same dir, no lock |
| Alternating edits on one tree | Same dir + mkdir lock |
| Parallel attempts or parallel file-touching subtasks | One git worktree per worker |
| Two agents editing one tree concurrently | Never; restructure |

Same-dir lock (mkdir is atomic; put these instructions in task.md too):

```sh
until mkdir .agent-lock 2>/dev/null; do sleep 1; done   # acquire
echo "$(whoami):$$" > .agent-lock/owner
# ... work ...
rm -rf .agent-lock                                       # release
```

Never auto-expire a lock by age: a slow worker looks identical to a dead
one. Verify the worker process is dead before clearing a stale lock.

Worktree mode: `git worktree add ../task-<worker> -b agent/<worker>` per
worker, workers never push and never touch each other's trees, the main
checkout stays read-only, and you (the coordinator) do all merging as the
one serialized step.

## 3. Invoke the worker headlessly

| Worker | Command |
| --- | --- |
| Claude Code | `claude -p "Read task.md in this directory and complete it."` |
| Codex CLI | `codex exec --skip-git-repo-check --sandbox workspace-write "Read task.md in this directory and complete it." </dev/null` |
| Gemini CLI | `gemini -p "Read task.md in this directory and complete it."` |

Rules that were learned the hard way:

- Run the worker from inside the task directory and scope its write access
  to it.
- Close stdin (`</dev/null`) for any backgrounded worker or it may hang
  waiting for input.
- Codex refuses untrusted non-git directories without
  `--skip-git-repo-check`.

## 4. Verify, then decide

- The worker's word is not the deliverable. Read `result.md` and check it
  against the definition of done; for code, run the tests yourself.
- A missing or wrong deliverable gets a new turn with a sharper spec, not a
  retry of the same one.
- You stay responsible for everything you accept: review a worker's diff as
  you would a human contractor's PR.

## Boundaries

- Never give a worker credentials, deploy rights, or access to real
  audiences; workers produce artifacts, the coordinator (with the user)
  ships them.
- Never run this protocol to parallelize edits inside one tree without
  locks or worktrees, even for "quick" tasks.
- The user decides which agent plays coordinator; do not hand off
  coordination to a worker.
