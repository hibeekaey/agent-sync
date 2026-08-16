#!/bin/sh
# agent-sync installer: fetches a pinned release asset, verifies its
# checksum, and installs it as `agent`. POSIX sh, macOS and Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/hibeekaey/agent-sync/main/install.sh | sh
#   PREFIX=~/.local sh install.sh
#   AGENT_SYNC_VERSION=v1.5.2 sh install.sh
set -eu

main() {
  REPO="hibeekaey/agent-sync"
  VERSION="${AGENT_SYNC_VERSION:-latest}"
  PREFIX="${PREFIX:-/usr/local}"
  BINDIR="$PREFIX/bin"

  if [ "$VERSION" = "latest" ]; then
    VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" |
      sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$VERSION" ] || {
      echo "install: could not resolve the latest release" >&2
      exit 1
    }
  fi

  base="https://github.com/$REPO/releases/download/$VERSION"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' 0

  echo "installing agent $VERSION to $BINDIR"
  curl -fsSL "$base/agent" -o "$tmp/agent"
  curl -fsSL "$base/SHA256SUMS" -o "$tmp/SHA256SUMS"
  (
    cd "$tmp"
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum -c SHA256SUMS
    else
      shasum -a 256 -c SHA256SUMS
    fi
  ) >/dev/null || {
    echo "install: checksum verification FAILED; not installing" >&2
    exit 1
  }

  chmod +x "$tmp/agent"
  mkdir -p "$BINDIR" 2>/dev/null || true
  if [ -w "$BINDIR" ]; then
    mv "$tmp/agent" "$BINDIR/agent"
  else
    echo "install: $BINDIR is not writable; re-run with PREFIX=~/.local or via sudo" >&2
    exit 1
  fi
  echo "installed: $("$BINDIR/agent" version)"
}

main "$@"
