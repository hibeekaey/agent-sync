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

mkdir -p "$TEST_ROOT/outside-skill"
printf -- '---\nname: linked-skill\n---\nprivate\n' >"$TEST_ROOT/outside-skill/SKILL.md"
ln -s "$TEST_ROOT/outside-skill" "$AGENT_CONFIG_ROOT/.claude/skills/linked-skill"
if (
  AGENT_SYNC_ONLY=codex
  export AGENT_SYNC_ONLY
  run_agent skills sync
) >"$TEST_ROOT/skills-source-symlink.out" 2>&1; then
  fail 'skills sync accepted a symbolic-link source skill'
fi
[ ! -e "$AGENT_CONFIG_ROOT/.codex/skills/linked-skill" ] ||
  fail 'skills sync propagated a symbolic-link source skill'
assert_contains "$TEST_ROOT/skills-source-symlink.out" 'refusing symbolic links in source skill'
rm "$AGENT_CONFIG_ROOT/.claude/skills/linked-skill"

# skills sync must never delete canonical skills through a symlinked target.
rm -rf "$AGENT_CONFIG_ROOT/.qwen/skills"
ln -s "$AGENT_CONFIG_ROOT/.claude/skills" "$AGENT_CONFIG_ROOT/.qwen/skills"
run_agent skills sync >"$TEST_ROOT/skills-symlink.out" || fail 'skills sync failed with a symlinked target'
assert_contains "$TEST_ROOT/skills-symlink.out" 'qwen: skipped (skills dir resolves to the source)'
[ -f "$AGENT_CONFIG_ROOT/.claude/skills/test-skill/SKILL.md" ] ||
  fail 'skills sync destroyed the canonical skill through a symlink'
rm "$AGENT_CONFIG_ROOT/.qwen/skills"
mkdir -p "$AGENT_CONFIG_ROOT/.qwen/skills"

echo 'skills tests passed'
