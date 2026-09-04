#!/bin/sh
# shellcheck disable=SC2016  # mock bodies must not expand when written
# The budget pass at the end of a sync, and the largest-first plan behind it:
# a semantic sync that leaves the file over budget trims the largest sections
# back the same run, never on the deterministic path, never touching an
# import block or a store, keeping the synthesis's .bak; --no-compact and
# AGENT_SYNC_COMPACT=0 skip it; a small overrun plans one section, not all.
set -eu
. "$(CDPATH= cd "$(dirname "$0")" && pwd)/lib.sh"

AC_MODE="$TEST_ROOT/ac-mode"
printf 'ok\n' >"$AC_MODE"

# One mock for every prompt shape: a fold answer for NEW MEMORIES, a compact
# answer for SECTION (heading, every line carrying an identifier, filler to
# 90% of the target), the document for a whole-document prompt. foldfail
# answers the fold prompt with prose so the fold is refused.
cat >"$MOCK_BIN/claude" <<'MOCK'
#!/bin/sh
printf 'claude %s\n' "$*" >>"$SYNTH_LOG"
prompt=$(cat)
mode=$(cat "$AC_MODE")
if printf '%s\n' "$prompt" | grep -q '^--- SECTION ---$'; then
  printf 'compact\n' >>"$SYNTH_LOG"
  target=$(printf '%s\n' "$prompt" | sed -n 's/.*at most \([0-9][0-9]*\) bytes\.$/\1/p' | head -1)
  body=$(printf '%s\n' "$prompt" | awk 'f { print } /^--- SECTION ---$/ { f = 1 }')
  first=$(printf '%s\n' "$body" | head -1)
  printf '%s\n' "$first"
  printf '%s\n' "$body" | tail -n +2 | awk -v t="$target" -v n="$(printf '%s\n' "$first" | wc -c)" '
    /`|https?:\/\/|[0-9]/ { print; n += length($0) + 1; next }
    { keep[++k] = $0 }
    END { for (i = 1; i <= k; i++) { if (n + length(keep[i]) + 1 > t * 0.9) break; print keep[i]; n += length(keep[i]) + 1 } }'
  exit 0
fi
if printf '%s\n' "$prompt" | grep -q '^--- NEW MEMORIES ---$'; then
  printf 'fold\n' >>"$SYNTH_LOG"
  if [ "$mode" = foldfail ]; then
    i=0
    while [ "$i" -lt 12 ]; do echo 'I would rather describe the changes than make them.'; i=$((i + 1)); done
    exit 0
  fi
  printf '%s\n' "$prompt" | awk 'f { print } /^--- NEW MEMORIES ---$/ { f = 1 }' | awk '
    /^From [^ ]+:$/ { agent = $2; sub(/:$/, "", agent); if (started) print ""; print "## Promoted from " agent; print ""; started = 1; next }
    /^### / || /^$/ { next }
    { print "- " $0 }
  '
  exit 0
fi
printf '# Claude synthesized memory\n'
printf '%s\n' "$prompt" | awk 'f { print } /^--- DOCUMENT ---$/ { f = 1 }'
MOCK
chmod +x "$MOCK_BIN/claude"

run_sync() {
  budget="$1"
  shift
  PATH="$SAFE_PATH" TMPDIR="$TEST_TMPDIR" \
    SYNTH_LOG="$SYNTH_LOG" AC_MODE="$AC_MODE" \
    NO_COLOR= FORCE_COLOR= CLICOLOR_FORCE= AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER=auto AGENT_SYNC_BUDGET="$budget" \
    "$AGENT_BIN" sync "$@"
}

bt=$(printf '\140')
write_fixture() {
  {
    printf '# Canon\n\nOpening line.\n\n## Rules\n\n'
    i=0
    while [ "$i" -lt 40 ]; do
      printf 'This paragraph explains at length why the rule exists and then repeats itself.\n'
      i=$((i + 1))
    done
    printf -- '- Analytics id %sG-Z3LXJSB0MB%s and docs https://example.com/docs/abc123 apply.\n\n## Colours\n\n' "$bt" "$bt"
    i=0
    while [ "$i" -lt 28 ]; do
      printf 'A section with no identifier in it, long enough to be worth a model call.\n'
      i=$((i + 1))
    done
    printf '\n## Small\n\none line\n'
  } >"$CANON"
  printf 'The Google Ads tag is %sAW-11072965548%s.\n' "$bt" "$bt" >"$CLAUDE_A"
  rm -f "$CLAUDE_B" "$CODEX_MEMORY"
  rm -rf "$STATE_DIR/folded"
}
compact_calls() { grep -c '^compact' "$SYNTH_LOG" || true; }

# A fold within budget: no budget pass at all.
write_fixture
: >"$SYNTH_LOG"
run_sync 1000000 >"$TEST_ROOT/fold.out" 2>&1
assert_contains "$CANON" '## Promoted from claude'
assert_not_contains "$TEST_ROOT/fold.out" 'compacting'
[ "$(compact_calls)" -eq 0 ] || fail 'a sync within budget compacted'
total=$(wc -c <"$CANON" | tr -d ' ')
colours_before=$(awk '/^## Colours$/ { f = 1 } /^## Small$/ { f = 0 } f' "$CANON")

# Over budget by a little: the largest section alone is trimmed, the others
# are byte for byte as they were, the store is untouched, the .bak is the
# pre-sync file, and the file ends under budget.
budget=$((total - 500))
cp "$CANON" "$TEST_ROOT/pre-sync.md"
: >"$SYNTH_LOG"
run_sync "$budget" >"$TEST_ROOT/trim.out" 2>&1
assert_contains "$TEST_ROOT/trim.out" 'compacting the largest sections first'
assert_contains "$TEST_ROOT/trim.out" 'trimming the largest sections first, 1 of them'
assert_contains "$TEST_ROOT/trim.out" '## Rules: '
assert_not_contains "$TEST_ROOT/trim.out" '## Colours: '
assert_not_contains "$TEST_ROOT/trim.out" 'import:'
assert_contains "$TEST_ROOT/trim.out" 'compact: '
[ "$(compact_calls)" -eq 1 ] || fail "expected one compact call, saw $(compact_calls)"
after=$(wc -c <"$CANON" | tr -d ' ')
[ "$after" -le "$budget" ] || fail "the budget pass left the file over budget: $after > $budget"
[ "$(awk '/^## Colours$/ { f = 1 } /^## Small$/ { f = 0 } f' "$CANON")" = "$colours_before" ] ||
  fail 'a section the plan did not name was changed'
assert_contains "$CANON" 'G-Z3LXJSB0MB'
assert_contains "$CANON" 'https://example.com/docs/abc123'
assert_contains "$CANON" 'one line'
assert_contains "$CANON" '## Promoted from claude'
[ -f "$CLAUDE_A" ] || fail 'the budget pass archived a store'
# The .bak is the file as the synthesis found it (after this run's import,
# before any model call): it still carries the re-imported block and the
# untrimmed section. Had the budget pass written its own .bak, the block
# would be gone from it.
assert_contains "$CANON.bak" '<!-- agent-sync:begin imported:claude -->'
[ "$(grep -c 'explains at length' "$CANON.bak")" -eq 40 ] || fail 'the .bak does not hold the untrimmed section'
[ "$(grep -c 'explains at length' "$CANON")" -lt 40 ] || fail 'the largest section was not trimmed'
cmp -s "$CANON" "$AGENT_CONFIG_ROOT/.codex/AGENTS.md" || fail 'the trimmed file was not what got distributed'
assert_not_contains "$TEST_ROOT/trim.out" 'over the'

# Within budget again: nothing happens.
: >"$SYNTH_LOG"
run_sync "$budget" >"$TEST_ROOT/again.out" 2>&1
assert_not_contains "$TEST_ROOT/again.out" 'compacting'
[ ! -s "$SYNTH_LOG" ] || fail 'a sync within budget with nothing new called the model'

# Opting out: the warning is printed, the file is left alone.
total=$(wc -c <"$CANON" | tr -d ' ')
tight=$((total - 200))
cp "$CANON" "$TEST_ROOT/before-opt-out.md"
: >"$SYNTH_LOG"
run_sync "$tight" --no-compact >"$TEST_ROOT/no-compact.out" 2>&1
assert_not_contains "$TEST_ROOT/no-compact.out" 'compacting'
assert_contains "$TEST_ROOT/no-compact.out" 'over the'
cmp -s "$CANON" "$TEST_ROOT/before-opt-out.md" || fail '--no-compact still changed the file'
[ ! -s "$SYNTH_LOG" ] || fail '--no-compact still called the model'
(
  export AGENT_SYNC_COMPACT=0
  run_sync "$tight" >"$TEST_ROOT/env-off.out" 2>&1
)
assert_not_contains "$TEST_ROOT/env-off.out" 'compacting'
cmp -s "$CANON" "$TEST_ROOT/before-opt-out.md" || fail 'AGENT_SYNC_COMPACT=0 still changed the file'

# The deterministic path never spends a model call, over budget or not.
run_sync "$tight" --synthesizer deterministic >"$TEST_ROOT/det.out" 2>&1
assert_not_contains "$TEST_ROOT/det.out" 'compacting'
assert_contains "$TEST_ROOT/det.out" 'over the'
[ ! -s "$SYNTH_LOG" ] || fail 'a deterministic sync called the model'

# A dry run says what it would do and touches nothing. (The deterministic
# sync above re-appended the import block, so the snapshot is taken here.)
cp "$CANON" "$TEST_ROOT/before-dry.md"
run_sync "$tight" --dry-run >"$TEST_ROOT/dry.out" 2>&1
assert_contains "$TEST_ROOT/dry.out" 'dry-run: would compact'
cmp -s "$CANON" "$TEST_ROOT/before-dry.md" || fail 'a dry run changed the file'
[ ! -s "$SYNTH_LOG" ] || fail 'a dry run called the model'

# The fold is refused and the import block stays: the budget pass trims
# sections only, never the block, and never archives the store.
write_fixture
printf 'foldfail\n' >"$AC_MODE"
: >"$SYNTH_LOG"
run_sync 3000 >"$TEST_ROOT/foldfail.out" 2>"$TEST_ROOT/foldfail.err"
assert_contains "$TEST_ROOT/foldfail.err" 'every claude model failed'
assert_contains "$TEST_ROOT/foldfail.out" 'compacting the largest sections first'
assert_contains "$TEST_ROOT/foldfail.out" '## Rules: '
assert_not_contains "$TEST_ROOT/foldfail.out" 'import:'
assert_contains "$CANON" '<!-- agent-sync:begin imported:claude -->'
assert_contains "$CANON" 'AW-11072965548'
[ -f "$CLAUDE_A" ] || fail 'the budget pass archived a store after a refused fold'
[ ! -d "$STATE_DIR/archive" ] || fail 'the budget pass wrote an archive'
printf 'ok\n' >"$AC_MODE"

# The plan itself, largest first: a small deficit names one section, a larger
# one names the next largest too and still leaves the smallest alone.
{
  printf '# Canon\n\n## Big\n\n'
  i=0; while [ "$i" -lt 75 ]; do printf 'Big section line number %s carries some words.\n' "$i"; i=$((i + 1)); done
  printf '\n## Medium\n\n'
  i=0; while [ "$i" -lt 50 ]; do printf 'Medium section line number %s carries some words.\n' "$i"; i=$((i + 1)); done
  printf '\n## Least\n\n'
  i=0; while [ "$i" -lt 30 ]; do printf 'Least section line number %s carries some words.\n' "$i"; i=$((i + 1)); done
} >"$CANON"
rm -f "$CLAUDE_A"
plan() {
  PATH="$SAFE_PATH" TMPDIR="$TEST_TMPDIR" NO_COLOR= FORCE_COLOR= CLICOLOR_FORCE= \
    AGENT_SYNC_ACTIVE=0 AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER=cat "$AGENT_BIN" compact --dry-run --budget "$1"
}
total=$(wc -c <"$CANON" | tr -d ' ')
big=$(awk '/^## Big$/ { f = 1 } /^## Medium$/ { f = 0 } f' "$CANON" | wc -c | tr -d ' ')
medium=$(awk '/^## Medium$/ { f = 1 } /^## Least$/ { f = 0 } f' "$CANON" | wc -c | tr -d ' ')
# The deficit is total - 95% of budget; these budgets set it to a chosen
# fraction of the two large sections' gentle (30%) cuts.
budget_for_need() { echo $((total - ($1 * 100 - total * 5) / 95)); }
target_of() { sed -n "s/.*\"## $1\" ([0-9]* bytes) to about \([0-9]*\).*/\1/p" "$2"; }

# A deficit under Big's gentle cut: one section, nothing else.
plan "$(budget_for_need $((big * 15 / 100)))" >"$TEST_ROOT/plan-small.out"
assert_contains "$TEST_ROOT/plan-small.out" 'trimming the largest sections first, 1 of them'
assert_contains "$TEST_ROOT/plan-small.out" 'would rewrite "## Big"'
assert_not_contains "$TEST_ROOT/plan-small.out" 'Medium'
assert_not_contains "$TEST_ROOT/plan-small.out" 'Least'

# A deficit past Big's gentle cut but within Big's plus half of Medium's:
# round one covers it with Big at exactly 30% and Medium for the rest.
plan "$(budget_for_need $((big * 30 / 100 + medium * 15 / 100)))" >"$TEST_ROOT/plan-two.out"
assert_contains "$TEST_ROOT/plan-two.out" 'trimming the largest sections first, 2 of them'
assert_contains "$TEST_ROOT/plan-two.out" 'would rewrite "## Medium"'
assert_not_contains "$TEST_ROOT/plan-two.out" 'Least'
big_target=$(target_of Big "$TEST_ROOT/plan-two.out")
[ $((big_target * 100)) -ge $((big * 69)) ] || fail "round one asked Big for more than a 30% cut: $big -> $big_target"

# A deficit past both gentle cuts: round two deepens Big first and leaves
# Medium at its gentle cut.
plan "$(budget_for_need $((big * 30 / 100 + medium * 30 / 100 + 200)))" >"$TEST_ROOT/plan-deep.out"
assert_contains "$TEST_ROOT/plan-deep.out" 'trimming the largest sections first, 2 of them'
big_target=$(target_of Big "$TEST_ROOT/plan-deep.out")
medium_target=$(target_of Medium "$TEST_ROOT/plan-deep.out")
[ $((big_target * 100)) -lt $((big * 69)) ] || fail "round two did not deepen Big: $big -> $big_target"
[ $((medium_target * 100)) -ge $((medium * 69)) ] || fail "round two deepened Medium before exhausting Big: $medium -> $medium_target"
assert_not_contains "$TEST_ROOT/plan-deep.out" 'Least'

echo 'autocompact tests passed'
