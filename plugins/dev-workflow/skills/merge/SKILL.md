---
name: merge
description: >-
  Merge the current feature branch's PR into main (rebase-merge) and clean up — update main,
  delete the branch (local + remote), clear the /restructure-commits backup tags, and prune. Run this ONLY
  when the user explicitly invokes /merge. Never trigger it from conversational context or infer
  it from phrases like "that's ready", "ship it", or "merge this" — because it merges into main
  and deletes branches, it must not run on its own. The explicit /merge invocation is the
  required go-ahead.
---

# Merge the branch and clean up

Take a merge-ready branch (typically straight after `/restructure-commits`) the last mile: rebase-merge its
PR into `main`, then return the repo to a clean baseline.

**GitHub is the gatekeeper for whether a PR *can* merge** — branch protection, required checks,
required reviews, conflicts. This skill doesn't re-implement those checks; it attempts the merge
and respects GitHub's verdict (if GitHub refuses, it stops and surfaces why). It runs
**unattended**: invoking `/merge` is your go-ahead, and the PR's own approval/branch-protection
state is the human checkpoint — so it doesn't ask again before merging. A push to `main` may
trigger CI (a release build, an image push, a deploy); that's expected, and GitHub's gate already
governs whether the merge is allowed at all.

## Workflow

### 1. Identify the branch, the trunk, and the PR

Default to the current branch (or the one the user named); capture the name *before* anything
switches it — call it `<feature>`. Then resolve the trunk and the remote:

```bash
feature=$(git branch --show-current)
git remote | grep -q . && HAS_REMOTE=1 || HAS_REMOTE=
[ -n "$HAS_REMOTE" ] && git fetch origin --quiet
base=""; trunk=""
for ref in origin/main origin/master refs/heads/main refs/heads/master; do
  if git rev-parse --verify --quiet "$ref" >/dev/null; then
    base="$ref"; trunk="${ref##*/}"; break
  fi
done
```

- **A `main`/`master` trunk must exist.** If `base` is empty, stop — and do **not** create one:

  > No `main` or `master` trunk found. `/merge` integrates into the trunk and can't run without
  > it. Create one first, e.g. `git branch main <ref>`, then re-run.

- **Refuse if `<feature>` is the trunk itself** (`main`/`master`) — there's nothing to merge.

Then find the PR **only when there's a remote**:

```bash
[ -n "$HAS_REMOTE" ] && gh pr view --json number,state,title,url
```

With a remote and **no open PR** for the branch, stop and say so — there's nothing to merge.
(With no remote there is no PR; Step 2 takes the local path.)

### 2. Merge — PR (remote) or fast-forward (local-only)

**Local-only (no remote) → fast-forward the trunk locally and delete the branch.** This is
safe because `/restructure-commits` already rebased `<feature>` onto the trunk, so `<trunk>` is
an ancestor of the feature tip — the merge is a pure fast-forward, never a merge commit:

```bash
git switch "$trunk"
git merge --ff-only "$feature"
git branch -d "$feature"
```

If `--ff-only` is **rejected**, stop — note that the `git switch` already moved you onto
`<trunk>`: *"`<trunk>` can't fast-forward to `<feature>` (you're now on `<trunk>`) — switch
back with `git switch <feature>` and run `/restructure-commits` first."* Nothing was changed,
so there's no cleanup; once restructured, re-run `/merge`.

**With a remote → merge the PR.** Merge straight away — **no confirmation prompt**. The
`/merge` invocation is the go-ahead, and the PR's approval/branch-protection state is GitHub's
call, so don't re-ask before merging:

```bash
gh pr merge <n> --rebase --delete-branch
```

- **Rebase-merge** lands the clean commits `/restructure-commits` produced directly on the trunk,
  with no merge commit. This pairs with `/restructure-commits`, which already rebased the branch
  onto the latest trunk. If your project squashes or uses merge commits instead, swap `--rebase`
  for `--squash` / `--merge`.
- `--delete-branch` removes the branch on the remote and locally (gh switches off it first).
- If GitHub **rejects** the merge — failing required checks, conflicts, branch-protection rules —
  stop and surface the reason. Don't reach for `--admin` or otherwise override GitHub's gate;
  whether to bypass it is the user's separate call.

### 3. Update local trunk — if there's a remote

In local-only mode this is already done: Step 2 fast-forwarded `<trunk>` and you're on it, so
skip. With a remote:

```bash
git switch "$trunk"     # usually already here — gh moved off the deleted branch
git pull --ff-only
```

`--ff-only` keeps the trunk a clean fast-forward; if it can't, stop and surface that rather than
making a merge commit on a protected branch.

### 4. Clear the branch's /restructure-commits backup tags

`/restructure-commits` left a local `restructure-commits-backup/<branch>-<timestamp>` tag (branch slashes turned to
dashes). Now that the branch is merged, those snapshots are obsolete — delete the ones for
*this* branch (the name captured in step 1), anchoring the glob on the timestamp's leading digit
so a sibling branch's tags aren't caught:

```bash
prefix="restructure-commits-backup/$(printf '%s' '<branch>' | tr / -)-"
tags=$(git tag -l "${prefix}[0-9]*")
[ -n "$tags" ] && git tag -d $tags
```

### 5. Prune stale references — if there's a remote

```bash
[ -n "$HAS_REMOTE" ] && git fetch --prune
```

Drops remote-tracking refs for branches deleted on the remote, so `git branch -a` stays honest.
With no remote there's nothing to prune.

### 6. Report

Summarize, naming the resolved `<trunk>` and the mode:
- **With a remote:** PR merged (rebase), `<trunk>` updated, branch deleted (local + remote),
  backup tags cleared.
- **Local-only:** `<trunk>` fast-forwarded to the feature tip, feature branch deleted locally,
  backup tags cleared (no PR / remote involved).

## Notes

- This is the last step of the lifecycle: `/premerge` (or `/restructure-commits`) makes a branch
  merge-ready, `/merge` lands it and cleans up.
- The trunk is only ever fast-forwarded here — never rewritten or committed to directly.
- This skill resolves the trunk automatically (`main` or `master`) and merges via rebase. If your
  project uses a different trunk name or merge strategy, adjust the `gh pr merge` strategy flag
  (`--squash` / `--merge`).
