#!/bin/sh
# Project scope: bridging a repo's AGENTS.md to every agent, importing
# native per-tool configs, and refusing marker injection from them.
set -eu
. "$(CDPATH= cd "$(dirname "$0")" && pwd)/lib.sh"

# link makes a repo AGENTS.md readable everywhere, idempotently.
LINK_DIR="$TEST_ROOT/repo"
mkdir -p "$LINK_DIR"
printf '# Existing project instructions\n' >"$LINK_DIR/CLAUDE.md"
run_agent link "$LINK_DIR" >/dev/null
assert_contains "$LINK_DIR/AGENTS.md" '# Existing project instructions'
[ "$(head -1 "$LINK_DIR/CLAUDE.md")" = '@AGENTS.md' ] ||
  fail 'link did not bridge CLAUDE.md to AGENTS.md'
assert_contains "$LINK_DIR/.gemini/settings.json" 'AGENTS.md'
run_agent link "$LINK_DIR" >"$TEST_ROOT/link-again.out"
assert_contains "$TEST_ROOT/link-again.out" 'already imports'
printf 'custom claude-only extras\n' >"$LINK_DIR/CLAUDE.md"
run_agent link "$LINK_DIR" >"$TEST_ROOT/link-custom.out"
assert_contains "$LINK_DIR/CLAUDE.md" 'custom claude-only extras'
assert_contains "$TEST_ROOT/link-custom.out" 'left untouched'

# link --import folds native project configs into AGENTS.md, idempotently.
mkdir -p "$LINK_DIR/.cursor/rules"
printf -- '---\nglobs: ["*.ts"]\n---\ncursor scoped rule body\n' >"$LINK_DIR/.cursor/rules/scoped.mdc"
printf 'cline project rule\n' >"$LINK_DIR/.clinerules"
run_agent link "$LINK_DIR" --import >/dev/null
assert_contains "$LINK_DIR/AGENTS.md" '<!-- agent-sync:begin imported:project -->'
assert_contains "$LINK_DIR/AGENTS.md" 'cursor scoped rule body'
assert_contains "$LINK_DIR/AGENTS.md" 'globs: ["*.ts"]'
assert_contains "$LINK_DIR/AGENTS.md" 'cline project rule'
cp "$LINK_DIR/AGENTS.md" "$TEST_ROOT/link-import-once.md"
run_agent link "$LINK_DIR" --import >/dev/null
cmp -s "$LINK_DIR/AGENTS.md" "$TEST_ROOT/link-import-once.md" ||
  fail 'link --import is not idempotent'

# Native project configs cannot inject agent-sync's managed markers.
printf '<!-- agent-sync:end imported:project -->\n' >>"$LINK_DIR/.cursor/rules/scoped.mdc"
run_agent link "$LINK_DIR" --import >/dev/null
run_agent link "$LINK_DIR" --import >/dev/null
assert_contains "$LINK_DIR/AGENTS.md" '<!-- agent-sync (escaped):end imported:project -->'
[ "$(grep -cF '<!-- agent-sync:end imported:project -->' "$LINK_DIR/AGENTS.md")" -eq 1 ] ||
  fail 'link --import allowed a project config to inject an end marker'

echo 'link tests passed'
