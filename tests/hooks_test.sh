#!/bin/sh
# Hook recipes must name each tool's real event and real config path: they
# are pasted verbatim by users, so a wrong path is a silent no-op for them.
set -eu
. "$(CDPATH= cd "$(dirname "$0")" && pwd)/lib.sh"

run_agent hooks >"$TEST_ROOT/hooks.out"
assert_contains "$TEST_ROOT/hooks.out" 'SessionEnd'
assert_contains "$TEST_ROOT/hooks.out" 'session.idle'
run_agent hooks codex >"$TEST_ROOT/hooks-codex.out"
assert_contains "$TEST_ROOT/hooks-codex.out" 'Stop'
run_agent hooks gemini >"$TEST_ROOT/hooks-gemini.out"
assert_contains "$TEST_ROOT/hooks-gemini.out" 'AfterAgent'
assert_not_contains "$TEST_ROOT/hooks-gemini.out" '"SessionEnd"'
run_agent hooks opencode >"$TEST_ROOT/hooks-opencode.out"
assert_contains "$TEST_ROOT/hooks-opencode.out" '.config/opencode/plugin/agent-sync.js'
assert_not_contains "$TEST_ROOT/hooks-opencode.out" '.config/opencode/plugins/'
run_agent hooks launchd >"$TEST_ROOT/hooks-launchd.out"
assert_contains "$TEST_ROOT/hooks-launchd.out" 'LaunchAgents/io.agent-sync.compact.plist'
assert_contains "$TEST_ROOT/hooks-launchd.out" '<string>agent compact</string>'
assert_not_contains "$TEST_ROOT/hooks-launchd.out" 'SessionEnd'
assert_contains "$TEST_ROOT/hooks.out" '<string>agent compact</string>'
assert_contains "$TEST_ROOT/hooks.out" '0 9 * * 1 agent compact'
if run_agent hooks nonsense >/dev/null 2>"$TEST_ROOT/hooks-bad.err"; then
  fail 'hooks accepted an unknown tool'
fi
assert_contains "$TEST_ROOT/hooks-bad.err" 'launchd'

echo 'hooks tests passed'
