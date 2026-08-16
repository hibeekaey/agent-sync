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
MOCK_BIN="$TEST_ROOT/mock-bin"
SYNTH_LOG="$TEST_ROOT/synthesizer.log"

# KEEP_TEST_ROOT=1 preserves the fixture for post-mortem debugging.
cleanup() {
  [ -n "${KEEP_TEST_ROOT:-}" ] || rm -rf "$TEST_ROOT"
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
    AGENT_SYNC_SYNTHESIZER=deterministic \
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

run_agent_auto() {
  PATH="$MOCK_BIN:/usr/bin:/bin" \
    TMPDIR="$TEST_TMPDIR" \
    SYNTH_LOG="$SYNTH_LOG" \
    AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
    AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER=auto \
    "$AGENT_BIN" "$@"
}

run_agent_without_models() {
  PATH="/usr/bin:/bin" \
    TMPDIR="$TEST_TMPDIR" \
    AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
    AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER=auto \
    "$AGENT_BIN" "$@"
}

write_claude_mock() {
  result="$1"
  if [ "$result" = "success" ]; then
    printf '%s\n' \
      '#!/bin/sh' \
      '[ "$*" = "-p --no-session-persistence --permission-mode dontAsk" ] || exit 2' \
      'printf "claude\\n" >>"$SYNTH_LOG"' \
      'printf "# Claude synthesized memory\\n"' >"$MOCK_BIN/claude"
  else
    printf '%s\n' \
      '#!/bin/sh' \
      '[ "$*" = "-p --no-session-persistence --permission-mode dontAsk" ] || exit 2' \
      'printf "claude\\n" >>"$SYNTH_LOG"' \
      'exit 1' >"$MOCK_BIN/claude"
  fi
  chmod +x "$MOCK_BIN/claude"
}

write_codex_mock() {
  printf '%s\n' \
    '#!/bin/sh' \
    '[ "$*" = "exec --skip-git-repo-check --sandbox read-only --ephemeral --color never -" ] || exit 2' \
    'printf "codex\\n" >>"$SYNTH_LOG"' \
    'printf "# Codex synthesized memory\\n"' >"$MOCK_BIN/codex"
  chmod +x "$MOCK_BIN/codex"
}

CLAUDE_A="$AGENT_CONFIG_ROOT/.claude/projects/project-a/memory/shared.md"
CLAUDE_B="$AGENT_CONFIG_ROOT/.claude/projects/project-b/memory/shared.md"
CODEX_MEMORY="$AGENT_CONFIG_ROOT/.codex/memories/project.md"

GOOSE_MEMORY="$AGENT_CONFIG_ROOT/.config/goose/memory/project.md"

mkdir -p \
  "$TEST_TMPDIR" \
  "$MOCK_BIN" \
  "$(dirname "$CLAUDE_A")" \
  "$(dirname "$CLAUDE_B")" \
  "$(dirname "$CODEX_MEMORY")" \
  "$(dirname "$GOOSE_MEMORY")" \
  "$AGENT_CONFIG_ROOT/.gemini" \
  "$AGENT_CONFIG_ROOT/.qwen" \
  "$AGENT_CONFIG_ROOT/.continue/rules" \
  "$AGENT_CONFIG_ROOT/.codeium/windsurf/memories" \
  "$AGENT_CONFIG_ROOT/.cursor/rules" \
  "$AGENT_CONFIG_ROOT/.config/opencode" \
  "$AGENT_CONFIG_ROOT/.config/amp" \
  "$AGENT_CONFIG_ROOT/.copilot" \
  "$AGENT_CONFIG_ROOT/.config/zed" \
  "$AGENT_CONFIG_ROOT/.junie" \
  "$AGENT_CONFIG_ROOT/.kiro/steering" \
  "$AGENT_CONFIG_ROOT/.config/crush" \
  "$AGENT_CONFIG_ROOT/.roo/rules" \
  "$AGENT_CONFIG_ROOT/Documents/Cline/Rules"

printf '# Canon\n\nCurated memory.\n' >"$CANON"
printf 'alpha without a final newline' >"$CLAUDE_A"
printf 'bravo\n' >"$CLAUDE_B"
printf 'obsolete codex memory\n' >"$CODEX_MEMORY"

# Adopt safety: a pre-existing user-authored global file must be preserved
# as .orig before the first overwrite, and only once.
printf '# My own zed rules\n' >"$AGENT_CONFIG_ROOT/.config/zed/AGENTS.md"

run_agent sync >/dev/null
assert_contains "$CANON" '<!-- agent-sync:begin imported:claude -->'
assert_contains "$CANON" '<!-- agent-sync:end imported:claude -->'
assert_contains "$CANON" '<!-- agent-sync:begin imported:codex -->'
cmp -s "$CANON" "$AGENT_CONFIG_ROOT/.claude/CLAUDE.md" ||
  fail 'a custom source was not redistributed to Claude'
run_agent status >/dev/null

# New targets received the synced file.
for dest in \
  "$AGENT_CONFIG_ROOT/.config/opencode/AGENTS.md" \
  "$AGENT_CONFIG_ROOT/.config/amp/AGENTS.md" \
  "$AGENT_CONFIG_ROOT/.config/goose/.goosehints" \
  "$AGENT_CONFIG_ROOT/.copilot/copilot-instructions.md" \
  "$AGENT_CONFIG_ROOT/.config/zed/AGENTS.md" \
  "$AGENT_CONFIG_ROOT/.junie/AGENTS.md" \
  "$AGENT_CONFIG_ROOT/.kiro/steering/agent-sync.md" \
  "$AGENT_CONFIG_ROOT/.config/crush/CRUSH.md" \
  "$AGENT_CONFIG_ROOT/.roo/rules/agent-sync.md" \
  "$AGENT_CONFIG_ROOT/Documents/Cline/Rules/agent-sync.md"; do
  cmp -s "$CANON" "$dest" || fail "new target not synced: $dest"
done
assert_contains "$AGENT_CONFIG_ROOT/.config/zed/AGENTS.md.orig" '# My own zed rules'
run_agent sync >/dev/null
assert_contains "$AGENT_CONFIG_ROOT/.config/zed/AGENTS.md.orig" '# My own zed rules'

# revert restores the adopted original (and consumes the .orig).
run_agent revert >/dev/null
assert_contains "$AGENT_CONFIG_ROOT/.config/zed/AGENTS.md" '# My own zed rules'
[ ! -f "$AGENT_CONFIG_ROOT/.config/zed/AGENTS.md.orig" ] ||
  fail 'revert left the .orig behind'
run_agent sync >/dev/null

# Goose memories are gathered into the canon.
printf 'goose remembers the deploy steps\n' >"$GOOSE_MEMORY"
run_agent sync >/dev/null
assert_contains "$CANON" 'goose remembers the deploy steps'
rm -f "$GOOSE_MEMORY"
run_agent sync >/dev/null
assert_not_contains "$CANON" 'goose remembers the deploy steps'

# diff exits 1 on a stale target and 0 when clean.
printf 'stale content\n' >"$AGENT_CONFIG_ROOT/.junie/AGENTS.md"
if run_agent diff >"$TEST_ROOT/diff.out" 2>&1; then
  fail 'diff exited 0 with a stale target'
fi
assert_contains "$TEST_ROOT/diff.out" '.junie/AGENTS.md'
run_agent sync >/dev/null
run_agent diff >/dev/null || fail 'diff exited nonzero when everything is in sync'

# dry-run mutates nothing anywhere.
find "$AGENT_CONFIG_ROOT" -type f ! -name '*.orig' -exec cksum {} + | sort >"$TEST_ROOT/before-dry.sum"
cp "$CANON" "$TEST_ROOT/before-dry-canon.md"
run_agent sync --dry-run >"$TEST_ROOT/dry.out"
assert_contains "$TEST_ROOT/dry.out" 'would sync'
find "$AGENT_CONFIG_ROOT" -type f ! -name '*.orig' -exec cksum {} + | sort >"$TEST_ROOT/after-dry.sum"
cmp -s "$TEST_ROOT/before-dry.sum" "$TEST_ROOT/after-dry.sum" ||
  fail 'dry-run modified target files'
cmp -s "$CANON" "$TEST_ROOT/before-dry-canon.md" || fail 'dry-run modified the canon'

# doctor reports a healthy setup.
run_agent doctor >"$TEST_ROOT/doctor.out" || fail 'doctor found problems in a healthy setup'
assert_contains "$TEST_ROOT/doctor.out" 'no problems found'

# link makes a repo AGENTS.md readable everywhere, idempotently.
LINK_DIR="$TEST_ROOT/repo"
mkdir -p "$LINK_DIR"
printf '# Existing project instructions\n' >"$LINK_DIR/CLAUDE.md"
run_agent link "$LINK_DIR" >/dev/null
assert_contains "$LINK_DIR/AGENTS.md" '# Existing project instructions'
[ "$(head -1 "$LINK_DIR/CLAUDE.md")" = '@AGENTS.md' ] ||
  fail 'link did not bridge CLAUDE.md to AGENTS.md'
assert_contains "$LINK_DIR/.gemini/settings.json" 'AGENTS.md'
run_agent link "$LINK_DIR" >"$TEST_ROOT/link-again.out"
assert_contains "$TEST_ROOT/link-again.out" 'already imports'
printf 'custom claude-only extras\n' >"$LINK_DIR/CLAUDE.md"
run_agent link "$LINK_DIR" >"$TEST_ROOT/link-custom.out"
assert_contains "$LINK_DIR/CLAUDE.md" 'custom claude-only extras'
assert_contains "$TEST_ROOT/link-custom.out" 'left untouched'

# link --import folds native project configs into AGENTS.md, idempotently.
mkdir -p "$LINK_DIR/.cursor/rules"
printf -- '---\nglobs: ["*.ts"]\n---\ncursor scoped rule body\n' >"$LINK_DIR/.cursor/rules/scoped.mdc"
printf 'cline project rule\n' >"$LINK_DIR/.clinerules"
run_agent link "$LINK_DIR" --import >/dev/null
assert_contains "$LINK_DIR/AGENTS.md" '<!-- agent-sync:begin imported:project -->'
assert_contains "$LINK_DIR/AGENTS.md" 'cursor scoped rule body'
assert_contains "$LINK_DIR/AGENTS.md" 'globs: ["*.ts"]'
assert_contains "$LINK_DIR/AGENTS.md" 'cline project rule'
cp "$LINK_DIR/AGENTS.md" "$TEST_ROOT/link-import-once.md"
run_agent link "$LINK_DIR" --import >/dev/null
cmp -s "$LINK_DIR/AGENTS.md" "$TEST_ROOT/link-import-once.md" ||
  fail 'link --import is not idempotent'

# Per-agent targeting: --skip filters a target; AGENT_SYNC_ONLY narrows to one.
# The env assignment lives in a subshell: `VAR=x shell_function` assignments
# persist in POSIX sh and would leak into every later test.
run_agent sync --skip qwen >"$TEST_ROOT/skip.out"
assert_contains "$TEST_ROOT/skip.out" 'qwen: skipped (filtered)'
(
  AGENT_SYNC_ONLY=codex
  export AGENT_SYNC_ONLY
  run_agent sync >"$TEST_ROOT/only.out"
)
assert_contains "$TEST_ROOT/only.out" 'codex: synced'
assert_contains "$TEST_ROOT/only.out" 'gemini: skipped (filtered)'
run_agent sync >/dev/null

# Packs fold into the canon from the lockfile and are fully removable.
PACK_STATE="$AGENT_CONFIG_ROOT/.config/agent-sync"
mkdir -p "$PACK_STATE/packs/testpack"
printf '# Team conventions\n\nAlways write regression tests.\n' >"$PACK_STATE/packs/testpack/conventions.md"
printf 'testpack\towner/repo\tHEAD\tdeadbeefdeadbeef\n' >"$PACK_STATE/packs.lock"
run_agent sync >/dev/null
assert_contains "$CANON" '<!-- agent-sync:begin imported:pack:testpack -->'
assert_contains "$CANON" 'Always write regression tests.'
run_agent pack list >"$TEST_ROOT/pack-list.out"
assert_contains "$TEST_ROOT/pack-list.out" 'testpack: owner/repo@HEAD'
run_agent pack remove testpack >/dev/null
assert_not_contains "$CANON" 'Always write regression tests.'
assert_not_contains "$CANON" 'imported:pack:testpack'
[ ! -d "$PACK_STATE/packs/testpack" ] || fail 'pack remove left the pack directory'
run_agent sync >/dev/null

# MCP: register stdio + remote servers, push via mocked CLIs, write owned files.
printf '%s\n' \
  '#!/bin/sh' \
  'printf "claude %s\\n" "$*" >>"$SYNTH_LOG"' >"$MOCK_BIN/claude"
printf '%s\n' \
  '#!/bin/sh' \
  'printf "codex %s\\n" "$*" >>"$SYNTH_LOG"' >"$MOCK_BIN/codex"
printf '%s\n' \
  '#!/bin/sh' \
  'printf "gemini %s\\n" "$*" >>"$SYNTH_LOG"' >"$MOCK_BIN/gemini"
chmod +x "$MOCK_BIN/claude" "$MOCK_BIN/codex" "$MOCK_BIN/gemini"
run_agent mcp add fetcher --env API_KEY=secret -- uvx mcp-server-fetch --strict >/dev/null
run_agent mcp add linear --url https://mcp.linear.app/sse --header 'Authorization: Bearer tok' >/dev/null
run_agent mcp list >"$TEST_ROOT/mcp-list.out"
assert_contains "$TEST_ROOT/mcp-list.out" 'fetcher: stdio uvx'
assert_contains "$TEST_ROOT/mcp-list.out" 'linear: http https://mcp.linear.app/sse'
: >"$SYNTH_LOG"
PATH="$MOCK_BIN:/usr/bin:/bin" SYNTH_LOG="$SYNTH_LOG" run_agent mcp sync >"$TEST_ROOT/mcp-sync.out"
assert_contains "$SYNTH_LOG" 'claude mcp add-json fetcher'
assert_contains "$SYNTH_LOG" '"env": {"API_KEY": "secret"}'
assert_contains "$SYNTH_LOG" 'codex mcp add fetcher --env API_KEY=secret -- uvx mcp-server-fetch --strict'
assert_contains "$SYNTH_LOG" 'codex mcp add linear --url https://mcp.linear.app/sse'
assert_contains "$SYNTH_LOG" 'gemini mcp add -s user -e API_KEY=secret fetcher uvx mcp-server-fetch --strict'
assert_contains "$SYNTH_LOG" 'gemini mcp add -s user --transport http --header Authorization: Bearer tok linear https://mcp.linear.app/sse'
assert_contains "$AGENT_CONFIG_ROOT/.cursor/mcp.json" '"type": "stdio", "command": "uvx"'
assert_contains "$AGENT_CONFIG_ROOT/.cursor/mcp.json" '"url": "https://mcp.linear.app/sse"'
assert_contains "$AGENT_CONFIG_ROOT/.codeium/windsurf/mcp_config.json" '"serverUrl": "https://mcp.linear.app/sse"'
assert_contains "$AGENT_CONFIG_ROOT/.kiro/settings/mcp.json" '"command": "uvx"'
assert_not_contains "$AGENT_CONFIG_ROOT/.kiro/settings/mcp.json" 'linear'
# A pre-existing non-owned MCP file is never rewritten.
printf '{"mcpServers": {"mine": {"command": "keepme"}}}\n' >"$AGENT_CONFIG_ROOT/.cursor/mcp.json"
rm -f "$PACK_STATE/mcp-owned"
PATH="$MOCK_BIN:/usr/bin:/bin" SYNTH_LOG="$SYNTH_LOG" run_agent mcp sync >"$TEST_ROOT/mcp-sync2.out"
assert_contains "$AGENT_CONFIG_ROOT/.cursor/mcp.json" 'keepme'
assert_contains "$TEST_ROOT/mcp-sync2.out" 'not agent-sync managed'
run_agent mcp remove fetcher >/dev/null
run_agent mcp remove linear >/dev/null
rm -f "$MOCK_BIN/claude" "$MOCK_BIN/codex" "$MOCK_BIN/gemini"

# Skills: mirror the canonical skills dir into every detected agent.
mkdir -p "$AGENT_CONFIG_ROOT/.claude/skills/test-skill"
printf -- '---\nname: test-skill\n---\nbody\n' >"$AGENT_CONFIG_ROOT/.claude/skills/test-skill/SKILL.md"
run_agent skills sync >"$TEST_ROOT/skills.out"
assert_contains "$AGENT_CONFIG_ROOT/.codex/skills/test-skill/SKILL.md" 'name: test-skill'
assert_contains "$AGENT_CONFIG_ROOT/.qwen/skills/test-skill/SKILL.md" 'name: test-skill'
assert_contains "$AGENT_CONFIG_ROOT/.agents/skills/test-skill/SKILL.md" 'name: test-skill'
assert_contains "$TEST_ROOT/skills.out" 'roo: 1 skill(s)'

# Hooks: recipes print and mention the right events.
run_agent hooks >"$TEST_ROOT/hooks.out"
assert_contains "$TEST_ROOT/hooks.out" 'SessionEnd'
assert_contains "$TEST_ROOT/hooks.out" 'session.idle'
run_agent hooks codex >"$TEST_ROOT/hooks-codex.out"
assert_contains "$TEST_ROOT/hooks-codex.out" 'Stop'

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

write_claude_mock success
write_codex_mock
: >"$SYNTH_LOG"
run_agent_auto sync >/dev/null
assert_contains "$CANON" '# Claude synthesized memory'
assert_contains "$SYNTH_LOG" 'claude'
assert_not_contains "$SYNTH_LOG" 'codex'

: >"$SYNTH_LOG"
run_agent_auto sync --synthesizer codex >/dev/null
assert_contains "$CANON" '# Codex synthesized memory'
assert_contains "$SYNTH_LOG" 'codex'
assert_not_contains "$SYNTH_LOG" 'claude'

write_claude_mock failure
: >"$SYNTH_LOG"
run_agent_auto sync >/dev/null 2>&1
assert_contains "$CANON" '# Codex synthesized memory'
assert_contains "$SYNTH_LOG" 'claude'
assert_contains "$SYNTH_LOG" 'codex'

run_agent_without_models sync >/dev/null
assert_contains "$CANON" '<!-- agent-sync:begin imported:claude -->'
cp "$CANON" "$TEST_ROOT/before-invalid-mode.md"
if run_agent sync --synthesizer invalid >"$TEST_ROOT/invalid-mode.out" 2>&1; then
  fail 'sync accepted an invalid synthesizer mode'
fi
cmp -s "$CANON" "$TEST_ROOT/before-invalid-mode.md" ||
  fail 'invalid synthesizer selection modified the canon'

cp "$CANON" "$TEST_ROOT/before-missing-agent.md"
if run_agent_without_models sync --synthesizer claude >"$TEST_ROOT/missing-agent.out" 2>&1; then
  fail 'sync accepted an explicitly selected missing synthesizer'
fi
cmp -s "$CANON" "$TEST_ROOT/before-missing-agent.md" ||
  fail 'missing synthesizer selection modified the canon'

MISSING_APPLY_DIR="$TEST_ROOT/missing-apply"
run_agent gather "$MISSING_APPLY_DIR" >/dev/null
missing_staged=$(awk -F '\t' -v path="$CLAUDE_A" '$2 == path { print $1 }' "$MISSING_APPLY_DIR/.agent-manifest")
printf 'must not be applied\n' >"$MISSING_APPLY_DIR/$missing_staged"
cp "$CLAUDE_A" "$TEST_ROOT/before-missing-apply.md"
if run_agent_without_models apply "$MISSING_APPLY_DIR" --synthesizer claude >"$TEST_ROOT/missing-apply.out" 2>&1; then
  fail 'apply accepted an explicitly selected missing synthesizer'
fi
cmp -s "$CLAUDE_A" "$TEST_ROOT/before-missing-apply.md" ||
  fail 'apply wrote stores before rejecting a missing synthesizer'

run_agent_with_synthesizer sync >/dev/null
assert_contains "$CANON" '# Synthesized memory'
[ -f "$CANON.bak" ] || fail 'semantic synthesis did not create a backup'
[ -z "$(find "$TEST_TMPDIR" -mindepth 1 -print -quit)" ] ||
  fail 'agent left temporary files behind'
assert_not_contains "$AGENT_BIN" '.tmp.$$'

echo 'behavior tests passed'
