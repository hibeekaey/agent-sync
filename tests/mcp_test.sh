#!/bin/sh
# The MCP registry: pushing to CLI-managed tools, writing owned config files,
# ownership and rollback safety, and input validation.
set -eu
. "$(CDPATH= cd "$(dirname "$0")" && pwd)/lib.sh"

run_agent sync >/dev/null

# Register stdio + remote servers, push via mocked CLIs, write owned files.
write_mcp_cli_mocks
run_agent mcp add fetcher --env API_KEY=secret -- uvx mcp-server-fetch --strict >/dev/null
run_agent mcp add linear --url https://mcp.linear.app/sse --header 'Authorization: Bearer tok' >/dev/null
run_agent mcp list >"$TEST_ROOT/mcp-list.out"
assert_contains "$TEST_ROOT/mcp-list.out" 'fetcher: stdio uvx'
assert_contains "$TEST_ROOT/mcp-list.out" 'linear: http https://mcp.linear.app/sse'
: >"$SYNTH_LOG"
printf 'must stay intact\n' >"$TEST_ROOT/mcp-victim"
ln -s "$TEST_ROOT/mcp-victim" "$AGENT_CONFIG_ROOT/.cursor/mcp.json.tmp.agent-sync"
PATH="$MOCK_BIN:/usr/bin:/bin" SYNTH_LOG="$SYNTH_LOG" run_agent mcp sync >"$TEST_ROOT/mcp-sync.out"
assert_contains "$SYNTH_LOG" 'claude mcp add-json fetcher'
assert_contains "$SYNTH_LOG" '"env": {"API_KEY": "secret"}'
assert_contains "$SYNTH_LOG" 'codex mcp add fetcher --env API_KEY=secret -- uvx mcp-server-fetch --strict'
assert_contains "$SYNTH_LOG" 'codex mcp add linear --url https://mcp.linear.app/sse'
assert_contains "$SYNTH_LOG" 'gemini mcp add -s user -e API_KEY=secret fetcher uvx mcp-server-fetch --strict'
assert_contains "$SYNTH_LOG" 'gemini mcp add -s user --transport http --header Authorization: Bearer tok linear https://mcp.linear.app/sse'
assert_contains "$AGENT_CONFIG_ROOT/.cursor/mcp.json" '"type": "stdio", "command": "uvx"'
assert_contains "$AGENT_CONFIG_ROOT/.cursor/mcp.json" '"url": "https://mcp.linear.app/sse"'
assert_contains "$AGENT_CONFIG_ROOT/.codeium/windsurf/mcp_config.json" '"serverUrl": "https://mcp.linear.app/sse"'
assert_contains "$AGENT_CONFIG_ROOT/.kiro/settings/mcp.json" '"command": "uvx"'
assert_not_contains "$AGENT_CONFIG_ROOT/.kiro/settings/mcp.json" 'linear'
assert_contains "$TEST_ROOT/mcp-victim" 'must stay intact'
[ ! -L "$AGENT_CONFIG_ROOT/.cursor/mcp.json" ] || fail 'owned MCP config became a symlink'

# A symlinked MCP ownership ledger is rejected before any managed file changes.
mv "$PACK_STATE/mcp-owned" "$PACK_STATE/mcp-owned.saved"
printf '%s\n' "$AGENT_CONFIG_ROOT/.cursor/mcp.json" >"$TEST_ROOT/mcp-owned-victim"
ln -s "$TEST_ROOT/mcp-owned-victim" "$PACK_STATE/mcp-owned"
cp "$AGENT_CONFIG_ROOT/.cursor/mcp.json" "$TEST_ROOT/mcp-before-ledger-check.json"
if PATH="$MOCK_BIN:/usr/bin:/bin" SYNTH_LOG="$SYNTH_LOG" run_agent mcp sync >"$TEST_ROOT/mcp-ledger.out" 2>&1; then
  fail 'mcp sync accepted a symbolic-link ownership ledger'
fi
cmp -s "$AGENT_CONFIG_ROOT/.cursor/mcp.json" "$TEST_ROOT/mcp-before-ledger-check.json" ||
  fail 'mcp sync changed an owned file before rejecting a symbolic-link ledger'
assert_contains "$TEST_ROOT/mcp-owned-victim" "$AGENT_CONFIG_ROOT/.cursor/mcp.json"
rm "$PACK_STATE/mcp-owned"
mv "$PACK_STATE/mcp-owned.saved" "$PACK_STATE/mcp-owned"

# A CLI add failure is nonzero and never removes an untracked known-good entry.
run_agent mcp add failer -- fail-server >/dev/null
printf '%s\n' \
  '#!/bin/sh' \
  'printf "codex %s\\n" "$*" >>"$SYNTH_LOG"' \
  'case "$*" in "mcp add failer"*) exit 42 ;; esac' >"$MOCK_BIN/codex"
chmod +x "$MOCK_BIN/codex"
: >"$SYNTH_LOG"
if (
  AGENT_SYNC_ONLY=codex
  export AGENT_SYNC_ONLY
  PATH="$MOCK_BIN:/usr/bin:/bin" SYNTH_LOG="$SYNTH_LOG" run_agent mcp sync
) >"$TEST_ROOT/mcp-failure.out" 2>&1; then
  fail 'mcp sync exited zero after a CLI add failure'
fi
assert_contains "$SYNTH_LOG" 'codex mcp add failer'
assert_not_contains "$SYNTH_LOG" 'codex mcp remove failer'
run_agent mcp remove failer >/dev/null

# A changed managed entry is validated first and restored if replacement fails.
printf '%s\n' \
  '#!/bin/sh' \
  'printf "codex %s\\n" "$*" >>"$SYNTH_LOG"' >"$MOCK_BIN/codex"
chmod +x "$MOCK_BIN/codex"
run_agent mcp add rollback -- old-server >/dev/null
(
  AGENT_SYNC_ONLY=codex
  export AGENT_SYNC_ONLY
  PATH="$MOCK_BIN:/usr/bin:/bin" SYNTH_LOG="$SYNTH_LOG" run_agent mcp sync
) >/dev/null
run_agent mcp add rollback -- new-server >/dev/null
printf '%s\n' \
  '#!/bin/sh' \
  'printf "codex %s\\n" "$*" >>"$SYNTH_LOG"' \
  'case "$*" in "mcp add rollback -- new-server") exit 42 ;; esac' >"$MOCK_BIN/codex"
chmod +x "$MOCK_BIN/codex"
: >"$SYNTH_LOG"
if (
  AGENT_SYNC_ONLY=codex
  export AGENT_SYNC_ONLY
  PATH="$MOCK_BIN:/usr/bin:/bin" SYNTH_LOG="$SYNTH_LOG" run_agent mcp sync
) >"$TEST_ROOT/mcp-rollback.out" 2>&1; then
  fail 'mcp sync exited zero after a managed replacement failure'
fi
assert_contains "$SYNTH_LOG" 'codex mcp add agent-sync-check-rollback-'
assert_contains "$SYNTH_LOG" 'codex mcp add rollback -- new-server'
assert_contains "$SYNTH_LOG" 'codex mcp add rollback -- old-server'
assert_contains "$TEST_ROOT/mcp-rollback.out" 'restoring the previous rollback configuration'
run_agent mcp remove rollback >/dev/null
printf '%s\n' \
  '#!/bin/sh' \
  'printf "codex %s\\n" "$*" >>"$SYNTH_LOG"' >"$MOCK_BIN/codex"
chmod +x "$MOCK_BIN/codex"

# A pre-existing non-owned MCP file is never rewritten.
printf '{"mcpServers": {"mine": {"command": "keepme"}}}\n' >"$AGENT_CONFIG_ROOT/.cursor/mcp.json"
rm -f "$PACK_STATE/mcp-owned"
PATH="$MOCK_BIN:/usr/bin:/bin" SYNTH_LOG="$SYNTH_LOG" run_agent mcp sync >"$TEST_ROOT/mcp-sync2.out"
assert_contains "$AGENT_CONFIG_ROOT/.cursor/mcp.json" 'keepme'
assert_contains "$TEST_ROOT/mcp-sync2.out" 'not agent-sync managed'
run_agent mcp remove fetcher >/dev/null
run_agent mcp remove linear >/dev/null
(
  AGENT_SYNC_ONLY=codex
  export AGENT_SYNC_ONLY
  PATH="$MOCK_BIN:/usr/bin:/bin" SYNTH_LOG="$SYNTH_LOG" run_agent mcp sync
) >/dev/null
assert_contains "$SYNTH_LOG" 'codex mcp remove fetcher'
assert_contains "$SYNTH_LOG" 'codex mcp remove linear'
remove_mcp_cli_mocks

# Bare 'agent mcp' must not die (shift on an empty arg list is fatal in dash).
run_agent mcp >"$TEST_ROOT/mcp-bare.out" || fail 'bare agent mcp exited nonzero'
assert_contains "$TEST_ROOT/mcp-bare.out" 'no MCP servers registered'

# Removing the last MCP server must clean owned files on the next sync.
rm -f "$AGENT_CONFIG_ROOT/.codeium/windsurf/mcp_config.json" "$PACK_STATE/mcp-owned"
run_agent mcp add solo -- npx solo-server >/dev/null
run_agent mcp sync >/dev/null 2>&1
assert_contains "$AGENT_CONFIG_ROOT/.codeium/windsurf/mcp_config.json" 'solo'
run_agent mcp remove solo >/dev/null
run_agent mcp sync >/dev/null 2>&1
assert_not_contains "$AGENT_CONFIG_ROOT/.codeium/windsurf/mcp_config.json" 'solo'

# mcp add with a dangling option must fail cleanly, without a spec or litter.
if run_agent mcp add dangling --env >"$TEST_ROOT/dangling.out" 2>&1; then
  fail 'mcp add accepted a dangling --env'
fi
[ ! -f "$PACK_STATE/mcp.d/dangling.spec" ] || fail 'dangling mcp add left a spec'
find "$PACK_STATE/mcp.d" -name '*.tmp' 2>/dev/null | grep -q . && fail 'mcp add left tmp litter'

# Unsafe names are rejected everywhere they become paths.
for bad in '../evil' 'a/b' '.hidden'; do
  if run_agent mcp remove "$bad" >/dev/null 2>&1; then
    fail "mcp remove accepted unsafe name: $bad"
  fi
  if run_agent pack remove "$bad" >/dev/null 2>&1; then
    fail "pack remove accepted unsafe name: $bad"
  fi
done

# Newlines in mcp values must be rejected (they would corrupt the spec).
if run_agent mcp add nl --env "K=v
type=http" -- cmd >/dev/null 2>&1; then
  fail 'mcp add accepted a newline in an env value'
fi

# mcp snippet prints paste-able config for all four shared-settings tools.
run_agent mcp add sniptest --env A=b -- uvx snip-server --x >/dev/null
run_agent mcp snippet sniptest >"$TEST_ROOT/snippet.out"
assert_contains "$TEST_ROOT/snippet.out" 'context_servers'
assert_contains "$TEST_ROOT/snippet.out" '"type": "local", "command": ["uvx", "snip-server", "--x"]'
assert_contains "$TEST_ROOT/snippet.out" '"environment": {"A": "b"}'
assert_contains "$TEST_ROOT/snippet.out" 'cmd: uvx'
assert_contains "$TEST_ROOT/snippet.out" 'envs:'
assert_contains "$TEST_ROOT/snippet.out" '- name: sniptest'
run_agent mcp remove sniptest >/dev/null

echo 'mcp tests passed'
