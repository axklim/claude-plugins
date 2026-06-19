# dev-workflow

A portable dev-workflow toolkit for Claude Code: the branch → PR → merge lifecycle, a
docs-sync step, and the review agents that back them. Language-agnostic — extracted from a
PHP/Symfony project and generalized so it works in any repo.

## What's inside

### Skills (slash commands)

Once installed, these are namespaced under the plugin (`/dev-workflow:premerge`). They are
**explicit-invocation only** — they rewrite history, merge to `main`, or edit docs, so they
never trigger from conversational phrasing.

| Skill | Does |
|-------|------|
| `premerge` | Rebases the current feature branch onto the latest `main`, collapses it to a clean commit (one by default; pass plain-language instructions to split), generates a Conventional Commits message, and opens/syncs the PR. Tags a backup first, so the whole run is reversible. |
| `merge` | Takes a merge-ready branch the last mile: rebase-merges its PR into `main` (after one confirmation, since `main` usually triggers CI/deploy), updates local `main`, deletes the branch, clears the `premerge` backup tags, and prunes. |
| `docs` | Dispatches the `documentation` agent to find doc gaps from recent changes, then **applies** the fixes to README.md / CLAUDE.md / other `*.md` and reports what moved. |

### Agents (subagents)

Namespaced as `dev-workflow:<name>` when dispatched via the Task/Agent tool.

| Agent | Role | Model |
|-------|------|-------|
| `commit-message` | Writes one Conventional Commits message from a diff alone — no conversation context, no trailer/footer. Used by `premerge`. | haiku |
| `documentation` | Finds gaps between code changes and docs (README for humans, CLAUDE.md for agents). Report-only; keeps per-project memory of doc conventions. Used by `docs`. | opus |
| `reviewer` | On-demand code review for correctness bugs, security issues, and over-engineering, ordered by severity. Language-agnostic. | opus |

## How the pieces fit

```
/premerge ──> commit-message agent (writes the message)
          └─> clean, rebased branch + open PR
/merge    ──> lands the PR on main, cleans up
/docs     ──> documentation agent (finds gaps) ──> applies the edits
reviewer  ──> standalone; invoke when you want a review
```

## Notes & assumptions

- **Trunk & merge strategy.** `premerge`/`merge` assume `main` is the protected trunk and the
  project merges by **rebase**. If your repo differs, adjust the default branch name and the
  `gh pr merge` strategy flag (`--squash` / `--merge`) in `skills/merge/SKILL.md`.
- **Tooling.** `merge` (and parts of `premerge`) use the GitHub CLI (`gh`). Make sure it's
  installed and authenticated.
- **Namespacing.** The skills dispatch the bundled agents by their **namespaced** ids
  (`dev-workflow:commit-message`, `dev-workflow:documentation`) — plugin agents don't resolve
  by bare name. If you rename this plugin, update those references in `skills/premerge/SKILL.md`
  and `skills/docs/SKILL.md`.
