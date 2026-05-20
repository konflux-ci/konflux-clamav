# Konflux ClamAV AI Skills

Skills for the **konflux-clamav** repository: a hermetic Konflux image that packages ClamAV virus definitions, `clamd`, and supporting tools for the platform `clamav-scan` task.

Tool-agnostic content lives under `skills/`. Symlink into your agent (see below).

## Skills

| Skill | Use when |
|-------|----------|
| [ci-pipeline-debugging](ci-pipeline-debugging/SKILL.md) | Tekton build or scan failures, task order, integration self-test |
| [hermetic-build-deps](hermetic-build-deps/SKILL.md) | RPMs, lockfiles, prefetch script, multi-arch `oc`, `clamav-db/` |
| [pr-definition-of-done](pr-definition-of-done/SKILL.md) | Opening or reviewing a PR, CI check failures |
| [daily-db-update](daily-db-update/SKILL.md) | Stale signatures, freshclam failures, push pipeline scheduling |

## Claude Code

```
.claude/skills/ci-pipeline-debugging -> ../../skills/ci-pipeline-debugging
.claude/skills/hermetic-build-deps -> ../../skills/hermetic-build-deps
.claude/skills/pr-definition-of-done -> ../../skills/pr-definition-of-done
.claude/skills/daily-db-update -> ../../skills/daily-db-update
```

## Cursor

```bash
mkdir -p .cursor/skills
for s in ci-pipeline-debugging hermetic-build-deps pr-definition-of-done daily-db-update; do
  ln -s "../../skills/$s" ".cursor/skills/$s"
done
```

## Other agents

```bash
mk dir -p agents/skills
for s in ci-pipeline-debugging hermetic-build-deps pr-definition-of-done daily-db-update; do
  ln -s "../../skills/$s" ".agents/skills/$s"
done
```
