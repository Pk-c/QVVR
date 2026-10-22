# Repository safety

This repository contains mod source, build/test scripts, default settings,
installation/removal helpers, licensing notices and maintained documentation.

Keep the following local only:

- `.deps/`: game-derived Unity references, BepInEx, SDKs and binary dependencies.
- `build/`, native/managed `bin/` and `obj/`: packages and generated outputs.
- `artifacts/`: logs, shader dumps, traces, captures and private audit reports.
- Historical device/session notes and machine-specific setup records.
- Saved user configurations, credentials, environment files and signing keys.

The default configuration under `package-assets/` is a clean template, not a
copy of headset settings. Setup requires explicit dependency paths instead of
paths to another local project. Deployment is opt-in, deploy-only and preserves
existing configuration. Diagnostic tools never upload their output automatically.

## Before publishing

Stage an explicit set of source/tool/document paths, then inspect it:

```powershell
git diff --cached --stat
git diff --cached --check
.\tools\check-publication.ps1
```

For a read-only preparation audit before staging, use
`tools/check-publication.ps1 -Mode WorkingTree`. It covers tracked and unignored
untracked public files without touching the index. The default still audits
staged content only; working-tree success does not replace the final staged audit.

The publication check audits staged content against a path/type allowlist and
rejects common secret patterns, private e-mail/home paths, binary/control content
and oversized files. Findings report filenames, never matched secret values.
It is a guardrail, not a guarantee: manually review the staged diff as well.
Use a GitHub noreply identity for new commits when protecting author e-mail.

Do not add dependencies/game files or generated packages to Git history, even
temporarily. Ignoring them after a commit does not remove them from history.
Do not force-push existing history or replace upstream licensing accidentally.
Release candidates have an exact file allowlist and archive audit, separate from
the public source audit. Complete pinned third-party licenses and unmodified
Doorstop source stay under ignored .deps until copied into the generated ZIP.
See release.md. Preparing/verifying these artifacts does not publish a release.
