#!/bin/sh
# Repository policy that is cheaper to enforce than to remember.
# shellcheck disable=SC2094  # the workflow file is only read, never written
set -eu
. "$(CDPATH= cd "$(dirname "$0")" && pwd)/lib.sh"

# Every action is pinned to a full-commit SHA carrying a version comment,
# so a moved upstream tag cannot change what CI runs and Dependabot can
# still read and rewrite the pin.
for workflow in "$PROJECT_DIR"/.github/workflows/*.yml; do
  while IFS= read -r line; do
    case "$line" in
      *"uses:"*"@"*) ;;
      *) continue ;;
    esac
    printf '%s\n' "$line" |
      grep -qE 'uses: [^ ]+@[0-9a-f]{40} +# v[0-9]+' ||
      fail "unpinned action in $(basename "$workflow"): $line"
  done <"$workflow"
done

# Every runner in the harness pins PATH. AGENT_SYNC_HOME isolates the files
# agent-sync writes itself, but `mcp sync` delegates to whichever vendor CLI
# is on PATH, and a real claude or codex writes to the developer's own
# configuration rather than the fixture -- which is how a probe server once
# ended up registered in a live ~/.claude.json.
runners=$(grep -c '^run_agent[a-z_]*() {' "$PROJECT_DIR/tests/lib.sh")
[ "$runners" -ge 4 ] ||
  fail "harness runners were renamed; the PATH-pinning check now proves nothing"
awk '
  /^run_agent[a-z_]*\(\) \{/ { fn = $1; expect = 1; next }
  expect == 1 {
    if ($0 !~ /^[[:space:]]*PATH=/) { print fn }
    expect = 0
  }
' "$PROJECT_DIR/tests/lib.sh" >"$TEST_ROOT/unpinned-runners"
[ ! -s "$TEST_ROOT/unpinned-runners" ] ||
  fail "harness runner does not pin PATH first: $(tr '\n' ' ' <"$TEST_ROOT/unpinned-runners")"

echo 'workflow policy tests passed'
