# Coordinating a task between two agents

`agent sync` gives every agent on the machine the same memory. This document
is the companion protocol: how two separate agents (say Claude Code and
Codex) work the same task without corrupting each other's state.

## The model

One agent is the **coordinator**: it owns the task definition, reviews
deliverables, and decides what happens next. Every other agent is a
**worker**: it receives a spec, produces an artifact, and stops. There is no
cross-vendor message bus, so coordination is turn-based and file-mediated:

```
coordinator writes task.md -> worker runs headlessly -> worker writes
result.md -> coordinator reads, reviews, issues the next task
```

Because all agents read the synced canon, a worker starts with your
practices and project facts already loaded. That is what makes a cross-agent
handoff coherent instead of a cold start.

## Invoking a worker headlessly

| Agent | Command | Notes |
| --- | --- | --- |
| Claude Code | `claude -p "Read task.md in this directory and complete it." ` | Run from the task directory |
| Codex CLI | `codex exec --skip-git-repo-check --sandbox workspace-write "Read task.md in this directory and complete it." </dev/null` | `--skip-git-repo-check` is required outside a git repo; close stdin or a backgrounded run hangs reading it |
| Gemini CLI | `gemini -p "Read task.md in this directory and complete it."` | |

Two hard-won details: always close stdin (`</dev/null`) when running a
worker in the background, and scope the worker's write access to the task
directory (Codex: `--sandbox workspace-write`; Claude: run it from the task
directory and let its permission model do the rest).

## The task directory

```
task/
  task.md      # spec, written by the coordinator: goal, inputs, exact
               # deliverable, definition of done
  ...inputs... # whatever the worker needs
  result.md    # the worker's deliverable; its existence signals completion
```

Write `task.md` the way you would brief a contractor: the deliverable is a
file, the definition of done is checkable, and the worker should stop when
it is written. The coordinator polls for `result.md` (or just waits on the
worker process) and verifies the content before acting on it.

## Rule zero: one writer per tree

Everything below exists to enforce a single rule: two agents must never
mutate the same working tree at the same time. Pick one of two sharing
modes.

### Mode 1: same directory, sequential, with a lock

Use when turns alternate on one tree (coordinator edits, then worker edits).
The lock is a `mkdir`, because `mkdir` is atomic on POSIX filesystems: it
either creates the directory (lock acquired) or fails (someone holds it).

Every agent runs this before touching the tree, and the instruction belongs
in `task.md` so workers actually do it:

```sh
# acquire (blocks until free)
until mkdir .agent-lock 2>/dev/null; do sleep 1; done
echo "$(whoami)@$(hostname):$$ $(date)" > .agent-lock/owner

# ... work ...

# release
rm -rf .agent-lock
```

Conventions that keep locks honest:

- Write an `owner` file inside the lock so a human can see who holds it.
- A crashed agent leaves a stale lock; a human (or the coordinator, after
  verifying the worker process is dead) clears it. Never auto-expire locks
  by timestamp: a slow worker looks identical to a dead one.
- Add `.agent-lock/` to `.gitignore`.

### Mode 2: git worktrees, parallel, no shared mutable state

Use when workers should run concurrently. Each worker gets its own worktree
on its own branch, so trees are disjoint and no locking is needed while
work happens; integration is ordinary git merging done by the coordinator.

```sh
# coordinator: one worktree per worker
git worktree add ../task-codex  -b agent/codex-attempt
git worktree add ../task-claude -b agent/claude-attempt

# workers run in parallel, one per worktree
(cd ../task-codex  && codex exec --skip-git-repo-check --sandbox workspace-write "Read task.md and complete it." </dev/null) &
(cd ../task-claude && claude -p "Read task.md and complete it.") &
wait

# coordinator: review both branches, merge the winner (or the union)
git diff main..agent/codex-attempt
git merge --no-ff agent/codex-attempt
git worktree remove ../task-codex && git branch -d agent/codex-attempt
```

Worktree rules:

- The main checkout is read-only while worktrees exist; only the
  coordinator merges into it, and merging is the one serialized step.
- Workers never touch each other's worktrees and never push; branches are
  the deliverable.
- Dependency dirs (`node_modules`, `.venv`) do not travel with worktrees;
  symlink them from the main checkout or install per worktree.

### Choosing a mode

| Situation | Mode |
| --- | --- |
| Review, second opinion, or analysis (worker only reads) | Same dir, no lock needed for read-only work |
| Alternating edits on one tree | Same dir + mkdir lock |
| Parallel attempts or parallel subtasks that touch files | Worktrees |
| Two agents editing one tree concurrently | Never; restructure into one of the above |

## A verified example

This exact round trip was run while writing this document. Coordinator:
Claude Code. Worker: Codex CLI 0.147.0.

1. Claude wrote `task.md` (sum the second column of `numbers.csv`, write
   `total:` and `count:` lines to `result.md`) and the input file.
2. Claude ran
   `codex exec --skip-git-repo-check --sandbox workspace-write "Read task.md in this directory and complete it exactly as specified." </dev/null`.
3. Codex wrote `result.md` with the correct totals and stopped.
4. Claude read `result.md`, verified it against the expected values, and
   accepted the deliverable.

The first attempt failed in an instructive way: Codex refused the untrusted
non-git directory and then blocked reading stdin. Both fixes are baked into
the invocation table above.
