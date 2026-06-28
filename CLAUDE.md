# Project conventions

Monorepo of Claude Code plugins under `plugins/<name>/`. Each plugin is self-contained and
versioned in `plugins/<name>/.claude-plugin/plugin.json`.

## Placing new skills and agents

Not every skill or agent justifies its own plugin. `plugins/common/` is the catch-all home for
items that don't yet belong to a focused plugin — park new skills/agents there instead of
spinning up a single-purpose plugin.

Before adding an item to `common`, check what's already parked there: if the new item plus some
existing ones form a coherent group (e.g. several advisory skills, or several review agents),
extract that group into a dedicated, well-named plugin rather than letting `common` sprawl.
`common` is a staging area, not a permanent dumping ground — graduating clusters out is the
whole point. Whenever you add a new plugin, register it in both `.claude-plugin/marketplace.json`
and the README plugin table.

## Version bumping

When you change a plugin, bump its `version` in `plugins/<name>/.claude-plugin/plugin.json` as
part of the same change — don't leave it for a follow-up. Map the change's Conventional Commit
type to semver:

- `feat` → minor (e.g. `0.3.0` → `0.4.0`)
- `fix` / `docs` / `refactor` / `chore` → patch (e.g. `0.3.0` → `0.3.1`)
- a breaking change → major

Repo-level changes that touch no `plugins/<name>/` tree (root docs, meta) need no plugin bump.
