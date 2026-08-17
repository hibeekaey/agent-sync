#!/bin/sh
# Assert that a vendor CLI still documents every flag and subcommand
# agent-sync passes to it. Reads "help arguments :: token" lines on stdin
# and runs each help invocation against the named tool.
#
#   printf 'mcp add --help :: --env\n' | check-cli-grammar.sh codex
#
# Matching is boundary-aware on purpose. Substring matching would let
# "--scope" satisfy a check for "-s" and "additional" satisfy "add", so a
# removed short flag would go unnoticed, which is the whole point of the
# check.
set -eu

TOOL="${1:-}"
if [ -z "$TOOL" ]; then
  echo "usage: check-cli-grammar.sh TOOL < assertions" >&2
  exit 2
fi

failures=0
checked=0

while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in \#*) continue ;; esac
  case "$line" in
    *::*) ;;
    *)
      echo "malformed assertion (expected 'args :: token'): $line" >&2
      exit 2
      ;;
  esac

  args=$(printf '%s' "${line%%::*}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  token=$(printf '%s' "${line#*::}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -n "$token" ] || continue

  escaped=$(printf '%s' "$token" | sed 's/[][\.^$*+?(){}|\\/]/\\&/g')
  # A flag character on either side means this is a different, longer
  # option rather than the one being asserted.
  pattern="(^|[^A-Za-z0-9_-])${escaped}([^A-Za-z0-9_-]|\$)"

  # shellcheck disable=SC2086
  out=$("$TOOL" $args 2>&1 || true)
  checked=$((checked + 1))

  if printf '%s\n' "$out" | grep -qE -- "$pattern"; then
    echo "ok: $TOOL $args documents '$token'"
  else
    echo "MISSING: $TOOL $args no longer documents '$token'" >&2
    failures=$((failures + 1))
  fi
done

if [ "$checked" -eq 0 ]; then
  echo "no assertions supplied" >&2
  exit 2
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures of $checked grammar assertion(s) failed for $TOOL" >&2
  exit 1
fi

echo "$checked grammar assertion(s) passed for $TOOL"
