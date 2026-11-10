# Project constraints

- All compilation, project execution, tests and build validation must run exclusively on GitHub-hosted Actions runners.
- Never run project code, builds or tests or install build dependencies on the current server.
- Maintain source via GitHub APIs; no local checkout or build cache.
- Never publish third-party IPA files, Apple credentials, decryption material or signing identities.
- Report CI compilation separately from actual X device compatibility.
