---
name: merge
description: >-
  Merge the current feature branch's PR into main (squash by default; override with `rebase`/`merge`)
  and clean up — update main,
  delete the branch (local + remote), clear the /restructure-commits backup tags, and prune. Run this ONLY
  when the user explicitly invokes /merge. Never trigger it from conversational context or infer
  it from phrases like "that's ready", "ship it", or "merge this" — because it merges into main
  and deletes branches, it must not run on its own. The explicit /merge invocation is the
  required go-ahead.
---

# Merge the branch and clean up

Take a merge-ready branch (typically straight after `/restructure-commits`) the last mile: merge its
PR into `main` — **squash by default**, or `rebase` / `merge` if you pass that argument — then return
the repo to a clean baseline.

**GitHub is the gatekeeper for whether a PR *can* merge** — branch protection, required checks,
required reviews, conflicts. This skill doesn't re-implement those checks; it attempts the merge
and respects GitHub's verdict (if GitHub refuses, it stops and surfaces why). It runs
**unattended**: invoking `/merge` is your go-ahead, and the PR's own approval/branch-protection
state is the human checkpoint — so it doesn't ask again before merging. A push to `main` may
trigger CI (a release build, an image push, a deploy); that's expected, and GitHub's gate already
governs whether the merge is allowed at all.

## Arguments

One optional token selects the merge strategy (passed straight to `gh pr merge`). With no argument
it **squashes** — the new default:

| Invocation | Strategy |
|---|---|
| `/merge` | `--squash` (default) |
| `/merge squash` | `--squash` (explicit) |
| `/merge rebase` | `--rebase` — land the branch's commits verbatim |
| `/merge merge` | `--merge` — a merge commit |

Match the first token case-insensitively against `squash` / `rebase` / `merge`; anything empty or
unrecognized falls back to `squash`. The strategy governs the remote/PR path only. In a
**local-only repo (no remote)** there's no `gh pr merge` to apply a strategy to — integration is a
fast-forward — so passing an explicit strategy token there is an error: `/merge` stops and redirects
to the local flow (see Step 2's gate). Bare `/merge` (no token) still fast-forwards locally. Name
the resolved strategy in the final report so the choice is never silent.

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
[ -n "$HAS_REMOTE" ] && gh pr view --json number,state,title,url,body
```

With a remote and **no open PR** for the branch, stop and say so — there's nothing to merge.
(With no remote there is no PR; Step 2 takes the local path.)

### 2. Merge — PR (remote) or fast-forward (local-only)

**Local-only (no remote) → fast-forward the trunk locally and delete the branch.**

**First, gate on an explicit strategy.** A strategy (`squash` / `rebase` / `merge`) is a
`gh pr merge` concept, and there's no PR here to apply one to. So if the user passed an explicit
strategy token *and* there's no remote, **stop** — don't fast-forward, and don't try to reproduce
the strategy locally (that's `/restructure-commits`' job):

> `/merge <strategy>` selects a PR-merge strategy, but this repo has no remote/PR. Local repos
> integrate by fast-forward. Shape the commits with `/premerge` (or `/restructure-commits`), then
> run plain `/merge` — it fast-forwards the trunk to the branch.

With **no token** (bare `/merge`), proceed. The fast-forward is safe because `/restructure-commits`
already rebased `<feature>` onto the trunk, so `<trunk>` is an ancestor of the feature tip — the
merge is a pure fast-forward, never a merge commit:

```bash
git switch "$trunk"
git merge --ff-only "$feature"
git branch -d "$feature"
```

If `--ff-only` is **rejected**, stop — note that the `git switch` already moved you onto
`<trunk>`: *"`<trunk>` can't fast-forward to `<feature>` (you're now on `<trunk>`) — switch
back with `git switch <feature>` and run `/restructure-commits` first."* Nothing was changed,
so there's no cleanup; once restructured, re-run `/merge`.

**With a remote → merge the PR.** Resolve the strategy from the argument (see Arguments) —
`squash` by default, else `rebase` / `merge`. Merge straight away — **no confirmation prompt**.
The `/merge` invocation is the go-ahead, and the PR's approval/branch-protection state is GitHub's
call, so don't re-ask before merging.

**For the default `squash`, the squash commit reuses the PR's own title and body** so the trunk
history stays as clean as a rebase-merge would. The PR title is always present; only the body can
be missing. If the PR body (from Step 1's `…,body`) is **empty**, generate one first rather than
let GitHub fall back to its commit-list default — and **never regenerate the title**:

1. Dispatch the **`commit-message`** agent (`subagent_type: dev-workflow:commit-message`) on the
   branch diff `git diff "$base"...HEAD`. Use its **entire returned message verbatim as the PR
   body** — the agent already emits a complete Conventional Commits message (subject line, plus
   body paragraphs when warranted); don't strip or reformat it.
2. Append the footer:

   ```
   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   ```
3. Write it onto the PR so the record matches the merge commit:

   ```bash
   gh pr edit <n> --body "<generated body>"
   ```

Then merge by the resolved strategy:

```bash
# squash (default) — PR body now guaranteed non-empty
gh pr merge <n> --squash --subject "<pr title>" --body "<pr body>" --delete-branch

# rebase — land the branch's commits verbatim (no --subject/--body)
gh pr merge <n> --rebase --delete-branch

# merge — a merge commit
gh pr merge <n> --merge --delete-branch
```

- **Squash (default)** collapses the branch to one commit on the trunk no matter how many commits
  it carries, so `/merge` no longer needs the branch pre-squashed — this is what makes merging
  without `/premerge` land cleanly. `--rebase` instead lands `/restructure-commits`'s clean commits
  verbatim; `--merge` makes a merge commit.
- The squash `--subject` is the PR title; GitHub may append the PR number `(#N)` to it (confirm in
  your setup — append `(#<n>)` to `--subject` yourself only if it doesn't).
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
- **With a remote:** PR merged (name the resolved strategy — squash / rebase / merge), `<trunk>`
  updated, branch deleted (local + remote), backup tags cleared.
- **Local-only:** `<trunk>` fast-forwarded to the feature tip, feature branch deleted locally,
  backup tags cleared (no PR / remote involved).

## Notes

- This is the last step of the lifecycle: `/premerge` (or `/restructure-commits`) makes a branch
  merge-ready, `/merge` lands it and cleans up.
- The trunk is only ever fast-forwarded here — never rewritten or committed to directly.
- This skill resolves the trunk automatically (`main` or `master`) and merges via **squash by
  default** — pass `rebase` or `merge` to override per-merge. To change the default for your
  project, adjust the strategy resolution in Step 2.
