#!/bin/sh
# compact keeps the synthesized file under a byte budget: promotes raw imports
# and archives their stores, rewrites oversized sections through the model,
# and refuses any rewrite that drops an identifier, changes the heading, or is
# a refusal-sized stub. Every guard is falsified here with a mock that breaks
# exactly one of them.
set -eu
. "$(CDPATH= cd "$(dirname "$0")" && pwd)/lib.sh"

# The mock synthesizer reads the prompt, finds the target size and (for an
# import) the required heading, and emits the heading, every line carrying an
# identifier, then filler lines until it nears the target -- the shape of a
# real rewrite. Its first argument breaks one guard at a time.
cat >"$MOCK_BIN/compactor" <<'MOCK'
#!/bin/sh
mode="$1"
printf 'call %s\n' "$mode" >>"$SYNTH_LOG"
prompt=$(cat)
[ "$mode" = fail ] && exit 1
target=$(printf '%s\n' "$prompt" | sed -n 's/.*at most \([0-9][0-9]*\) bytes\.$/\1/p' | head -1)
heading=$(printf '%s\n' "$prompt" | sed -n 's/^- The first line of your output must be exactly: //p')
body=$(printf '%s\n' "$prompt" | awk 'f{print} /^--- SECTION ---/{f=1}')
if [ -n "$heading" ]; then
  first="$heading"
  rest=$(printf '%s\n' "$body")
else
  first=$(printf '%s\n' "$body" | head -1)
  rest=$(printf '%s\n' "$body" | tail -n +2)
fi
case "$mode" in
  badhead) first="# Something else" ;;
  tiny) printf '%s\n' "$first"; exit 0 ;;
esac
printf '%s\n' "$first"
printf '%s\n' "$rest" | awk -v t="$target" -v mode="$mode" -v n="$(printf '%s\n' "$first" | wc -c)" '
  /^---$/ { fm = !fm; next }
  fm { next }
  /^### / { next }
  mode == "drop" && /G-Z3LXJSB0MB/ { next }
  mode == "hex" && /0E0E0E/ { next }
  mode == "prose" && /146-account/ { next }
  mode == "prose" && /compare it to HEAD/ { sub(/ — compare it to HEAD before trusting /, " then check ") }
  /`|https?:\/\/|[0-9]/ { print; n += length($0) + 1; next }
  { keep[++k] = $0 }
  END { for (i = 1; i <= k; i++) { if (n + length(keep[i]) + 1 > t * 0.9) break; print keep[i]; n += length(keep[i]) + 1 } }'
MOCK
chmod +x "$MOCK_BIN/compactor"

run_agent_with_budget() {
  budget="$1"
  shift
  PATH="$SAFE_PATH" \
    TMPDIR="$TEST_TMPDIR" \
    NO_COLOR= FORCE_COLOR= CLICOLOR_FORCE= \
    AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
    AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER=deterministic \
    AGENT_SYNC_BUDGET="$budget" \
    "$AGENT_BIN" "$@"
}

run_compact() {
  mode="$1"
  shift
  PATH="$SAFE_PATH" \
    TMPDIR="$TEST_TMPDIR" \
    SYNTH_LOG="$SYNTH_LOG" \
    NO_COLOR= FORCE_COLOR= CLICOLOR_FORCE= \
    AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" \
    AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER="$MOCK_BIN/compactor $mode" \
    "$AGENT_BIN" compact "$@"
}

# A canon with one long section carrying identifiers, one short section, and
# one Claude store awaiting import.
bt=$(printf '\140')
write_fixture() {
  {
    printf '# Canon\n\nOpening line.\n\n## Rules\n\n'
    i=0
    while [ "$i" -lt 40 ]; do
      printf 'This paragraph explains at length why the rule exists and then repeats itself.\n'
      i=$((i + 1))
    done
    printf -- '- Analytics id %sG-Z3LXJSB0MB%s, docs https://example.com/docs/abc123 and sha de3e1c3 apply.\n' "$bt" "$bt"
    printf -- '- The release ritual uses %snpm version patch%s.\n' "$bt" "$bt"
    printf -- '- Purchase stops at 2026-02-05 in the 146-account chart, and tests start 429ing themselves.\n'
    printf -- '- All three carry %sReviewed commit:\n  <sha>%s — compare it to HEAD before trusting %sbadge/P<n>-%s counts.\n\n## Colours\n\n' "$bt" "$bt" "$bt" "$bt"
    i=0
    while [ "$i" -lt 30 ]; do
      printf 'A section with no URL in it, so the URL grep finds nothing and must not abort the rest.\n'
      i=$((i + 1))
    done
    printf -- '- The dark ladder runs from 0E0E0E to 262626 and lime is BFFF72.\n\n## Small\n\none line\n'
  } >"$CANON"
  mkdir -p "$(dirname "$CLAUDE_A")"
  {
    printf -- '---\nname: shared\ndescription: an imported store\nmetadata:\n  originSessionId: 3ab3c336-8985-4994-8e44-bc906079c304\n---\n\n'
    printf 'The Google Ads tag is %sAW-11072965548%s and the endpoint is https://ads.example/v9/tag.\n' "$bt" "$bt"
    i=0
    while [ "$i" -lt 12 ]; do
      printf 'Narrative about how the session went, which nobody needs to keep.\n'
      i=$((i + 1))
    done
  } >"$CLAUDE_A"
  rm -f "$CLAUDE_B" "$CODEX_MEMORY"
  run_agent sync >/dev/null
  cp "$CANON" "$TEST_ROOT/canon.before"
}

write_fixture
assert_contains "$CANON" '<!-- agent-sync:begin imported:claude -->'
before_bytes=$(wc -c <"$CANON" | tr -d ' ')
[ "$before_bytes" -gt 3000 ] || fail "fixture too small to compact: $before_bytes bytes"

# Within budget: no model call, nothing written, exit 0.
: >"$SYNTH_LOG"
run_compact good --budget 1000000 >"$TEST_ROOT/within.out"
assert_contains "$TEST_ROOT/within.out" 'within budget'
cmp -s "$CANON" "$TEST_ROOT/canon.before" || fail 'compact within budget modified the canon'
[ ! -s "$SYNTH_LOG" ] || fail 'compact within budget called the synthesizer'

# The deterministic merge cannot summarize.
if run_agent compact --synthesizer deterministic --budget 10 >"$TEST_ROOT/det.out" 2>&1; then
  fail 'compact accepted the deterministic synthesizer'
fi
assert_contains "$TEST_ROOT/det.out" 'deterministic merge cannot summarize'
cmp -s "$CANON" "$TEST_ROOT/canon.before" || fail 'a refused compact modified the canon'

# No model at all under auto.
if run_agent_without_models compact --budget 10 >"$TEST_ROOT/nomodel.out" 2>&1; then
  fail 'compact ran with no synthesizer available'
fi
assert_contains "$TEST_ROOT/nomodel.out" 'no synthesizer available'

# A budget must be a positive number of bytes.
if run_compact good --budget abc >"$TEST_ROOT/badbudget.out" 2>&1; then
  fail 'compact accepted a non-numeric budget'
fi
assert_contains "$TEST_ROOT/badbudget.out" 'positive number of bytes'

# Dry run: the plan, no model call, nothing written.
: >"$SYNTH_LOG"
run_compact good --budget 2800 --dry-run >"$TEST_ROOT/dry.out"
assert_contains "$TEST_ROOT/dry.out" 'would rewrite "## Rules"'
assert_contains "$TEST_ROOT/dry.out" 'would promote import:claude'
assert_not_contains "$TEST_ROOT/dry.out" 'Small'
cmp -s "$CANON" "$TEST_ROOT/canon.before" || fail 'dry-run modified the canon'
[ ! -s "$SYNTH_LOG" ] || fail 'dry-run called the synthesizer'
[ -f "$CLAUDE_A" ] || fail 'dry-run archived a store'

# The real thing: sections shrink, identifiers survive, the import is
# promoted, its store is archived, and the next sync has nothing to re-import.
: >"$SYNTH_LOG"
run_compact good --budget 2800 >"$TEST_ROOT/compact.out" || fail "compact exited nonzero: $(cat "$TEST_ROOT/compact.out")"
after_bytes=$(wc -c <"$CANON" | tr -d ' ')
[ "$after_bytes" -lt "$before_bytes" ] || fail "compact did not shrink the canon ($before_bytes -> $after_bytes)"
[ "$after_bytes" -le 2800 ] || fail "compact left the canon over budget: $after_bytes bytes"
assert_contains "$TEST_ROOT/compact.out" 'archived 1 store file(s)'
for id in 'G-Z3LXJSB0MB' 'https://example.com/docs/abc123' 'de3e1c3' 'npm version patch' 'AW-11072965548' 'https://ads.example/v9/tag'; do
  assert_contains "$CANON" "$id"
done
assert_contains "$CANON" '## Promoted from claude'
assert_not_contains "$CANON" 'agent-sync:begin imported:claude'
assert_not_contains "$CANON" 'originSessionId'
assert_contains "$CANON" '## Small'
assert_contains "$CANON" 'one line'
assert_contains "$CANON" '# Canon'
cmp -s "$CANON.bak" "$TEST_ROOT/canon.before" || fail 'compact did not keep the previous file at .bak'
[ ! -f "$CLAUDE_A" ] || fail 'the promoted store was not removed'
archive=$(find "$STATE_DIR/archive" -name 'stores-claude-*.tar.gz' 2>/dev/null | head -1)
[ -n "$archive" ] || fail 'no archive was written for the promoted stores'
tar tzf "$archive" | grep -q 'memory/shared.md$' || fail 'the archive does not list the promoted store'
cmp -s "$CANON" "$AGENT_CONFIG_ROOT/.claude/CLAUDE.md" || fail 'compact did not redistribute the result'
cp "$CANON" "$TEST_ROOT/canon.compacted"
run_agent sync >/dev/null
cmp -s "$CANON" "$TEST_ROOT/canon.compacted" || fail 'the sync after compact re-imported the archived store'
run_agent status >/dev/null || fail 'status failed after a successful compact'

# Prose is not an identifier: a rewrite may rephrase "146-account", "429ing"
# and the text between a broken span's closing backtick and the next opening
# one, so dropping those lines is accepted, while badge/P<n>- must survive.
write_fixture
run_compact prose --budget 2800 >"$TEST_ROOT/prose.out" 2>&1 || fail "compact refused a rewrite over prose tokens: $(cat "$TEST_ROOT/prose.out")"
assert_not_contains "$CANON" '146-account'
assert_not_contains "$CANON" 'compare it to HEAD'
assert_contains "$CANON" 'badge/P<n>-'
assert_contains "$CANON" '<sha>'
assert_not_contains "$TEST_ROOT/prose.out" 'kept'

# Falsify the identifier guard: a rewrite that drops G-Z3LXJSB0MB is refused
# and the section is kept verbatim, so the file stays over budget (exit 1).
write_fixture
: >"$SYNTH_LOG"
if run_compact drop --budget 2800 >"$TEST_ROOT/drop.out" 2>&1; then
  fail 'compact exited 0 after keeping a section and staying over budget'
fi
assert_contains "$TEST_ROOT/drop.out" 'the rewrite dropped:'
assert_contains "$TEST_ROOT/drop.out" 'G-Z3LXJSB0MB'
assert_contains "$TEST_ROOT/drop.out" 'still'
assert_contains "$TEST_ROOT/drop.out" '## Colours: '
assert_not_contains "$TEST_ROOT/drop.out" '## Colours: kept'

# A section with no URL is guarded too: the URL grep finds nothing there, and
# under set -e that once aborted the extractor before the bare tokens were
# read, so a rewrite that dropped a hex colour passed unchecked.
write_fixture
if run_compact hex --budget 2800 >"$TEST_ROOT/hex.out" 2>&1; then
  fail 'compact exited 0 after dropping a token from a URL-less section'
fi
assert_contains "$TEST_ROOT/hex.out" '## Colours: '
assert_contains "$TEST_ROOT/hex.out" 'the rewrite dropped:'
assert_contains "$TEST_ROOT/hex.out" '0E0E0E'
assert_contains "$CANON" '0E0E0E'
assert_contains "$CANON" 'G-Z3LXJSB0MB'
assert_contains "$CANON" 'explains at length why the rule exists'
assert_contains "$CANON" '## Promoted from claude'

# Falsify the heading guard.
write_fixture
if run_compact badhead --budget 2800 >"$TEST_ROOT/badhead.out" 2>&1; then
  fail 'compact exited 0 with every rewrite refused'
fi
assert_contains "$TEST_ROOT/badhead.out" 'does not start with the heading'
cmp -s "$CANON" "$TEST_ROOT/canon.before" || fail 'a refused heading rewrite changed the canon'
[ -f "$CLAUDE_A" ] || fail 'a refused import promotion still archived the store'

# Falsify the floor: a heading alone is a refusal, not a rewrite.
write_fixture
if run_compact tiny --budget 2800 >"$TEST_ROOT/tiny.out" 2>&1; then
  fail 'compact accepted a refusal-sized rewrite'
fi
assert_contains "$TEST_ROOT/tiny.out" 'below the 25% floor'
assert_contains "$TEST_ROOT/tiny.out" 'below the 8% floor'
cmp -s "$CANON" "$TEST_ROOT/canon.before" || fail 'a refusal-sized rewrite changed the canon'

# A failing model keeps everything.
write_fixture
if run_compact fail --budget 2800 >"$TEST_ROOT/fail.out" 2>&1; then
  fail 'compact exited 0 when the synthesizer failed'
fi
assert_contains "$TEST_ROOT/fail.out" 'the synthesizer failed'
cmp -s "$CANON" "$TEST_ROOT/canon.before" || fail 'a failed synthesizer run changed the canon'

# Budget reporting: sync warns, status and doctor fail while over budget.
write_fixture
run_agent_with_budget 10 sync >"$TEST_ROOT/sync-over.out" || fail 'sync exited nonzero over budget'
assert_contains "$TEST_ROOT/sync-over.out" 'over the 10-byte budget; run: agent compact'
if run_agent_with_budget 10 status >"$TEST_ROOT/status-over.out"; then
  fail 'status exited 0 over budget'
fi
assert_contains "$TEST_ROOT/status-over.out" 'over the 10-byte budget'
if run_agent_with_budget 10 doctor >"$TEST_ROOT/doctor-over.out"; then
  fail 'doctor exited 0 over budget'
fi
assert_contains "$TEST_ROOT/doctor-over.out" 'PROBLEM'
assert_contains "$TEST_ROOT/doctor-over.out" 'agent compact fixes'
run_agent status >"$TEST_ROOT/status-ok.out" || fail 'status failed within budget'
assert_contains "$TEST_ROOT/status-ok.out" 'of 150000 bytes'

echo 'compact tests passed'
