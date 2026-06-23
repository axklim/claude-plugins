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
3. **`/merge`** — once approved, lands the change on the trunk (`main`/`master`) and cleans up
   the branch.

Skip the docs step with `/premerge no docs`, or reach for `/restructure-commits` directly when
you don't want docs touched at all.

**Local-only repos** (no remote configured) run the same `/premerge → review → /merge` flow:
`/premerge` squashes and rebases onto the local trunk and skips the push/PR, and `/merge`
fast-forwards the local trunk to your branch — no GitHub or `gh` required. See
*Notes & assumptions*.

## What's inside

### Skills (slash commands)

Once installed, these are namespaced under the plugin (`/dev-workflow:restructure-commits`). They are
**explicit-invocation only** — they rewrite history, merge to `main`, or edit docs, so they
never trigger from conversational phrasing.

| Skill | Does |
|-------|------|
| `premerge` | The everyday "make this merge-ready" command: chains `docs` (sync + `docs:` commit), then `restructure-commits` (rebase, squash, push, open/sync PR — or, with no remote, skip push + PR). The front of the **premerge → review → merge** lifecycle. Pass `no docs` to skip the docs pass; any other instruction (e.g. "split into two commits: …") passes through to control commit structure. |
| `restructure-commits` | Rebases the current feature branch onto the latest trunk (`main`/`master`), collapses it to a clean commit (one by default; pass plain-language instructions to split), generates a Conventional Commits message, and opens/syncs the PR (skipped in a local-only repo, leaving a clean rebased branch). Tags a backup first, so the whole run is reversible. The canonical no-docs prepare path. |
| `merge` | Takes a merge-ready branch the last mile: rebase-merges its PR into the trunk (`main`/`master`) — or, in a local-only repo, fast-forwards the local trunk to the branch — updates the trunk, deletes the branch, clears the `restructure-commits` backup tags, and prunes. |
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
                                     then: Review ──> /merge (lands on the trunk, cleans up)

standalone:
  /restructure-commits   ──> commit-message agent ──> clean, rebased branch + open PR
  /docs                  ──> documentation agent (finds gaps) ──> applies edits ──> docs: commit
  /merge                 ──> lands on the trunk, cleans up
  reviewer               ──> invoke when you want a code review
```

*No remote? `restructure-commits` stops at a clean rebased branch and `/merge` fast-forwards the
local trunk — no `gh`, no PR.*

## Notes & assumptions

- **Trunk & merge strategy.** The trunk may be **`main` or `master`** (resolved automatically,
  `main` preferred); all three skills **require** one of them to exist and **never create one** —
  if neither exists they halt and tell you to create it (e.g. `git branch main <ref>`). They
  merge by **rebase**; if your repo uses a different strategy, adjust the `gh pr merge` flag
  (`--squash` / `--merge`) in `skills/merge/SKILL.md`.
- **Local-only repos (no remote).** With no remote configured the lifecycle degrades cleanly:
  `restructure-commits` squashes and rebases onto the **local** trunk and **skips push + PR**;
  `/merge` fast-forwards the local trunk to the branch and deletes it. No GitHub, no `gh`
  required. (`scripts/verify-local-only.sh` exercises these paths.)
- **Tooling.** `merge` (and the push/PR steps of `restructure-commits`) use the GitHub CLI (`gh`)
  **when a remote is configured** — install and authenticate it for remote repos. Local-only
  repos need neither.
- **Namespacing.** The skills dispatch the bundled agents by their **namespaced** ids
  (`dev-workflow:commit-message`, `dev-workflow:documentation`) — plugin agents don't resolve
  by bare name. If you rename this plugin, update those references in `skills/restructure-commits/SKILL.md`
  and `skills/docs/SKILL.md`.
