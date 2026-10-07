#!/bin/sh
# Skills propagation: additive updates, unmanaged collisions, and the
# symlink paths that could otherwise destroy canonical skills.
set -eu
. "$(CDPATH= cd "$(dirname "$0")" && pwd)/lib.sh"

run_agent sync >/dev/null

# Additively synchronize the canonical skills into detected agents.
seed_skill
run_agent skills sync >"$TEST_ROOT/skills.out"
assert_contains "$AGENT_CONFIG_ROOT/.codex/skills/test-skill/SKILL.md" 'name: test-skill'
assert_contains "$AGENT_CONFIG_ROOT/.qwen/skills/test-skill/SKILL.md" 'name: test-skill'
assert_contains "$AGENT_CONFIG_ROOT/.agents/skills/test-skill/SKILL.md" 'name: test-skill'
assert_contains "$TEST_ROOT/skills.out" 'roo: 1 skill(s)'

# Managed skills update atomically; unrelated target-only skills remain.
printf -- '---\nname: test-skill\n---\nupdated body\n' >"$AGENT_CONFIG_ROOT/.claude/skills/test-skill/SKILL.md"
mkdir -p "$AGENT_CONFIG_ROOT/.codex/skills/target-only"
printf -- '---\nname: target-only\n---\nlocal\n' >"$AGENT_CONFIG_ROOT/.codex/skills/target-only/SKILL.md"
run_agent skills sync >/dev/null
assert_contains "$AGENT_CONFIG_ROOT/.codex/skills/test-skill/SKILL.md" 'updated body'
assert_contains "$AGENT_CONFIG_ROOT/.codex/skills/target-only/SKILL.md" 'local'

# An unmanaged same-name skill is a reported collision, never overwritten.
mkdir -p "$AGENT_CONFIG_ROOT/.claude/skills/collision" "$AGENT_CONFIG_ROOT/.codex/skills/collision"
printf -- '---\nname: collision\n---\ncanonical\n' >"$AGENT_CONFIG_ROOT/.claude/skills/collision/SKILL.md"
printf -- '---\nname: collision\n---\nkeep local\n' >"$AGENT_CONFIG_ROOT/.codex/skills/collision/SKILL.md"
if (
  AGENT_SYNC_ONLY=codex
  export AGENT_SYNC_ONLY
  run_agent skills sync
) >"$TEST_ROOT/skills-collision.out" 2>&1; then
  fail 'skills sync exited zero for an unmanaged collision'
fi
assert_contains "$AGENT_CONFIG_ROOT/.codex/skills/collision/SKILL.md" 'keep local'
assert_contains "$TEST_ROOT/skills-collision.out" 'collision at'
rm -rf "$AGENT_CONFIG_ROOT/.claude/skills/collision" "$AGENT_CONFIG_ROOT/.codex/skills/collision"

# Symlinked ownership state and source content are rejected before propagation.
mv "$PACK_STATE/skills-owned" "$PACK_STATE/skills-owned.saved"
printf '%s\n' "$AGENT_CONFIG_ROOT/.codex/skills/test-skill" >"$TEST_ROOT/skills-owned-victim"
ln -s "$TEST_ROOT/skills-owned-victim" "$PACK_STATE/skills-owned"
if run_agent skills sync >"$TEST_ROOT/skills-ledger.out" 2>&1; then
  fail 'skills sync accepted a symbolic-link ownership ledger'
fi
assert_contains "$TEST_ROOT/skills-owned-victim" "$AGENT_CONFIG_ROOT/.codex/skills/test-skill"
rm "$PACK_STATE/skills-owned"
mv "$PACK_STATE/skills-owned.saved" "$PACK_STATE/skills-owned"

# A symlinked source skill is never copied, but it must not block the
# others: plugin-installed skills are routinely symlinks into a shared
# skills directory, and failing the whole run made the command unusable.
mkdir -p "$TEST_ROOT/outside-skill"
printf -- '---\nname: linked-skill\n---\nprivate\n' >"$TEST_ROOT/outside-skill/SKILL.md"
ln -s "$TEST_ROOT/outside-skill" "$AGENT_CONFIG_ROOT/.claude/skills/linked-skill"
mkdir -p "$AGENT_CONFIG_ROOT/.claude/skills/plain-skill"
printf -- '---\nname: plain-skill\n---\nreal\n' >"$AGENT_CONFIG_ROOT/.claude/skills/plain-skill/SKILL.md"
(
  AGENT_SYNC_ONLY=codex
  export AGENT_SYNC_ONLY
  run_agent skills sync
) >"$TEST_ROOT/skills-source-symlink.out" 2>&1 ||
  fail 'a symbolic-link source skill blocked the whole run'
[ ! -e "$AGENT_CONFIG_ROOT/.codex/skills/linked-skill" ] ||
  fail 'skills sync propagated a symbolic-link source skill'
assert_contains "$TEST_ROOT/skills-source-symlink.out" 'skipping linked-skill (symbolic link in source)'
assert_contains "$TEST_ROOT/skills-source-symlink.out" '1 skipped as symbolic links'
assert_contains "$AGENT_CONFIG_ROOT/.codex/skills/plain-skill/SKILL.md" 'real'
assert_contains "$AGENT_CONFIG_ROOT/.codex/skills/test-skill/SKILL.md" 'name: test-skill'
rm "$AGENT_CONFIG_ROOT/.claude/skills/linked-skill"
rm -rf "$AGENT_CONFIG_ROOT/.claude/skills/plain-skill"

# skills sync must never delete canonical skills through a symlinked target.
rm -rf "$AGENT_CONFIG_ROOT/.qwen/skills"
ln -s "$AGENT_CONFIG_ROOT/.claude/skills" "$AGENT_CONFIG_ROOT/.qwen/skills"
run_agent skills sync >"$TEST_ROOT/skills-symlink.out" || fail 'skills sync failed with a symlinked target'
assert_contains "$TEST_ROOT/skills-symlink.out" 'qwen: skipped (skills dir resolves to the source)'
[ -f "$AGENT_CONFIG_ROOT/.claude/skills/test-skill/SKILL.md" ] ||
  fail 'skills sync destroyed the canonical skill through a symlink'
rm "$AGENT_CONFIG_ROOT/.qwen/skills"
mkdir -p "$AGENT_CONFIG_ROOT/.qwen/skills"

# A skill rewritten from Claude to Codex is refused by path with a nonzero exit; clean skills still sync.
mkdir -p "$AGENT_CONFIG_ROOT/.claude/skills/damaged-skill/refs" "$AGENT_CONFIG_ROOT/.claude/skills/clean-skill"
printf -- '---\nname: damaged-skill\n---\nbody\n' >"$AGENT_CONFIG_ROOT/.claude/skills/damaged-skill/SKILL.md"
printf 'Run `Codex -p "Read task.md"` from Codex Code\n' >"$AGENT_CONFIG_ROOT/.claude/skills/damaged-skill/refs/usage.md"
printf -- '---\nname: clean-skill\n---\nCodex exec and Claude Code are both fine\n' >"$AGENT_CONFIG_ROOT/.claude/skills/clean-skill/SKILL.md"
mkdir -p "$AGENT_CONFIG_ROOT/.claude/skills/clean-skill/.trash"
printf 'Codex Code\n' >"$AGENT_CONFIG_ROOT/.claude/skills/clean-skill/.trash/old.md"
if run_agent skills sync >"$TEST_ROOT/skills-damage.out" 2>"$TEST_ROOT/skills-damage.err"; then
  fail 'skills sync exited zero with a damaged skill in the source'
fi
[ ! -e "$AGENT_CONFIG_ROOT/.codex/skills/damaged-skill" ] ||
  fail 'skills sync copied a damaged skill'
assert_contains "$AGENT_CONFIG_ROOT/.codex/skills/clean-skill/SKILL.md" 'Codex exec'
assert_contains "$TEST_ROOT/skills-damage.err" "$AGENT_CONFIG_ROOT/.claude/skills/damaged-skill/refs/usage.md"
assert_not_contains "$TEST_ROOT/skills-damage.err" 'clean-skill/.trash'

# status and doctor report the damage as a problem.
if run_agent status >"$TEST_ROOT/skills-damage-status.out" 2>&1; then
  fail 'status exited zero with a damaged skill in the source'
fi
assert_contains "$TEST_ROOT/skills-damage-status.out" 'DAMAGED'
assert_contains "$TEST_ROOT/skills-damage-status.out" "$AGENT_CONFIG_ROOT/.claude/skills/damaged-skill/refs/usage.md"
if run_agent doctor >"$TEST_ROOT/skills-damage-doctor.out" 2>&1; then
  fail 'doctor exited zero with a damaged skill in the source'
fi
assert_contains "$TEST_ROOT/skills-damage-doctor.out" 'rewritten from Claude to Codex'

# Repaired text syncs again and status is clean.
printf 'Run `claude -p "Read task.md"` from Claude Code\n' >"$AGENT_CONFIG_ROOT/.claude/skills/damaged-skill/refs/usage.md"
run_agent skills sync >/dev/null || fail 'skills sync refused a repaired skill'
assert_contains "$AGENT_CONFIG_ROOT/.codex/skills/damaged-skill/refs/usage.md" 'claude -p'
run_agent status >/dev/null || fail 'status failed after the skill was repaired'
rm -rf "$AGENT_CONFIG_ROOT/.claude/skills/damaged-skill" "$AGENT_CONFIG_ROOT/.claude/skills/clean-skill"

echo 'skills tests passed'
