#!/bin/sh
# Colour behaviour: additive on a terminal, invisible everywhere else.
# The contract these assertions defend is that colour changes bytes on a
# terminal and nothing else -- not piped output, not exit codes, and above
# all not a single byte of any file agent-sync writes.
set -eu
. "$(dirname "$0")/lib.sh"

ESC=$(printf '\033')

strip_ansi() {
  sed "s/${ESC}\[[0-9;]*m//g" "$1"
}

assert_has_color() {
  grep -q "$ESC\[" "$1" || fail "$2: expected ANSI escapes in $1"
}

assert_no_color() {
  ! grep -q "$ESC\[" "$1" || fail "$2: unexpected ANSI escapes in $1"
}

# Every regular file below a root, ESC-scanned. This is the guard that keeps
# colour out of generated content: markdown, JSON and staged memory stores
# are written with the same echo statements that print status lines.
assert_tree_clean() {
  root="$1"
  label="$2"
  found=$(find "$root" -type f -exec grep -l "$ESC\[" {} + 2>/dev/null || true)
  [ -z "$found" ] || fail "$label: ANSI escapes written into files: $found"
}

seed_skill

# -- 1. no terminal, no colour ------------------------------------------------
# TERM carries a real terminal name here on purpose: with the environment
# otherwise colour-capable, the absence of a terminal on stdout is the only
# thing left keeping these runs plain, which is exactly what is under test.

run_agent_term() {
  TMPDIR="$TEST_TMPDIR" \
    NO_COLOR= FORCE_COLOR= CLICOLOR_FORCE= TERM=xterm-256color \
    AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
    AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER=deterministic \
    "$AGENT_BIN" "$@"
}

run_agent_term sync >"$TEST_ROOT/plain-sync.out" 2>&1
assert_no_color "$TEST_ROOT/plain-sync.out" 'piped sync'
assert_contains "$TEST_ROOT/plain-sync.out" 'codex: synced -> '

run_agent_term status >"$TEST_ROOT/plain-status.out" 2>&1
assert_no_color "$TEST_ROOT/plain-status.out" 'piped status'
run_agent_term targets >"$TEST_ROOT/plain-targets.out" 2>&1
assert_no_color "$TEST_ROOT/plain-targets.out" 'piped targets'
run_agent_term doctor >"$TEST_ROOT/plain-doctor.out" 2>&1
assert_no_color "$TEST_ROOT/plain-doctor.out" 'piped doctor'

# -- 2. forced colour paints the status vocabulary ----------------------------

run_agent_forced_color sync >"$TEST_ROOT/color-sync.out" 2>&1
assert_has_color "$TEST_ROOT/color-sync.out" 'forced sync'
assert_contains "$TEST_ROOT/color-sync.out" "codex: ${ESC}[32msynced${ESC}[0m"
assert_contains "$TEST_ROOT/color-sync.out" "${ESC}[35msynthesis: deterministic merge${ESC}[0m"

# STALE is the one token that has to survive a glance across a full screen,
# so it is bold as well as yellow.
printf 'drifted\n' >"$AGENT_CONFIG_ROOT/.codex/AGENTS.md"
if run_agent_forced_color status >"$TEST_ROOT/color-status.out" 2>&1; then
  fail 'status exited 0 with a stale target'
fi
assert_contains "$TEST_ROOT/color-status.out" "${ESC}[1m${ESC}[33mSTALE${ESC}[0m"

# -- 3. colour is purely additive ---------------------------------------------
# Strip the escapes back out and the bytes must match the piped run exactly.
# This is what stops a colourised branch from quietly rewriting content: the
# diff body goes through a read loop when colour is on and through a bare
# `diff -u` when it is off, and those two have to agree.

run_agent status >"$TEST_ROOT/plain-stale.out" 2>&1 || true
run_agent_forced_color status >"$TEST_ROOT/color-stale.out" 2>&1 || true
strip_ansi "$TEST_ROOT/color-stale.out" >"$TEST_ROOT/stripped-stale.out"
cmp -s "$TEST_ROOT/plain-stale.out" "$TEST_ROOT/stripped-stale.out" ||
  fail 'colour changed the text payload of status'

# Drift built from the expected file so the diff carries real context lines
# (which arrive space-prefixed and hit the filter's default branch), plus the
# shapes most likely to be mangled: a leading dash, a tab, no final newline.
cp "$CANON" "$AGENT_CONFIG_ROOT/.codex/AGENTS.md"
printf -- '-leading dash\n\ttabbed\nno trailing newline' \
  >>"$AGENT_CONFIG_ROOT/.codex/AGENTS.md"
run_agent diff >"$TEST_ROOT/plain-diff.out" 2>&1 || true
run_agent_forced_color diff >"$TEST_ROOT/color-diff.out" 2>&1 || true
strip_ansi "$TEST_ROOT/color-diff.out" >"$TEST_ROOT/stripped-diff.out"
cmp -s "$TEST_ROOT/plain-diff.out" "$TEST_ROOT/stripped-diff.out" ||
  fail 'colour changed the text payload of diff'
assert_contains "$TEST_ROOT/plain-diff.out" 'No newline at end of file'

# -- 4. exit codes are untouched ----------------------------------------------

printf 'drifted again\n' >"$AGENT_CONFIG_ROOT/.codex/AGENTS.md"
if run_agent_forced_color status >/dev/null 2>&1; then
  fail 'forced colour lost the stale exit code from status'
fi
if run_agent_forced_color diff >"$TEST_ROOT/color-diff-stale.out" 2>&1; then
  fail 'forced colour lost the stale exit code from diff'
fi
# A unified diff body is colourised by a read loop rather than printed raw;
# both markers must still be there, and wearing the right hue.
assert_contains "$TEST_ROOT/color-diff-stale.out" "${ESC}[31m-drifted again"
assert_contains "$TEST_ROOT/color-diff-stale.out" "${ESC}[32m+# Canon"
run_agent sync >/dev/null 2>&1
run_agent_forced_color diff >/dev/null 2>&1 ||
  fail 'forced colour broke the in-sync exit code from diff'

# -- 5. the escapes never reach a file ----------------------------------------

COLOR_GATHER="$TEST_ROOT/color-gather"
COLOR_PROJECT="$TEST_ROOT/color-project"
mkdir -p "$COLOR_PROJECT"
run_agent_forced_color sync >/dev/null 2>&1
run_agent_forced_color gather "$COLOR_GATHER" >/dev/null 2>&1
run_agent_forced_color apply "$COLOR_GATHER" >/dev/null 2>&1
run_agent_forced_color link "$COLOR_PROJECT" >/dev/null 2>&1
run_agent_forced_color skills sync >/dev/null 2>&1
# MCP writes JSON that a tool has to parse, so it is the least forgiving
# destination for a stray escape.
run_agent_forced_color mcp add file-probe -- /bin/echo hi >/dev/null 2>&1
run_agent_forced_color mcp sync >/dev/null 2>&1
assert_tree_clean "$AGENT_CONFIG_ROOT" 'forced colour'
assert_tree_clean "$COLOR_GATHER" 'forced colour'
assert_tree_clean "$COLOR_PROJECT" 'forced colour'
assert_no_color "$CANON" 'forced colour'

# -- 6. every off switch works ------------------------------------------------

TMPDIR="$TEST_TMPDIR" NO_COLOR=1 FORCE_COLOR= CLICOLOR_FORCE= TERM=xterm-256color \
  AGENT_SYNC_ACTIVE=0 AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
  AGENT_SYNC_SOURCE="$CANON" AGENT_SYNC_SYNTHESIZER=deterministic \
  "$AGENT_BIN" targets >"$TEST_ROOT/no-color.out" 2>&1
assert_no_color "$TEST_ROOT/no-color.out" 'NO_COLOR'

TMPDIR="$TEST_TMPDIR" NO_COLOR= FORCE_COLOR=0 CLICOLOR_FORCE= TERM=xterm-256color \
  AGENT_SYNC_ACTIVE=0 AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
  AGENT_SYNC_SOURCE="$CANON" AGENT_SYNC_SYNTHESIZER=deterministic \
  "$AGENT_BIN" targets >"$TEST_ROOT/force-zero.out" 2>&1
assert_no_color "$TEST_ROOT/force-zero.out" 'FORCE_COLOR=0'

run_agent_forced_color --no-color targets >"$TEST_ROOT/flag-off.out" 2>&1
assert_no_color "$TEST_ROOT/flag-off.out" '--no-color over FORCE_COLOR'
run_agent_forced_color --color=never targets >"$TEST_ROOT/flag-never.out" 2>&1
assert_no_color "$TEST_ROOT/flag-never.out" '--color=never'

# --color=always is what makes colour usable through a pager or `tee`.
run_agent --color=always targets >"$TEST_ROOT/flag-on.out" 2>&1
assert_has_color "$TEST_ROOT/flag-on.out" '--color=always over a pipe'
run_agent --color targets >"$TEST_ROOT/flag-bare.out" 2>&1
assert_has_color "$TEST_ROOT/flag-bare.out" 'bare --color'

# FORCE_COLOR is the documented override for a NO_COLOR environment.
TMPDIR="$TEST_TMPDIR" NO_COLOR=1 FORCE_COLOR=1 CLICOLOR_FORCE= TERM=xterm-256color \
  AGENT_SYNC_ACTIVE=0 AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
  AGENT_SYNC_SOURCE="$CANON" AGENT_SYNC_SYNTHESIZER=deterministic \
  "$AGENT_BIN" targets >"$TEST_ROOT/force-over-no.out" 2>&1
assert_has_color "$TEST_ROOT/force-over-no.out" 'FORCE_COLOR over NO_COLOR'

if run_agent --color=technicolor targets >"$TEST_ROOT/bad-mode.out" 2>&1; then
  fail 'an unknown colour mode was accepted'
fi
assert_contains "$TEST_ROOT/bad-mode.out" 'unknown colour mode: technicolor'

# -- 7. paste targets stay plain ----------------------------------------------
# Hook recipes and MCP snippets are copied into config files by hand; an
# escape in one of them is a broken config, not a pretty terminal.

run_agent_forced_color hooks claude >"$TEST_ROOT/color-hooks.out" 2>&1
assert_no_color "$TEST_ROOT/color-hooks.out" 'hooks recipe'
run_agent_forced_color mcp add snippet-probe -- /bin/echo hi >/dev/null 2>&1
run_agent_forced_color mcp snippet snippet-probe >"$TEST_ROOT/color-snippet.out" 2>&1
assert_no_color "$TEST_ROOT/color-snippet.out" 'mcp snippet'

# -- 8. a server's own --no-color is the server's ------------------------------
# Colour flags are global only up to a literal `--`; past it the words belong
# to the program agent-sync is registering.

run_agent_forced_color mcp add passthru --  /bin/echo --no-color arg \
  >"$TEST_ROOT/passthru-add.out" 2>&1
assert_has_color "$TEST_ROOT/passthru-add.out" 'flag after -- must not disable colour'
assert_contains "$STATE_DIR/mcp.d/passthru.spec" 'arg=--no-color'

echo 'colour tests passed'
