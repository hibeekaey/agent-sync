# Security Policy

## Supported Versions

Security fixes are applied to the `main` branch and shipped in the next
release. Only the latest release is supported.

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Report privately using GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
through this repository's **Security → Report a vulnerability** tab.

You should receive a response within a few days. Please include reproduction
steps and the impact you believe the issue has.

## Scope notes

`agent` reads and writes agent configuration, memory, MCP and skill files in
your home directory. Its default `auto` synthesis mode sends the synthesized
memory document to your configured Claude Code account, then Codex if Claude
is unavailable or fails. Select `--synthesizer deterministic` to keep memory
out of model calls. A custom `AGENT_SYNC_SYNTHESIZER` command receives the
same document on standard input.

Memory files can contain private context. Treat the synthesized file,
everything `gather` stages, and synthesizer input or output as sensitive.
MCP registry specifications can contain environment values and HTTP headers;
they are stored with private permissions, but `agent mcp snippet` prints them
for manual pasting. Do not publish MCP state or snippet output.

Memory-pack archives are untrusted input. agent-sync rejects a selected pack
subdirectory unless its resolved physical path remains inside the downloaded
repository, and it never follows Markdown file symlinks. Skills are copied
only into configured user-scope directories; unmanaged same-name collisions
are refused rather than overwritten.
