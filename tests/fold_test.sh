#!/bin/sh
# shellcheck disable=SC2016  # mock bodies must not expand when written
# Incremental folding: a sync shows the model the file and the new memories
# and splices in only the sections that change; a block folded before is
# dropped with no model call; every guard on the answer is falsified with a
# mock that breaks exactly one of them; --rewrite still asks for the whole
# document.
set -eu
. "$(CDPATH= cd "$(dirname "$0")" && pwd)/lib.sh"

FOLD_MODE="$TEST_ROOT/fold-mode"
FOLD_PROMPT="$TEST_ROOT/fold-prompt.log"
printf 'fold\n' >"$FOLD_MODE"

# The mocks answer both prompt shapes: the whole-document prompt the way the
# lib.sh mocks do, the fold prompt with one "## Promoted from <agent>" section
# per agent in NEW MEMORIES (or, in replace mode, the file's own "## Notes"
# section grown by the memories). FOLD_MODE breaks one guard at a time.
cat >"$MOCK_BIN/claude" <<'MOCK'
#!/bin/sh
printf 'claude %s\n' "$*" >>"$SYNTH_LOG"
prompt=$(cat)
printf '%s\n' "$prompt" >"$FOLD_PROMPT"
mode=$(cat "$FOLD_MODE")
if [ "$mode" = fail ]; then
  echo 'Your workspace is out of credits.' >&2
  exit 1
fi
if ! printf '%s\n' "$prompt" | grep -q '^--- NEW MEMORIES ---$'; then
  printf '# Claude synthesized memory\n'
  printf '%s\n' "$prompt" | awk 'f { print } /^--- DOCUMENT ---$/ { f = 1 }'
  exit 0
fi
memories=$(printf '%s\n' "$prompt" | awk 'f { print } /^--- NEW MEMORIES ---$/ { f = 1 }')
context=$(printf '%s\n' "$prompt" | awk '/^--- NEW MEMORIES ---$/ { exit } f { print } /^--- MEMORY FILE/ { f = 1 }')
case "$mode" in
  preamble) echo 'Here are the changed sections:'; echo ;;
  prose)
    i=0
    while [ "$i" -lt 12 ]; do echo 'Let me explain what I changed and why, at length.'; i=$((i + 1)); done
    echo
    ;;
  echo) echo '## Memories imported from claude'; echo; echo '- copied straight back'; exit 0 ;;
  tiny) echo '## Notes'; exit 0 ;;
  dup) echo '## Promoted from claude'; echo; echo '- one'; echo; echo '## Promoted from claude'; echo; echo '- two'; exit 0 ;;
esac
if [ "$mode" = replace ]; then
  echo '## Notes'
  printf '%s\n' "$context" | awk '/^## Notes$/ { f = 1; next } /^## / { f = 0 } f'
  printf '%s\n' "$memories" | awk '/^From / || /^### / || /^$/ { next } { print "- " $0 }'
  exit 0
fi
told=0
printf '%s\n' "$prompt" | grep -q 'previous answer dropped the following' && told=1
printf '%s\n' "$memories" | awk -v mode="$mode" -v told="$told" '
  /^From [^ ]+:$/ {
    agent = $2; sub(/:$/, "", agent)
    if (started) print ""
    print "## Promoted from " agent; print ""
    started = 1; next
  }
  /^### / || /^$/ { next }
  mode == "drop" && /keep-0042/ { next }
  mode == "dropfirst" && !told && /keep-0042/ { next }
  { print "- " $0 }
'
MOCK
cat >"$MOCK_BIN/codex" <<'MOCK'
#!/bin/sh
printf 'codex %s\n' "$*" >>"$SYNTH_LOG"
prompt=$(cat)
if ! printf '%s\n' "$prompt" | grep -q '^--- NEW MEMORIES ---$'; then
  printf '# Codex synthesized memory\n'
  printf '%s\n' "$prompt" | awk 'f { print } /^--- DOCUMENT ---$/ { f = 1 }'
  exit 0
fi
printf '%s\n' "$prompt" | awk 'f { print } /^--- NEW MEMORIES ---$/ { f = 1 }' | awk '
  /^From [^ ]+:$/ {
    agent = $2; sub(/:$/, "", agent)
    if (started) print ""
    print "## Promoted from " agent; print ""; print "- (via codex)"
    started = 1; next
  }
  /^### / || /^$/ { next }
  { print "- " $0 }
'
MOCK
chmod +x "$MOCK_BIN/claude" "$MOCK_BIN/codex"

run_fold() {
  PATH="$SAFE_PATH" TMPDIR="$TEST_TMPDIR" \
    SYNTH_LOG="$SYNTH_LOG" FOLD_MODE="$FOLD_MODE" FOLD_PROMPT="$FOLD_PROMPT" \
    NO_COLOR= FORCE_COLOR= CLICOLOR_FORCE= AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER=auto "$AGENT_BIN" "$@"
}

claude_calls() { grep -c '^claude' "$SYNTH_LOG" || true; }

# First fold: two agents' stores become two promoted sections, the import
# blocks are gone, the head of the file is untouched, the fold is remembered.
: >"$SYNTH_LOG"
run_fold sync >"$TEST_ROOT/first.out" 2>"$TEST_ROOT/first.err"
assert_contains "$TEST_ROOT/first.out" 'folding 2 new import block(s)'
assert_contains "$TEST_ROOT/first.out" 'synthesized via: claude (fable)'
[ "$(claude_calls)" -eq 1 ] || fail "the first fold made $(claude_calls) claude calls, expected 1"
[ "$(head -1 "$CANON")" = '# Canon' ] || fail "the fold lost the file head: $(head -1 "$CANON")"
assert_contains "$CANON" 'Curated memory.'
assert_contains "$CANON" '## Promoted from claude'
assert_contains "$CANON" '- alpha without a final newline'
assert_contains "$CANON" '- bravo'
assert_contains "$CANON" '## Promoted from codex'
assert_contains "$CANON" '- obsolete codex memory'
assert_not_contains "$CANON" 'agent-sync:begin imported'
assert_not_contains "$CANON" '### /'
[ -f "$CANON.bak" ] || fail 'the fold did not keep the previous file'
if [ ! -f "$STATE_DIR/folded/claude" ] || [ ! -f "$STATE_DIR/folded/codex" ]; then
  fail 'the fold was not recorded'
fi
assert_contains "$FOLD_PROMPT" '--- NEW MEMORIES ---'
assert_contains "$FOLD_PROMPT" 'From claude:'
assert_contains "$FOLD_PROMPT" 'From codex:'
assert_contains "$FOLD_PROMPT" 'Print ONLY the sections of the file that change'
assert_not_contains "$FOLD_PROMPT" 'Rewrite the whole document'
assert_contains "$AGENT_CONFIG_ROOT/.codex/AGENTS.md" '## Promoted from claude'
[ -z "$(find "$TEST_TMPDIR" -mindepth 1 -print -quit)" ] || fail 'the fold left temporary files behind'
# The dropped blocks took the blank lines that set them apart with them, and
# each promoted section sits after exactly one blank line.
assert_clean_seams "$CANON"

# Nothing changed: the re-imported blocks are recognised and dropped without a
# model call, and the file reads as it did after the fold.
cp "$CANON" "$TEST_ROOT/after-first.md"
run_fold sync >"$TEST_ROOT/second.out" 2>&1
assert_contains "$TEST_ROOT/second.out" 'nothing new to fold'
assert_contains "$TEST_ROOT/second.out" 'removed: 2 import block(s) folded earlier'
[ "$(claude_calls)" -eq 1 ] || fail 'an unchanged store caused a model call'
cmp -s "$CANON" "$TEST_ROOT/after-first.md" || fail 'a sync with nothing new changed the file'

# One store changes: only that agent's block goes to the model, the other is
# dropped as folded before, and the promoted section is replaced, not doubled.
printf 'bravo\ncharlie at https://docs.estate-fixture.io/keep-0042\n' >"$CLAUDE_B"
run_fold sync >"$TEST_ROOT/third.out" 2>&1
assert_contains "$TEST_ROOT/third.out" 'folding 1 new import block(s)'
assert_contains "$TEST_ROOT/third.out" '1 import block(s) folded before will be dropped'
[ "$(claude_calls)" -eq 2 ] || fail "a changed store made $(claude_calls) claude calls in total, expected 2"
assert_contains "$FOLD_PROMPT" 'From claude:'
assert_not_contains "$FOLD_PROMPT" 'From codex:'
assert_contains "$CANON" 'charlie at https://docs.estate-fixture.io/keep-0042'
[ "$(grep -c '^## Promoted from claude$' "$CANON")" -eq 1 ] || fail 'the promoted section was doubled'
assert_contains "$CANON" '## Promoted from codex'
assert_not_contains "$CANON" 'agent-sync:begin imported'
# The answer's only section ends without a blank line; the section that
# follows it in the file must still start on one.
assert_clean_seams "$CANON"

# A fact removed from the curated text by hand comes back: its block is no
# longer "done" even though the store is unchanged.
sed '/keep-0042/d' "$CANON" >"$CANON.edited" && mv "$CANON.edited" "$CANON"
run_fold sync >"$TEST_ROOT/fourth.out" 2>&1
assert_contains "$TEST_ROOT/fourth.out" 'folding 1 new import block(s)'
assert_contains "$CANON" 'keep-0042'

# Replacing an existing section keeps every other section byte for byte.
rm -rf "$STATE_DIR/folded"
cat >"$TEST_ROOT/fixture-canon.md" <<'CANON_TEXT'
# Canon

Curated memory.

## Notes

These notes are the working section of the fixture. They run long enough that
a one-line answer sits well under the floor, which is what the tiny mode
below relies on, and they carry the token NOTES_ANCHOR so a test can see them.

## Other

Untouched body with OTHER_ANCHOR.
CANON_TEXT
cp "$TEST_ROOT/fixture-canon.md" "$CANON"
other_before=$(awk '/^## Other$/ { f = 1 } f' "$CANON")
printf 'replace\n' >"$FOLD_MODE"
run_fold sync >"$TEST_ROOT/replace.out" 2>&1
assert_contains "$TEST_ROOT/replace.out" 'synthesized via: claude (fable)'
assert_contains "$CANON" 'NOTES_ANCHOR'
assert_contains "$CANON" '- alpha without a final newline'
assert_contains "$CANON" '- obsolete codex memory'
other_after=$(awk '/^## Other$/ { f = 1 } f' "$CANON")
[ "$other_before" = "$other_after" ] || fail 'a section the fold did not name was changed'
[ "$(grep -n '^## ' "$CANON" | head -1)" = '5:## Notes' ] || fail "section order changed: $(grep -n '^## ' "$CANON" | head -1)"
assert_not_contains "$CANON" 'agent-sync:begin imported'
assert_clean_seams "$CANON"

# Each guard on the answer, one at a time: the file keeps its imports and its
# previous text when the answer is refused.
refused() {
  mode="$1"
  reason="$2"
  rm -rf "$STATE_DIR/folded"
  # A fresh fixture each time: the identifier the drop mode withholds must
  # live only in the store, not already in the curated text.
  cp "$TEST_ROOT/fixture-canon.md" "$CANON"
  printf '%s\n' "$mode" >"$FOLD_MODE"
  run_fold sync --synthesizer deterministic >/dev/null
  cp "$CANON" "$TEST_ROOT/before-$mode.md"
  # Claude only: every rung refuses the same way, and the deterministic merge
  # must stand. (In auto mode the Codex mock would take over, which the
  # fallback test below covers.)
  run_fold sync --synthesizer claude >"$TEST_ROOT/$mode.out" 2>"$TEST_ROOT/$mode.err"
  assert_contains "$TEST_ROOT/$mode.err" "$reason"
  assert_contains "$TEST_ROOT/$mode.err" 'every claude model failed; keeping the deterministic merge'
  cmp -s "$CANON" "$TEST_ROOT/before-$mode.md" || fail "a refused fold ($mode) changed the file"
  assert_contains "$CANON" '<!-- agent-sync:begin imported:claude -->'
}
refused tiny 'shrank "## Notes"'
refused echo 'echoed an imported block'
refused dup 'printed the same heading twice'
refused drop 'synthesis dropped 1 identifier(s)'
refused prose 'text before its first section'

# A model that dropped an identifier is told what it lost and tried once more
# before the ladder moves on; on the retry the same model keeps it.
rm -rf "$STATE_DIR/folded"
cp "$TEST_ROOT/fixture-canon.md" "$CANON"
printf 'dropfirst\n' >"$FOLD_MODE"
: >"$SYNTH_LOG"
run_fold sync --synthesizer claude >"$TEST_ROOT/dropfirst.out" 2>"$TEST_ROOT/dropfirst.err"
assert_contains "$TEST_ROOT/dropfirst.err" 'synthesis dropped 1 identifier(s)'
assert_contains "$TEST_ROOT/dropfirst.err" 'retrying claude fable once, naming the 1 identifier(s) it dropped'
assert_not_contains "$TEST_ROOT/dropfirst.err" 'trying the next model'
assert_contains "$FOLD_PROMPT" 'previous answer dropped the following'
assert_contains "$FOLD_PROMPT" '- https://docs.estate-fixture.io/keep-0042'
assert_contains "$CANON" 'keep-0042'
assert_not_contains "$CANON" 'agent-sync:begin imported'
[ "$(grep -c '^claude' "$SYNTH_LOG")" -eq 2 ] || fail "expected two calls, fable then fable again, saw $(grep -c '^claude' "$SYNTH_LOG")"
[ "$(grep -c 'model fable' "$SYNTH_LOG")" -eq 2 ] || fail 'the retry went to a different model'
assert_contains "$TEST_ROOT/dropfirst.out" 'synthesized via: claude (fable)'

# One line of chat before the sections is dropped, not fatal.
rm -rf "$STATE_DIR/folded"
printf 'preamble\n' >"$FOLD_MODE"
run_fold sync >"$TEST_ROOT/preamble.out" 2>&1
assert_contains "$TEST_ROOT/preamble.out" 'synthesized via: claude (fable)'
assert_not_contains "$CANON" 'Here are the changed sections'

# Every Claude model failing hands the fold to Codex, whose answer is spliced
# the same way.
rm -rf "$STATE_DIR/folded"
printf 'fail\n' >"$FOLD_MODE"
: >"$SYNTH_LOG"
run_fold sync >"$TEST_ROOT/fallback.out" 2>"$TEST_ROOT/fallback.err"
assert_contains "$TEST_ROOT/fallback.err" 'out of credits'
assert_contains "$TEST_ROOT/fallback.err" 'every claude model failed; trying the next fallback'
assert_contains "$TEST_ROOT/fallback.out" 'synthesized via: codex (gpt-5.6-terra)'
assert_contains "$CANON" '- (via codex)'
assert_not_contains "$CANON" 'agent-sync:begin imported'
assert_clean_seams "$CANON"
[ "$(claude_calls)" -eq 3 ] || fail 'every claude rung should have been tried before codex'

# --rewrite asks for the whole document, as before.
printf 'fold\n' >"$FOLD_MODE"
run_fold sync --rewrite >"$TEST_ROOT/rewrite.out" 2>&1
assert_contains "$FOLD_PROMPT" 'Rewrite the whole document'
assert_contains "$FOLD_PROMPT" '--- DOCUMENT ---'
assert_contains "$TEST_ROOT/rewrite.out" 'whole-document rewrite'
[ "$(head -1 "$CANON")" = '# Claude synthesized memory' ] || fail '--rewrite did not replace the whole document'

# Nothing imported at all: no model call, and it says so.
rm -f "$CLAUDE_A" "$CLAUDE_B" "$CODEX_MEMORY"
run_fold sync --synthesizer deterministic >/dev/null
assert_not_contains "$CANON" 'agent-sync:begin imported'
: >"$SYNTH_LOG"
run_fold sync >"$TEST_ROOT/nothing.out" 2>&1
assert_contains "$TEST_ROOT/nothing.out" 'nothing to fold'
[ "$(claude_calls)" -eq 0 ] || fail 'a file with nothing imported caused a model call'

# A dry run plans and touches nothing.
printf 'alpha again\n' >"$CLAUDE_A"
cp "$CANON" "$TEST_ROOT/before-dry.md"
run_fold sync --dry-run >"$TEST_ROOT/dry.out" 2>&1
assert_contains "$TEST_ROOT/dry.out" 'dry-run: would synthesize'
cmp -s "$CANON" "$TEST_ROOT/before-dry.md" || fail 'a dry run changed the file'
[ "$(claude_calls)" -eq 0 ] || fail 'a dry run called the model'

echo 'fold tests passed'
