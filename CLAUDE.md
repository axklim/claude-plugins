# Project conventions

Monorepo of Claude Code plugins under `plugins/<name>/`. Each plugin is self-contained and
versioned in `plugins/<name>/.claude-plugin/plugin.json`.

## Version bumping

When you change a plugin, bump its `version` in `plugins/<name>/.claude-plugin/plugin.json` as
part of the same change — don't leave it for a follow-up. Map the change's Conventional Commit
type to semver:

- `feat` → minor (e.g. `0.3.0` → `0.4.0`)
- `fix` / `docs` / `refactor` / `chore` → patch (e.g. `0.3.0` → `0.3.1`)
- a breaking change → major

Repo-level changes that touch no `plugins/<name>/` tree (root docs, meta) need no plugin bump.
