#!/bin/sh
# Repository policy that is cheaper to enforce than to remember.
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

echo 'workflow policy tests passed'
