---
name: merge
description: >-
  Merge the current feature branch's PR into main (rebase-merge) and clean up — update main,
  delete the branch (local + remote), clear the /premerge backup tags, and prune. Run this ONLY
  when the user explicitly invokes /merge. Never trigger it from conversational context or infer
  it from phrases like "that's ready", "ship it", or "merge this" — because it merges into main
  and deletes branches, it must not run on its own. The explicit /merge invocation is the
  required go-ahead.
---

# Merge the branch and clean up

Take a merge-ready branch (typically straight after `/premerge`) the last mile: rebase-merge its
PR into `main`, then return the repo to a clean baseline.

**GitHub is the gatekeeper for whether a PR *can* merge** — branch protection, required checks,
conflicts. This skill doesn't re-implement those checks; it attempts the merge and respects
GitHub's verdict (if GitHub refuses, it stops and surfaces why). What it adds is **one
confirmation before the merge**, because a push to `main` typically triggers CI (a release
build, an image push, a deploy), so the merge reaches beyond the repo.

## Workflow

### 1. Identify the branch and its PR

Default to the current branch (or the one the user named); capture the name *before* anything
switches it. Refuse if it's `main`. Find the open PR:

```bash
gh pr view --json number,state,title,url
```

If there's no open PR for the branch, stop and say so — there's nothing to merge.

### 2. Merge the PR — confirm first

Merging changes the protected `main` branch and usually triggers a release build or deploy, so
**confirm with the user before merging** (and that the branch is deleted as part of it). Then:

```bash
gh pr merge <n> --rebase --delete-branch
```

- **Rebase-merge** lands the clean commits `/premerge` produced directly on `main`, with no
  merge commit. This pairs with `/premerge`, which already rebased the branch onto the latest
  `main`. If your project squashes or uses merge commits instead, swap `--rebase` for
  `--squash` / `--merge`.
- `--delete-branch` removes the branch on the remote and locally (gh switches off it first).
- If GitHub **rejects** the merge — failing required checks, conflicts, branch-protection rules —
  stop and surface the reason. Don't reach for `--admin` or otherwise override GitHub's gate;
  whether to bypass it is the user's separate call.

### 3. Update local main

```bash
git switch main        # usually already here — gh moved off the deleted branch
git pull --ff-only
```

`--ff-only` keeps `main` a clean fast-forward; if it can't, stop and surface that rather than
making a merge commit on a protected branch.

### 4. Clear the branch's /premerge backup tags

`/premerge` left a local `premerge-backup/<branch>-<timestamp>` tag (branch slashes turned to
dashes). Now that the branch is merged, those snapshots are obsolete — delete the ones for
*this* branch (the name captured in step 1), anchoring the glob on the timestamp's leading digit
so a sibling branch's tags aren't caught:

```bash
prefix="premerge-backup/$(printf '%s' '<branch>' | tr / -)-"
tags=$(git tag -l "${prefix}[0-9]*")
[ -n "$tags" ] && git tag -d $tags
```

### 5. Prune stale references

```bash
git fetch --prune
```

Drops remote-tracking refs for branches deleted on the remote, so `git branch -a` stays honest.

### 6. Report

Summarize: PR merged (rebase), `main` updated, branch deleted (local + remote), backup tags
cleared.

## Notes

- This is the last step of the lifecycle: `/premerge` makes a branch merge-ready, `/merge` lands
  it and cleans up.
- `main` is only ever fast-forwarded here — never rewritten or committed to directly.
- This skill assumes `main` is the protected trunk and the project merges via rebase. Adjust the
  default branch name and the `gh pr merge` strategy flag if your project differs.
