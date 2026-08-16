#!/bin/sh
set -eu
umask 077

PROJECT_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
AGENT_BIN="$PROJECT_DIR/bin/agent"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-sync-test.XXXXXXXX")
AGENT_CONFIG_ROOT="$TEST_ROOT/config"
CANON="$TEST_ROOT/canon.md"
GATHER_DIR="$TEST_ROOT/gathered"
TEST_TMPDIR="$TEST_ROOT/tmp"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup 0
trap 'exit 1' HUP INT TERM

fail() {
  echo "test failure: $*" >&2
  exit 1
}

assert_contains() {
  file="$1"
  text="$2"
  grep -qF "$text" "$file" || fail "$file does not contain: $text"
}

assert_not_contains() {
  file="$1"
  text="$2"
  if grep -qF "$text" "$file"; then
    fail "$file unexpectedly contains: $text"
  fi
}

run_agent() {
  TMPDIR="$TEST_TMPDIR" \
    AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
    AGENT_SYNC_SOURCE="$CANON" \
    "$AGENT_BIN" "$@"
}

run_agent_with_synthesizer() {
  TMPDIR="$TEST_TMPDIR" \
    AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
    AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER='printf "# Synthesized memory\n"' \
    "$AGENT_BIN" "$@"
}

CLAUDE_A="$AGENT_CONFIG_ROOT/.claude/projects/project-a/memory/shared.md"
CLAUDE_B="$AGENT_CONFIG_ROOT/.claude/projects/project-b/memory/shared.md"
CODEX_MEMORY="$AGENT_CONFIG_ROOT/.codex/memories/project.md"

mkdir -p \
  "$TEST_TMPDIR" \
  "$(dirname "$CLAUDE_A")" \
  "$(dirname "$CLAUDE_B")" \
  "$(dirname "$CODEX_MEMORY")" \
  "$AGENT_CONFIG_ROOT/.gemini" \
  "$AGENT_CONFIG_ROOT/.qwen" \
  "$AGENT_CONFIG_ROOT/.continue/rules" \
  "$AGENT_CONFIG_ROOT/.codeium/windsurf/memories" \
  "$AGENT_CONFIG_ROOT/.cursor/rules"

printf '# Canon\n\nCurated memory.\n' >"$CANON"
printf 'alpha without a final newline' >"$CLAUDE_A"
printf 'bravo\n' >"$CLAUDE_B"
printf 'obsolete codex memory\n' >"$CODEX_MEMORY"

run_agent sync >/dev/null
assert_contains "$CANON" '<!-- agent-sync:begin imported:claude -->'
assert_contains "$CANON" '<!-- agent-sync:end imported:claude -->'
assert_contains "$CANON" '<!-- agent-sync:begin imported:codex -->'
cmp -s "$CANON" "$AGENT_CONFIG_ROOT/.claude/CLAUDE.md" ||
  fail 'a custom source was not redistributed to Claude'
run_agent status >/dev/null

cp "$CANON" "$TEST_ROOT/idempotent.md"
run_agent sync >/dev/null
if ! cmp -s "$CANON" "$TEST_ROOT/idempotent.md"; then
  diff -u "$TEST_ROOT/idempotent.md" "$CANON" >&2 || true
  fail 'sync is not idempotent'
fi

rm -f "$CODEX_MEMORY"
run_agent sync >/dev/null
assert_not_contains "$CANON" '<!-- agent-sync:begin imported:codex -->'
assert_not_contains "$CANON" 'obsolete codex memory'

printf 'fresh codex memory\n' >"$CODEX_MEMORY"
run_agent migrate codex >/dev/null
assert_contains "$CANON" 'fresh codex memory'
rm -f "$CODEX_MEMORY"
run_agent sync >/dev/null

cp "$CANON" "$TEST_ROOT/canon-valid.md"
printf '\n<!-- agent-sync:begin imported:codex -->\nbroken\n' >>"$CANON"
cp "$CANON" "$TEST_ROOT/canon-malformed.md"
if run_agent sync >"$TEST_ROOT/malformed.out" 2>&1; then
  fail 'sync accepted malformed import markers'
fi
cmp -s "$CANON" "$TEST_ROOT/canon-malformed.md" ||
  fail 'sync modified the canon after rejecting malformed markers'
cp "$TEST_ROOT/canon-valid.md" "$CANON"

run_agent gather "$GATHER_DIR" >/dev/null
manifest_count=$(wc -l <"$GATHER_DIR/.agent-manifest" | tr -d ' ')
[ "$manifest_count" -eq 2 ] || fail "expected 2 manifest entries, got $manifest_count"
staged_count=$(find "$GATHER_DIR" -type f ! -name '.agent-manifest' | wc -l | tr -d ' ')
[ "$staged_count" -eq 2 ] || fail "expected 2 collision-safe staged files, got $staged_count"
assert_contains "$GATHER_DIR/.agent-manifest" "$CLAUDE_A"
assert_contains "$GATHER_DIR/.agent-manifest" "$CLAUDE_B"

staged_a=$(awk -F '\t' -v path="$CLAUDE_A" '$2 == path { print $1 }' "$GATHER_DIR/.agent-manifest")
[ -n "$staged_a" ] || fail 'could not find project-a in the gather manifest'
printf 'edited alpha\n' >"$GATHER_DIR/$staged_a"
run_agent apply "$GATHER_DIR" >/dev/null
assert_contains "$CLAUDE_A" 'edited alpha'

printf 'safe\n' >"$TEST_ROOT/outside.md"
printf 'unsafe\n' >"$GATHER_DIR/unsafe.md"
printf 'unsafe.md\t%s\n' "$TEST_ROOT/outside.md" >>"$GATHER_DIR/.agent-manifest"
if run_agent apply "$GATHER_DIR" >"$TEST_ROOT/unsafe.out" 2>&1; then
  fail 'apply accepted a manifest path outside supported memory stores'
fi
assert_contains "$TEST_ROOT/outside.md" 'safe'
assert_not_contains "$TEST_ROOT/outside.md" 'unsafe'

run_agent_with_synthesizer sync >/dev/null
assert_contains "$CANON" '# Synthesized memory'
[ -f "$CANON.bak" ] || fail 'semantic synthesis did not create a backup'
[ -z "$(find "$TEST_TMPDIR" -mindepth 1 -print -quit)" ] ||
  fail 'agent left temporary files behind'
assert_not_contains "$AGENT_BIN" '.tmp.$$'

echo 'behavior tests passed'
