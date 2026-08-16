# agent-sync on Windows

agent-sync is POSIX sh and is supported on Windows through WSL.

## WSL (supported)

Inside any WSL distribution:

```sh
curl -fsSL https://raw.githubusercontent.com/hibeekaey/agent-sync/main/install.sh | sh
```

Agents running inside WSL (Claude Code, Codex CLI, Gemini CLI, OpenCode,
Goose, and the other CLI tools) keep their config under the WSL home
directory, so detection and sync work exactly as on Linux.

Agents installed on the Windows side (Cursor, Zed, the JetBrains IDEs) keep
their config under the Windows user profile, which agent-sync inside WSL
does not manage. Two options:

- Run the Windows-side agents' WSL integration where available, so their
  config lives in the WSL home.
- Point a target at the Windows profile explicitly by symlinking, e.g.
  `ln -s /mnt/c/Users/<you>/.cursor ~/.cursor` before syncing. Do this
  deliberately; path semantics differ (case sensitivity, line endings).

## Git Bash (untested)

The script is plain POSIX sh and may run under Git Bash, but Windows-native
agents expect profile paths (`%USERPROFILE%`, `%APPDATA%`) that agent-sync
does not currently write. Treat Git Bash as unsupported.

## Native PowerShell port

On the roadmap; contributions welcome. The `targets()` table in `bin/agent`
is the complete specification of what a port needs to write where.
