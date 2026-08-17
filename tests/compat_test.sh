#!/bin/sh
# The compatibility checker guards agent mcp against vendor CLI changes, so
# it must fail when a flag disappears. Substring matching would let
# "--scope" satisfy a check for "-s", making the short-flag assertions
# vacuous, which is the defect these fixtures pin.
set -eu
. "$(CDPATH= cd "$(dirname "$0")" && pwd)/lib.sh"

CHECK="$PROJECT_DIR/scripts/check-cli-grammar.sh"
STUB_BIN="$TEST_ROOT/stub-bin"
mkdir -p "$STUB_BIN"

# A CLI documenting both short and long forms, like Gemini and Qwen.
write_stub() {
  printf '%s\n' '#!/bin/sh' "cat <<'HELP'" "$2" 'HELP' >"$STUB_BIN/$1"
  chmod +x "$STUB_BIN/$1"
}

run_check() {
  printf '%s\n' "$2" | PATH="$STUB_BIN:/usr/bin:/bin" sh "$CHECK" "$1"
}

write_stub fulltool '  -s, --scope <scope>   where to write
  -e, --env <KEY=VALUE> environment
  --transport <type>    transport
  --header <header>     http header'

run_check fulltool 'mcp add --help :: -s' >/dev/null ||
  fail 'a documented short flag was reported missing'
run_check fulltool 'mcp add --help :: -e' >/dev/null ||
  fail 'a documented short flag was reported missing'
run_check fulltool 'mcp add --help :: --transport' >/dev/null ||
  fail 'a documented long flag was reported missing'
run_check fulltool 'mcp add --help :: --header' >/dev/null ||
  fail 'a documented long flag was reported missing'

# The regression: only the long forms remain. A substring match would see
# "-s" inside "--scope" and "-e" inside "--env" and wrongly pass.
write_stub longonly '  --scope <scope>       where to write
  --env <KEY=VALUE>     environment'

if run_check longonly 'mcp add --help :: -s' >"$TEST_ROOT/short-s.out" 2>&1; then
  fail 'a removed -s flag passed because --scope contains it'
fi
assert_contains "$TEST_ROOT/short-s.out" "no longer documents '-s'"
if run_check longonly 'mcp add --help :: -e' >/dev/null 2>&1; then
  fail 'a removed -e flag passed because --env contains it'
fi

# Subcommand names must not match inside longer words.
write_stub wordy 'Usage: wordy mcp <command>

  list        list servers
  additional  see the manual for additional options'

if run_check wordy 'mcp --help :: add' >"$TEST_ROOT/word.out" 2>&1; then
  fail 'a missing add subcommand passed because "additional" contains it'
fi
assert_contains "$TEST_ROOT/word.out" "no longer documents 'add'"
run_check wordy 'mcp --help :: list' >/dev/null ||
  fail 'a present subcommand was reported missing'

# A flag that is genuinely absent fails, and every assertion is evaluated
# rather than stopping at the first failure.
if run_check longonly 'mcp add --help :: --transport' >/dev/null 2>&1; then
  fail 'an absent flag passed'
fi
if run_check longonly 'mcp add --help :: -s
mcp add --help :: -e' >"$TEST_ROOT/both.out" 2>&1; then
  fail 'multiple absent flags passed'
fi
assert_contains "$TEST_ROOT/both.out" '2 of 2 grammar assertion(s) failed'

# Operator errors are refused rather than silently passing.
if printf 'no separator here\n' | PATH="$STUB_BIN:/usr/bin:/bin" sh "$CHECK" fulltool >/dev/null 2>&1; then
  fail 'a malformed assertion line was accepted'
fi
if printf '' | PATH="$STUB_BIN:/usr/bin:/bin" sh "$CHECK" fulltool >/dev/null 2>&1; then
  fail 'an empty assertion set was accepted'
fi
if PATH="$STUB_BIN:/usr/bin:/bin" sh "$CHECK" </dev/null >/dev/null 2>&1; then
  fail 'a missing tool argument was accepted'
fi

# The workflow must drive this script rather than reimplementing matching.
assert_contains "$PROJECT_DIR/.github/workflows/compat.yml" 'check-cli-grammar.sh'
assert_not_contains "$PROJECT_DIR/.github/workflows/compat.yml" 'grep -qF'

echo 'compat tests passed'
