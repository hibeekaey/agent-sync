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

`agent` reads and writes files in your home directory (agent configuration
and memory files) and, when `AGENT_SYNC_SYNTHESIZER` is set, pipes memory
content through the command you configure. Memory files can contain private
context: treat the synthesized file, everything `gather` stages, and any
synthesizer transcript as sensitive.
