#!/bin/sh
# shellcheck disable=SC2016,SC2030,SC2031  # mock bodies must not expand when
# written; the ( export ...; run ) groups are deliberate so each knob applies
# to one run only
# The synthesis run itself: the keep rules reach the prompt, model and effort
# knobs reach the vendor, a silent run beats, a stuck run is stopped, one run
# writes at a time, and a file edited mid-run is kept rather than overwritten.
set -eu
. "$(dirname "$0")/lib.sh"

run_synth_fixture() {
  PATH="$SAFE_PATH" TMPDIR="$TEST_TMPDIR" AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER="sh $TEST_ROOT/$1" "$AGENT_BIN" sync
}

# The keep rules are part of the prompt, not a literal "$(compact_keep_rules)"
# left unexpanded inside a quoted heredoc, and the run announces itself.
cat >"$TEST_ROOT/synth-log-prompt.sh" <<FIXTURE
cat >"$TEST_ROOT/prompt.log"
printf '# Logged memory\n'
awk 'f { print } /^--- DOCUMENT ---\$/ { f = 1 }' "$TEST_ROOT/prompt.log"
FIXTURE
run_synth_fixture synth-log-prompt.sh >"$TEST_ROOT/log-prompt.out"
assert_contains "$CANON" '# Logged memory'
assert_contains "$TEST_ROOT/prompt.log" 'Keep every CURRENT rule'
assert_contains "$TEST_ROOT/prompt.log" 'Print ONLY the new markdown document.'
assert_not_contains "$TEST_ROOT/prompt.log" 'compact_keep_rules'
assert_contains "$TEST_ROOT/log-prompt.out" 'synthesis via custom'
assert_contains "$TEST_ROOT/log-prompt.out" 'whole-document rewrite'
assert_contains "$TEST_ROOT/log-prompt.out" 'stops after 1200s'

# The script decides the model. With nothing set, each vendor gets the first
# rung of the script's ladder at the script's effort; a flag or environment
# variable replaces it, flag over environment; a flag without a value is an
# error. The argv-logging mocks accept any model so the ladder can be seen.
printf '%s\n' \
  '#!/bin/sh' \
  'printf "claude %s\n" "$*" >>"$SYNTH_LOG"' \
  'printf "# Claude synthesized memory\n"' \
  'awk "f{print} /^--- DOCUMENT ---/{f=1}"' >"$MOCK_BIN/claude"
printf '%s\n' \
  '#!/bin/sh' \
  'printf "codex %s\n" "$*" >>"$SYNTH_LOG"' \
  'printf "# Codex synthesized memory\n"' \
  'awk "f{print} /^--- DOCUMENT ---/{f=1}"' >"$MOCK_BIN/codex"
chmod +x "$MOCK_BIN/claude" "$MOCK_BIN/codex"
: >"$SYNTH_LOG"
run_agent_auto sync >"$TEST_ROOT/defaults.out"
argv=$(grep '^claude' "$SYNTH_LOG")
[ "$argv" = "claude $CLAUDE_SYNTH_ARGV" ] || fail "default claude argv: $argv"
assert_contains "$TEST_ROOT/defaults.out" 'synthesis via claude (fable, effort low)'
assert_contains "$TEST_ROOT/defaults.out" 'synthesized via: claude (fable)'
: >"$SYNTH_LOG"
run_agent_auto sync --synthesizer codex >/dev/null
argv=$(grep '^codex' "$SYNTH_LOG")
[ "$argv" = "codex $CODEX_SYNTH_ARGV" ] || fail "default codex argv: $argv"

: >"$SYNTH_LOG"
run_agent_auto sync --claude-model sonnet --claude-effort medium >/dev/null
assert_contains "$SYNTH_LOG" '--model sonnet --effort medium'
: >"$SYNTH_LOG"
run_agent_auto sync --synthesizer codex --codex-model=gpt-5.5 --codex-effort=high >/dev/null
assert_contains "$SYNTH_LOG" '-m gpt-5.5 -c model_reasoning_effort=high -'
: >"$SYNTH_LOG"
(
  export AGENT_SYNC_CLAUDE_MODEL=opus AGENT_SYNC_CLAUDE_EFFORT=high
  run_agent_auto sync >/dev/null
)
assert_contains "$SYNTH_LOG" '--model opus --effort high'
: >"$SYNTH_LOG"
(
  export AGENT_SYNC_CLAUDE_MODEL=opus
  run_agent_auto sync --claude-model sonnet >/dev/null
)
assert_contains "$SYNTH_LOG" '--model sonnet --effort low'
assert_not_contains "$SYNTH_LOG" '--model opus'
: >"$SYNTH_LOG"
(
  export AGENT_SYNC_CODEX_MODEL=gpt-5.4 AGENT_SYNC_CODEX_EFFORT=medium
  run_agent_auto sync --synthesizer codex >/dev/null
)
assert_contains "$SYNTH_LOG" '-m gpt-5.4 -c model_reasoning_effort=medium -'
if run_agent sync --claude-model >"$TEST_ROOT/no-value.out" 2>&1; then
  fail 'a model flag without a value was accepted'
fi
assert_contains "$TEST_ROOT/no-value.out" '--claude-model requires a value'

# The ladder. A rung that is out of credits fails in seconds and the next rung
# runs; the reason is one plain line; a whole vendor failing hands over to the
# next vendor; a flag can set the ladder itself.
cat >"$MOCK_BIN/claude" <<'MOCK'
#!/bin/sh
printf 'claude %s\n' "$*" >>"$SYNTH_LOG"
case "$*" in
  *"--model fable "*)
    echo 'Your workspace is out of credits. Ask your workspace owner to refill in order to continue.' >&2
    exit 1
    ;;
  *"--model sonnet "*)
    echo 'unknown model: sonnet' >&2
    exit 1
    ;;
esac
printf '# Opus synthesized memory\n'
awk 'f { print } /^--- DOCUMENT ---$/ { f = 1 }'
MOCK
chmod +x "$MOCK_BIN/claude"
: >"$SYNTH_LOG"
run_agent_auto sync >"$TEST_ROOT/ladder.out" 2>"$TEST_ROOT/ladder.err"
assert_contains "$CANON" '# Opus synthesized memory'
[ "$(grep -c '^claude' "$SYNTH_LOG")" -eq 2 ] || fail "ladder tried $(grep -c '^claude' "$SYNTH_LOG") claude rungs, expected fable then opus"
grep -n 'model fable' "$SYNTH_LOG" | grep -q '^1:' || fail 'fable was not the first rung'
grep -n 'model opus' "$SYNTH_LOG" | grep -q '^2:' || fail 'opus was not the second rung'
assert_contains "$TEST_ROOT/ladder.err" 'claude fable did not produce a usable document'
assert_contains "$TEST_ROOT/ladder.err" 'out of credits'
assert_contains "$TEST_ROOT/ladder.err" 'trying the next model'
assert_not_contains "$TEST_ROOT/ladder.err" 'rmcp'
assert_contains "$TEST_ROOT/ladder.out" 'synthesis via claude (opus, effort low)'
assert_contains "$TEST_ROOT/ladder.out" 'synthesized via: claude (opus)'

: >"$SYNTH_LOG"
run_agent_auto sync --claude-model sonnet,opus >"$TEST_ROOT/ladder-flag.out" 2>"$TEST_ROOT/ladder-flag.err"
grep -n 'model sonnet' "$SYNTH_LOG" | grep -q '^1:' || fail 'a flagged ladder did not start with its first model'
grep -n 'model opus' "$SYNTH_LOG" | grep -q '^2:' || fail 'a flagged ladder did not continue to its second model'
assert_not_contains "$SYNTH_LOG" 'model fable'
assert_contains "$TEST_ROOT/ladder-flag.err" 'unknown model: sonnet'

cat >"$MOCK_BIN/claude" <<'MOCK'
#!/bin/sh
printf 'claude %s\n' "$*" >>"$SYNTH_LOG"
echo 'Your workspace is out of credits.' >&2
exit 1
MOCK
chmod +x "$MOCK_BIN/claude"
: >"$SYNTH_LOG"
run_agent_auto sync >"$TEST_ROOT/exhausted.out" 2>"$TEST_ROOT/exhausted.err"
assert_contains "$CANON" '# Codex synthesized memory'
[ "$(grep -c '^claude' "$SYNTH_LOG")" -eq 3 ] || fail 'every claude rung should have been tried before codex'
assert_contains "$SYNTH_LOG" 'codex exec'
assert_contains "$TEST_ROOT/exhausted.err" 'every claude model failed; trying the next fallback'
assert_contains "$TEST_ROOT/exhausted.out" 'synthesized via: codex (gpt-5.6-terra)'
rm -f "$MOCK_BIN/claude" "$MOCK_BIN/codex"

# The heartbeat: a dot per interval on stderr while the model runs, nothing
# when it is off (the default away from a terminal, which is where the suite
# runs).
cat >"$TEST_ROOT/synth-slow.sh" <<'FIXTURE'
sleep 3
printf '# Slow memory\n'
awk 'f { print } /^--- DOCUMENT ---$/ { f = 1 }'
FIXTURE
(
  export AGENT_SYNC_SYNTH_HEARTBEAT=1
  run_synth_fixture synth-slow.sh >"$TEST_ROOT/beat.out" 2>"$TEST_ROOT/beat.err"
)
assert_contains "$CANON" '# Slow memory'
grep -q '\.\.' "$TEST_ROOT/beat.err" ||
  fail "no heartbeat reached stderr: $(cat "$TEST_ROOT/beat.err")"
assert_contains "$TEST_ROOT/beat.out" 'a dot every 1s'
run_synth_fixture synth-slow.sh >/dev/null 2>"$TEST_ROOT/quiet.err"
[ ! -s "$TEST_ROOT/quiet.err" ] ||
  fail "stderr was not silent with the heartbeat off: $(cat "$TEST_ROOT/quiet.err")"

# The timeout: a model still running when it expires is stopped, the failure
# takes the normal fallback path, nothing of the late answer lands, and the
# private temporary directory is still cleaned up.
cat >"$TEST_ROOT/synth-stuck.sh" <<'FIXTURE'
sleep 30
printf '# Late memory\n'
awk 'f { print } /^--- DOCUMENT ---$/ { f = 1 }'
FIXTURE
started=$(date +%s)
(
  export AGENT_SYNC_SYNTH_TIMEOUT=1
  run_synth_fixture synth-stuck.sh >"$TEST_ROOT/stuck.out" 2>"$TEST_ROOT/stuck.err"
)
elapsed=$(($(date +%s) - started))
[ "$elapsed" -lt 15 ] || fail "the timeout did not stop the synthesizer: ${elapsed}s"
assert_contains "$TEST_ROOT/stuck.err" 'ran past 1s and was stopped'
assert_contains "$TEST_ROOT/stuck.err" 'keeping the deterministic merge'
assert_not_contains "$CANON" '# Late memory'
assert_contains "$CANON" '<!-- agent-sync:begin imported:claude -->'
[ -z "$(find "$TEST_TMPDIR" -mindepth 1 -print -quit)" ] ||
  fail 'a stopped synthesis left temporary files behind'
(
  export AGENT_SYNC_SYNTH_TIMEOUT=0
  run_synth_fixture synth-slow.sh >"$TEST_ROOT/no-timeout.out"
)
assert_contains "$CANON" '# Slow memory'
assert_contains "$TEST_ROOT/no-timeout.out" 'no timeout'
cp "$CANON" "$TEST_ROOT/before-bad-timeout.md"
if (
  export AGENT_SYNC_SYNTH_TIMEOUT=soon
  run_synth_fixture synth-slow.sh >/dev/null 2>"$TEST_ROOT/bad-timeout.err"
); then
  fail 'a non-numeric timeout was accepted'
fi
assert_contains "$TEST_ROOT/bad-timeout.err" 'AGENT_SYNC_SYNTH_TIMEOUT must be a whole number of seconds'
cmp -s "$CANON" "$TEST_ROOT/before-bad-timeout.md" ||
  fail 'a rejected timeout value still modified the canon'

# One writer at a time. A sync started while another holds the lock is refused
# before it touches anything; a dry run is not; the lock leaves with its
# holder; a lock left by a dead pid or holding garbage is reclaimed.
cat >"$TEST_ROOT/synth-hold.sh" <<'FIXTURE'
sleep 4
printf '# Held memory\n'
awk 'f { print } /^--- DOCUMENT ---$/ { f = 1 }'
FIXTURE
run_synth_fixture synth-hold.sh >"$TEST_ROOT/hold.out" 2>&1 &
hold_pid=$!
sleep 1
[ -f "$STATE_DIR/sync.lock" ] || fail 'a running sync did not take the lock'
cp "$CANON" "$TEST_ROOT/before-second.md"
if run_agent sync >"$TEST_ROOT/second.out" 2>&1; then
  fail 'a second sync ran while the first held the lock'
fi
assert_contains "$TEST_ROOT/second.out" 'is already syncing'
cmp -s "$CANON" "$TEST_ROOT/before-second.md" ||
  fail 'the refused sync modified the canon'
run_agent sync --dry-run >"$TEST_ROOT/dry-under-lock.out" 2>&1 ||
  fail "a dry run was refused under the lock: $(cat "$TEST_ROOT/dry-under-lock.out")"
wait "$hold_pid" || fail "the lock-holding sync failed: $(cat "$TEST_ROOT/hold.out")"
assert_contains "$CANON" '# Held memory'
[ ! -e "$STATE_DIR/sync.lock" ] || fail 'the lock outlived its sync'

sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" || true
printf '%s\n' "$dead_pid" >"$STATE_DIR/sync.lock"
run_agent sync >"$TEST_ROOT/stale.out" 2>&1
assert_contains "$TEST_ROOT/stale.out" "reclaiming a lock left by pid $dead_pid"
[ ! -e "$STATE_DIR/sync.lock" ] || fail 'the reclaimed lock was not released'
printf 'not a pid\n' >"$STATE_DIR/sync.lock"
run_agent sync >"$TEST_ROOT/garbage.out" 2>&1
assert_contains "$TEST_ROOT/garbage.out" 'discarding an unreadable lock'
[ ! -e "$STATE_DIR/sync.lock" ] || fail 'the discarded lock was not released'

# A file edited while the model ran is kept and distributed as edited; the
# rewrite that never saw the edit is not accepted.
cat >"$TEST_ROOT/synth-race.sh" <<FIXTURE
printf '\n- edited while the model ran\n' >>"$CANON"
printf '# Raced memory\n'
awk 'f { print } /^--- DOCUMENT ---\$/ { f = 1 }'
FIXTURE
run_synth_fixture synth-race.sh >"$TEST_ROOT/race.out" 2>"$TEST_ROOT/race.err"
assert_contains "$TEST_ROOT/race.err" 'changed while the'
assert_contains "$TEST_ROOT/race.err" 'synthesis ran; keeping the deterministic merge'
assert_contains "$CANON" 'edited while the model ran'
[ "$(head -1 "$CANON")" != '# Raced memory' ] ||
  fail 'a rewrite that never saw the edit replaced the canon'
assert_contains "$AGENT_CONFIG_ROOT/.codex/AGENTS.md" 'edited while the model ran'

echo 'synth tests passed'
