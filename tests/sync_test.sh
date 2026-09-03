#!/bin/sh
# The core round trip: gather, fold, redistribute, plus adoption safety,
# revert, diff, dry-run, doctor, targeting, migrate, the gather/apply loop
# and synthesizer selection.
set -eu
. "$(CDPATH= cd "$(dirname "$0")" && pwd)/lib.sh"

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

cp "$CANON" "$TEST_ROOT/idempotent.md"
run_agent sync >/dev/null
if ! cmp -s "$CANON" "$TEST_ROOT/idempotent.md"; then
  diff -u "$TEST_ROOT/idempotent.md" "$CANON" >&2 || true
  fail 'sync is not idempotent'
fi

# A removed source drops its imported section rather than stranding it.
rm -f "$CODEX_MEMORY"
run_agent sync >/dev/null
assert_not_contains "$CANON" '<!-- agent-sync:begin imported:codex -->'
assert_not_contains "$CANON" 'obsolete codex memory'

printf 'fresh codex memory\n' >"$CODEX_MEMORY"
run_agent migrate codex >/dev/null
assert_contains "$CANON" 'fresh codex memory'
rm -f "$CODEX_MEMORY"
run_agent sync >/dev/null

# Malformed markers abort before the canon is touched.
cp "$CANON" "$TEST_ROOT/canon-valid.md"
printf '\n<!-- agent-sync:begin imported:codex -->\nbroken\n' >>"$CANON"
cp "$CANON" "$TEST_ROOT/canon-malformed.md"
if run_agent sync >"$TEST_ROOT/malformed.out" 2>&1; then
  fail 'sync accepted malformed import markers'
fi
cmp -s "$CANON" "$TEST_ROOT/canon-malformed.md" ||
  fail 'sync modified the canon after rejecting malformed markers'
cp "$TEST_ROOT/canon-valid.md" "$CANON"

# The gather, edit, apply loop.
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

# apply accepts flags before, after and around the directory.
FLAGS_DIR="$TEST_ROOT/flags-apply"
run_agent gather "$FLAGS_DIR" >/dev/null
run_agent apply --dry-run "$FLAGS_DIR" >"$TEST_ROOT/apply-flags.out"
assert_contains "$TEST_ROOT/apply-flags.out" 'store file(s) updated'
run_agent apply "$FLAGS_DIR" --synthesizer deterministic --only codex >"$TEST_ROOT/apply-value-flags.out"
assert_contains "$TEST_ROOT/apply-value-flags.out" 'codex: synced'
assert_contains "$TEST_ROOT/apply-value-flags.out" 'gemini: skipped (filtered)'
run_agent apply --skip qwen "$FLAGS_DIR" --synthesizer deterministic >"$TEST_ROOT/apply-leading-flags.out"
assert_contains "$TEST_ROOT/apply-leading-flags.out" 'qwen: skipped (filtered)'

# Synthesizer selection: auto prefers Claude, falls through to Codex, and
# an explicit or missing selection never silently degrades.
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

# Synthesizer fixtures live in files rather than inline strings: each one has
# to read the prompt on stdin and answer proportionally to it, which is the
# behaviour the size floor is written against.
run_synth_fixture() {
  PATH="$SAFE_PATH" TMPDIR="$TEST_TMPDIR" AGENT_SYNC_ACTIVE=0 \
    AGENT_SYNC_HOME="$AGENT_CONFIG_ROOT" AGENT_SYNC_SOURCE="$CANON" \
    AGENT_SYNC_SYNTHESIZER="sh $TEST_ROOT/$1" "$AGENT_BIN" sync
}

# A synthesizer that prefaces the document with a line of chat still counts:
# the preamble is dropped, the document is kept. Rejecting it would discard a
# correct merge over one sentence.
cat >"$TEST_ROOT/synth-preamble.sh" <<'FIXTURE'
printf 'Here is the merged document:\n\n# Preambled memory\n'
awk 'f { print } /^--- DOCUMENT ---$/ { f = 1 }'
FIXTURE
run_synth_fixture synth-preamble.sh >/dev/null
[ "$(head -1 "$CANON")" = '# Preambled memory' ] ||
  fail "preamble was not stripped; canon starts: $(head -1 "$CANON")"
assert_not_contains "$CANON" 'Here is the merged document'

# Prose running past the window is a refusal, not a document. The canon keeps
# the deterministic merge rather than being replaced by the model's chat.
cat >"$TEST_ROOT/synth-long-refusal.sh" <<'FIXTURE'
i=0
while [ "$i" -lt 14 ]; do
  echo 'I cannot do that.'
  i=$((i + 1))
done
echo '# Too late'
FIXTURE
run_synth_fixture synth-long-refusal.sh >/dev/null 2>&1
assert_not_contains "$CANON" '# Too late'
assert_not_contains "$CANON" 'I cannot do that.'

# The size floor. A refusal that happens to open with a heading passes every
# other check, so without this it replaces the memory file and is pushed to
# every agent. Shrinking is legitimate -- folding the imported sections away
# is the whole job -- so the floor sits well below a real merge.
cat >"$TEST_ROOT/synth-stub.sh" <<'FIXTURE'
cat >/dev/null
printf '# Note\n\nI cannot rewrite this document.\n'
FIXTURE
cp "$CANON" "$TEST_ROOT/before-stub.md"
run_synth_fixture synth-stub.sh >/dev/null 2>&1
cmp -s "$CANON" "$TEST_ROOT/before-stub.md" ||
  fail 'a heading-prefixed stub replaced the canon'

# The identifier guard. A merge that reads well and clears the floor can still
# have summarised away the one thing an agent cannot re-derive; a real one
# dropped 919 of 1,116 identifiers from a 195 KB file. Every backtick span, URL
# and letter-and-digit token of the document must survive the merge.
bt=$(printf '\140')
printf 'Release %sv9.9.9-keep%s is documented at https://example.test/keep-0042 for tag ci-run-77.\n' "$bt" "$bt" >>"$CANON"
cat >"$TEST_ROOT/synth-drop-id.sh" <<'FIXTURE'
printf '# Lossy memory\n'
awk 'f && !/keep/ { print } /^--- DOCUMENT ---$/ { f = 1 }'
FIXTURE
cp "$CANON" "$TEST_ROOT/before-drop.md"
run_synth_fixture synth-drop-id.sh >"$TEST_ROOT/drop-id.out" 2>&1 && :
cmp -s "$CANON" "$TEST_ROOT/before-drop.md" ||
  fail 'a merge that dropped identifiers replaced the canon'
assert_contains "$TEST_ROOT/drop-id.out" 'synthesis dropped 1 identifier(s)'
assert_contains "$TEST_ROOT/drop-id.out" 'https://example.test/keep-0042'
run_agent_with_synthesizer sync >/dev/null
assert_contains "$CANON" '# Synthesized memory'
assert_contains "$CANON" 'https://example.test/keep-0042'

# Half the document is a plausible merge and must survive the floor, which is
# the failure mode of setting it too high.
cat >"$TEST_ROOT/synth-half.sh" <<'FIXTURE'
printf '# Halved memory\n'
awk 'f { n++; if (n % 2 == 0) print } /^--- DOCUMENT ---$/ { f = 1 }'
FIXTURE
run_synth_fixture synth-half.sh >/dev/null
assert_contains "$CANON" '# Halved memory'

echo 'sync tests passed'
