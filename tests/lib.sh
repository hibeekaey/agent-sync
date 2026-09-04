# shellcheck shell=sh
# shellcheck disable=SC2034,SC2016  # vars are consumed by the suites; the
# single quotes are deliberate: mock bodies must not expand when written
# Shared harness for the behavioral suites. Sourcing this builds a fresh
# isolated fixture: AGENT_SYNC_HOME points at a throwaway agent-config root
# and AGENT_SYNC_SOURCE at a throwaway canon, so no suite can read or mutate
# the real configuration. Each suite gets its own fixture and its own
# cleanup trap.
umask 077

PROJECT_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
# AGENT_BIN may point a suite at another build, e.g. the previous release, to
# prove a new assertion fails without the change it guards.
AGENT_BIN="${AGENT_BIN:-$PROJECT_DIR/bin/agent}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-sync-test.XXXXXXXX")
AGENT_CONFIG_ROOT="$TEST_ROOT/config"
CANON="$TEST_ROOT/canon.md"
GATHER_DIR="$TEST_ROOT/gathered"
TEST_TMPDIR="$TEST_ROOT/tmp"
MOCK_BIN="$TEST_ROOT/mock-bin"
SYNTH_LOG="$TEST_ROOT/synthesizer.log"
STATE_DIR="$AGENT_CONFIG_ROOT/.config/agent-sync"
PACK_STATE="$STATE_DIR"

# Every runner below is pinned to this PATH. AGENT_SYNC_HOME isolates the
# files agent-sync writes itself, but `mcp sync` delegates to whichever
# vendor CLI it finds, and a real `claude` or `codex` on the ambient PATH
# writes to the developer's actual configuration, not the fixture. MOCK_BIN
# is empty until a suite calls write_mcp_cli_mocks, so the default state is
# "no vendor CLI exists" -- the only state in which a suite cannot escape.
SAFE_PATH="$MOCK_BIN:/usr/bin:/bin"

CLAUDE_A="$AGENT_CONFIG_ROOT/.claude/projects/project-a/memory/shared.md"
CLAUDE_B="$AGENT_CONFIG_ROOT/.claude/projects/project-b/memory/shared.md"
CODEX_MEMORY="$AGENT_CONFIG_ROOT/.codex/memories/project.md"
GOOSE_MEMORY="$AGENT_CONFIG_ROOT/.config/goose/memory/project.md"

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
  grep -qF -- "$text" "$file" || fail "$file does not contain: $text"
}

assert_not_contains() {
  file="$1"
  text="$2"
  if grep -qF -- "$text" "$file"; then
    fail "$file unexpectedly contains: $text"
  fi
}

run_agent() {
  PATH="$SAFE_PATH" \
    TMPDIR="$TEST_TMPDIR" \
    NO_COLOR= FORCE_COLOR= CLICOLOR_FORCE= \
    AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
    AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER=deterministic \
    "$AGENT_BIN" "$@"
}

run_agent_with_synthesizer() {
  PATH="$SAFE_PATH" \
    TMPDIR="$TEST_TMPDIR" \
    NO_COLOR= FORCE_COLOR= CLICOLOR_FORCE= \
    AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
    AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER='printf "# Synthesized memory\n"; awk "f{print} /^--- DOCUMENT ---/{f=1}"' \
    "$AGENT_BIN" "$@"
}

run_agent_auto() {
  PATH="$SAFE_PATH" \
    TMPDIR="$TEST_TMPDIR" \
    SYNTH_LOG="$SYNTH_LOG" \
    NO_COLOR= FORCE_COLOR= CLICOLOR_FORCE= \
    AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
    AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER=auto \
    "$AGENT_BIN" "$@"
}

# The suites never own a terminal, so colour has to be forced to be observed
# at all. Everything else about the run is identical to run_agent.
run_agent_forced_color() {
  PATH="$SAFE_PATH" \
    TMPDIR="$TEST_TMPDIR" \
    NO_COLOR= CLICOLOR_FORCE= FORCE_COLOR=1 \
    TERM=xterm-256color \
    AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
    AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER=deterministic \
    "$AGENT_BIN" "$@"
}

# Deliberately narrower than SAFE_PATH: MOCK_BIN is excluded so that even a
# suite that has written mocks sees no synthesizer at all.
run_agent_without_models() {
  PATH="/usr/bin:/bin" \
    TMPDIR="$TEST_TMPDIR" \
    NO_COLOR= FORCE_COLOR= CLICOLOR_FORCE= \
    AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
    AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER=auto \
    "$AGENT_BIN" "$@"
}

# The exact command line agent-sync hands each vendor for the first rung of
# its default ladder. The mocks refuse anything else (exit 2), so a flag
# added or dropped in bin/agent fails the suite; they read the expectation
# from a sidecar file because the JSON in --mcp-config does not survive being
# quoted inside a quoted mock body.
CLAUDE_SYNTH_ARGV='-p --no-session-persistence --permission-mode dontAsk --strict-mcp-config --mcp-config {"mcpServers":{}} --model fable --effort low'
CODEX_SYNTH_ARGV='exec --skip-git-repo-check --sandbox read-only --ephemeral --color never -c mcp_servers={} -m gpt-5.6-terra -c model_reasoning_effort=low -'

write_claude_mock() {
  result="$1"
  printf '%s\n' "$CLAUDE_SYNTH_ARGV" >"$MOCK_BIN/claude.argv"
  if [ "$result" = "success" ]; then
    printf '%s\n' \
      '#!/bin/sh' \
      '[ "$*" = "$(cat "$0.argv")" ] || exit 2' \
      'printf "claude\\n" >>"$SYNTH_LOG"' \
      'printf "# Claude synthesized memory\\n"' \
      'awk "f{print} /^--- DOCUMENT ---/{f=1}"' >"$MOCK_BIN/claude"
  else
    printf '%s\n' \
      '#!/bin/sh' \
      '[ "$*" = "$(cat "$0.argv")" ] || exit 2' \
      'printf "claude\\n" >>"$SYNTH_LOG"' \
      'exit 1' >"$MOCK_BIN/claude"
  fi
  chmod +x "$MOCK_BIN/claude"
}

write_codex_mock() {
  printf '%s\n' "$CODEX_SYNTH_ARGV" >"$MOCK_BIN/codex.argv"
  printf '%s\n' \
    '#!/bin/sh' \
    '[ "$*" = "$(cat "$0.argv")" ] || exit 2' \
    'printf "codex\\n" >>"$SYNTH_LOG"' \
    'printf "# Codex synthesized memory\\n"' \
    'awk "f{print} /^--- DOCUMENT ---/{f=1}"' >"$MOCK_BIN/codex"
  chmod +x "$MOCK_BIN/codex"
}

# Every agent directory the targets table knows about, so detection covers
# the full matrix rather than whichever tools happen to exist locally.
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

# A skill in the canonical location, for suites that exercise propagation.
seed_skill() {
  mkdir -p "$AGENT_CONFIG_ROOT/.claude/skills/test-skill"
  printf -- '---\nname: test-skill\n---\nbody\n' \
    >"$AGENT_CONFIG_ROOT/.claude/skills/test-skill/SKILL.md"
}

# Mocked vendor CLIs that log their argv, for suites that exercise MCP push.
write_mcp_cli_mocks() {
  for tool in claude codex gemini; do
    printf '%s\n' \
      '#!/bin/sh' \
      "printf \"$tool %s\\\\n\" \"\$*\" >>\"\$SYNTH_LOG\"" >"$MOCK_BIN/$tool"
    chmod +x "$MOCK_BIN/$tool"
  done
}

remove_mcp_cli_mocks() {
  rm -f "$MOCK_BIN/claude" "$MOCK_BIN/codex" "$MOCK_BIN/gemini"
}
