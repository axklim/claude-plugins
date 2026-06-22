# dev-workflow

A portable dev-workflow toolkit for Claude Code: the branch → PR → merge lifecycle, a
docs-sync step, and the review agents that back them. Language-agnostic — extracted from a
PHP/Symfony project and generalized so it works in any repo.

## Quick start

The everyday flow — three steps from "code's done" to "merged":

```
/premerge  →  review  →  /merge
```

1. **`/premerge`** — on your feature branch: syncs docs, squashes to a clean commit, pushes,
   and opens the PR. One command, branch is now merge-ready.
2. **review** — look over the PR on GitHub (run the `reviewer` agent first if you want a second
   pair of eyes).
3. **`/merge`** — once approved, lands the PR on `main` and cleans up the branch.

Skip the docs step with `/premerge no docs`, or reach for `/restructure-commits` directly when
you don't want docs touched at all.

## What's inside

### Skills (slash commands)

Once installed, these are namespaced under the plugin (`/dev-workflow:restructure-commits`). They are
**explicit-invocation only** — they rewrite history, merge to `main`, or edit docs, so they
never trigger from conversational phrasing.

| Skill | Does |
|-------|------|
| `premerge` | The everyday "make this merge-ready" command: chains `docs` (sync + `docs:` commit), then `restructure-commits` (rebase, squash, push, open/sync PR). The front of the **premerge → review → merge** lifecycle. Pass `no docs` to skip the docs pass; any other instruction (e.g. "split into two commits: …") passes through to control commit structure. |
| `restructure-commits` | Rebases the current feature branch onto the latest `main`, collapses it to a clean commit (one by default; pass plain-language instructions to split), generates a Conventional Commits message, and opens/syncs the PR. Tags a backup first, so the whole run is reversible. The canonical no-docs prepare path. |
| `merge` | Takes a merge-ready branch the last mile: rebase-merges its PR into `main` (after one confirmation, since `main` usually triggers CI/deploy), updates local `main`, deletes the branch, clears the `restructure-commits` backup tags, and prunes. |
| `docs` | Dispatches the `documentation` agent to find doc gaps from recent changes, **applies** the fixes to README.md / CLAUDE.md / other `*.md`, and **commits** them as a single `docs:` commit (no push). Returns the tree to clean so the docs can ride along into a later `/restructure-commits`. |

### Agents (subagents)

Namespaced as `dev-workflow:<name>` when dispatched via the Task/Agent tool.

| Agent | Role | Model |
|-------|------|-------|
| `commit-message` | Writes one Conventional Commits message from a diff alone — no conversation context, no trailer/footer. Used by `restructure-commits`. | haiku |
| `documentation` | Finds gaps between code changes and docs (README for humans, CLAUDE.md for agents). Report-only; keeps per-project memory of doc conventions. Used by `docs`. | opus |
| `reviewer` | On-demand code review for correctness bugs, security issues, and over-engineering, ordered by severity. Language-agnostic. | opus |

## How the pieces fit

```
/premerge ┬─> /docs                (sync docs ──> docs: commit)   ── skip with "no docs"
          └─> /restructure-commits  (rebase, squash, push, open PR)
                                     then: Review ──> /merge (lands on main, cleans up)

standalone:
  /restructure-commits   ──> commit-message agent ──> clean, rebased branch + open PR
  /docs                  ──> documentation agent (finds gaps) ──> applies edits ──> docs: commit
  /merge                 ──> lands the PR on main, cleans up
  reviewer               ──> invoke when you want a code review
```

## Notes & assumptions

- **Trunk & merge strategy.** `restructure-commits`/`merge` assume `main` is the protected trunk and the
  project merges by **rebase**. If your repo differs, adjust the default branch name and the
  `gh pr merge` strategy flag (`--squash` / `--merge`) in `skills/merge/SKILL.md`.
- **Tooling.** `merge` (and parts of `restructure-commits`) use the GitHub CLI (`gh`). Make sure it's
  installed and authenticated.
- **Namespacing.** The skills dispatch the bundled agents by their **namespaced** ids
  (`dev-workflow:commit-message`, `dev-workflow:documentation`) — plugin agents don't resolve
  by bare name. If you rename this plugin, update those references in `skills/restructure-commits/SKILL.md`
  and `skills/docs/SKILL.md`.
