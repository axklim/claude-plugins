# dev-workflow: local-only repo support (no remote, require `main`/`master`)

**Issue:** [#10](https://github.com/axklim/claude-plugins/issues/10) — adapt `premerge`/`restructure-commits`/`merge` for local-only repos.
**Date:** 2026-06-23
**Status:** Approved design — ready for implementation plan.

## Problem

The `dev-workflow` merge pipeline — `/premerge`, `/restructure-commits`, `/merge` —
hardcodes a GitHub-backed repo: `git fetch origin`, `origin/main` as the rebase base,
`git push --force-with-lease`, and `gh pr create/merge`. On a repo with **no remote**, those
steps have no target. On a repo with **no `main` trunk** (e.g. a fresh `git init` where the
root commit landed on a feature branch because `git checkout -b <feature>` ran before the first
commit), the rebase base and merge target don't exist.

Today the skills correctly halt at their preconditions rather than doing something unsafe, but
the messaging doesn't distinguish these situations and the user is left with no clear path
forward.

## Design overview

Each skill resolves **two independent facts** up front and adapts. This replaces the current
all-or-nothing "must be GitHub-backed" assumption.

### Axis A — trunk base (what to count against / rebase onto / merge into)

The trunk may be named `main` **or** `master`. Resolve it by an ordered probe — prefer `main`
over `master`, and a remote-tracking ref over a local one — taking the first that exists:

1. `origin/main` (after fetch)
2. `origin/master` (after fetch)
3. local `main`
4. local `master`
5. else → **halt at preconditions** with tailored guidance. The pipeline **never creates** a
   trunk — establishing one is the user's call.

The resolved ref is `<base>` and its short name is `<trunk>`; both are used in place of the
hardcoded `main` / `origin/main` throughout the steps below.

### Axis B — remote (whether push and PR happen)

- `git remote` is non-empty → push the branch and open/sync the PR via `gh`. *(today's behavior)*
- else → **local-only**: skip push and skip PR; use the local trunk for base/target.

These are independent: a repo can have a local `main` but no remote (the main local-only case),
a remote but no `main` (treated per Axis A), or neither.

### Detection

Cheap, unambiguous, no network beyond the existing fetch:

- has a remote: `git remote` produces non-empty output (default remote name: `origin`).
- trunk resolution: probe in order with `git rev-parse --verify --quiet <ref>` and take the
  first that resolves — `origin/main`, `origin/master`, `refs/heads/main`, `refs/heads/master`
  (the remote refs only after the fetch). This yields `<base>` and `<trunk>`.

```bash
# Resolve the trunk; prefer main over master, remote over local.
base=""; trunk=""
for ref in origin/main origin/master refs/heads/main refs/heads/master; do
  if git rev-parse --verify --quiet "$ref" >/dev/null; then
    base="$ref"; trunk="${ref##*/}"; break
  fi
done
# base/trunk empty → halt at the precondition with guidance.
```

The resolved mode is always stated in the skill's final summary, so a local-only or
halt outcome is never silent.

### Conventions / scope decisions

- Trunk name is `main` **or** `master`, resolved by the Axis A probe (`main` preferred). If a
  repo somehow has both, the probe deterministically picks `main` (remote before local).
  Honoring an arbitrary `init.defaultBranch` name beyond these two is **out of scope**.
- The remote-exists-but-no-remote-trunk case is handled by Axis A falling through to a local
  trunk (rebase base) while Axis B still pushes + opens a PR against the remote's default
  branch. Not a primary target; documented as a fall-through, not specially built.
- No auto-bootstrap of `main`, no "rootless" squash mode. (An earlier design iteration
  considered creating `main` in `/merge`; that was dropped in favor of the precondition.)

## Per-skill changes

### `restructure-commits` (the core skill)

**Step 1 — preconditions.** Add a third check alongside the existing two:

- *(existing)* must be on a feature branch, not the trunk (`main`/`master`) or detached.
- *(existing)* working tree must be clean.
- **(new) a `main`/`master` trunk must exist** — resolved by the Axis A probe (`origin/main`,
  `origin/master` after the step-2 fetch, or local `main`/`master`). If none resolves, **stop**
  with tailored guidance and do **not** create one:

  > No `main` or `master` trunk found (no remote trunk, no local `main`/`master`).
  > `/restructure-commits` rebases onto the trunk and can't run without it. Create one first,
  > e.g. `git branch main <ref>` (or `git branch -m main` to rename this branch into the
  > trunk), then re-run.

  Note the ordering wrinkle: the remote refs only become checkable after the fetch (step 2),
  and the fetch only runs when a remote exists. So the precondition is evaluated as: *if a
  remote exists, fetch first, then run the full probe; if no remote, probe the local refs only.*

**Step 2 — fetch.** Run `git fetch <remote>` only if a remote exists; otherwise skip.

**Step 3 — backup tag.** Unchanged (local tag).

**Step 4 — count.** `git rev-list --count <base>..HEAD`, where `<base>` is the resolved trunk
from Axis A. `0` → branch matches the trunk; stop and say so.

**Step 5 — build commit(s).** Unchanged mechanics; squash base = `git merge-base <base> HEAD`.

**Step 6 — rebase.** `git rebase <base>` (the resolved trunk ref). Conflict handling unchanged
(stop and hand back).

**Step 7 — push.** Only if a remote exists (`git push --force-with-lease`, or `git push -u`
for a first push). Otherwise skip.

**Step 8 — PR.** Only if a remote exists (`gh pr view/create/edit`). Otherwise skip.

**Summary.** Report the resolved mode, naming the actual `<trunk>`. Local-only example:

> Squashed → 1 commit, rebased onto local `main`. Skipped push + PR (no remote configured).
> `main` not advanced — run `/merge` to integrate.

### `merge`

**Step 1 — identify branch and PR + new precondition.** Capture the branch name first; refuse
if it's the trunk itself (`main`/`master`). Add: **a trunk must exist** — resolve `<base>` /
`<trunk>` via the Axis A probe. If none resolves, stop with the same guidance as
`restructure-commits` (no bootstrap).

**Step 2 — merge.**

- **Remote + open PR** → `gh pr merge <n> --rebase --delete-branch`. *(unchanged)* If no open
  PR for the branch and a remote exists, stop and say so.
- **Local-only (no remote)** →
  ```bash
  git switch <trunk>
  git merge --ff-only <feature>
  git branch -d <feature>
  ```
  The fast-forward is safe because `restructure-commits` already rebased the feature branch
  onto the trunk, so `<trunk>` is an ancestor of the feature tip. If `--ff-only` **fails** (the
  branch wasn't restructured onto the trunk), stop and say: "`<trunk>` can't fast-forward to
  `<feature>` — run `/restructure-commits` first." Never create a merge commit on the trunk here.

**Step 3 — update local trunk.** `git pull --ff-only` only if a remote exists; in local mode
`<trunk>` is already at the feature tip from step 2, so skip.

**Step 4 — clear backup tags.** Unchanged (local tags; applies in both modes).

**Step 5 — prune.** `git fetch --prune` only if a remote exists; otherwise skip.

**Step 6 — report.** Mode-aware: remote path reports PR merged; local path reports `<trunk>`
fast-forwarded and the feature branch deleted locally.

### `premerge`

**Step 1 — preconditions.** Add the **trunk-existence** check (`main`/`master` via the Axis A
probe) to its up-front guards (it already checks not-on-trunk and clean-tree up front
specifically to avoid a half-done run where `docs` commits but the restructure can't finish).
Use the same detection and guidance.
`restructure-commits` re-checks in its own step 1; checking here too just fails fast before the
`docs` pass runs.

**Steps 2–4 — delegation + summary.** Otherwise unchanged: `premerge` adds no git logic, it
chains `docs` then `restructure-commits`. The combined summary surfaces the local-only mode that
`restructure-commits` reports (skipped push/PR), so the user sees it without `premerge`
re-deriving it.

### README

Update `plugins/dev-workflow/README.md`'s lifecycle section to document:

- the trunk precondition shared by all three skills — a `main` **or** `master` branch must
  exist, and the pipeline won't create one,
- local-only behavior: no remote → squash/rebase onto the local trunk, skip push + PR; `/merge`
  fast-forwards the local trunk and deletes the branch.

## Verification

These are markdown skills with no test harness, so verification is walking the commands the
skills specify in throwaway repos. Cover four scenarios:

1. **main + remote (regression):** existing behavior unchanged — fetch, squash, rebase onto
   `origin/main`, force-push, open/sync PR; `/merge` does `gh pr merge`.
2. **main, no remote (local-only):** `/restructure-commits` squashes and rebases onto local
   `main`, skips push + PR; `/merge` fast-forwards local `main` to the feature tip and deletes
   the branch.
3. **master, no remote (trunk-name resolution):** same as scenario 2 but the trunk is
   `master` — confirm the probe resolves `<trunk>=master` and every step targets it.
4. **no trunk (repro):** neither `main` nor `master` exists — all three skills halt at the
   precondition with the tailored guidance and create nothing.

A throwaway-repo setup script for scenarios 2–4 will be included with the implementation to
make the manual walk repeatable.

## Out of scope

- Auto-creating / bootstrapping a trunk.
- Trunk names other than `main` / `master` (e.g. an arbitrary `init.defaultBranch`).
- A dedicated `--local` flag (mode is auto-detected and reported instead).
