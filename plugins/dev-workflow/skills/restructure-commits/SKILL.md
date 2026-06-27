---
name: restructure-commits
description: >-
  Prepare the current feature branch to be merged into main — rebase onto the latest main,
  collapse it to a clean commit, generate a Conventional Commits message, and open or sync the
  PR. Runs unattended on sensible defaults (squash to one commit); pass plain-language
  instructions to control the commit structure, e.g. "/restructure-commits split into two commits: …".
  Run this ONLY when the user explicitly invokes /restructure-commits. Never trigger it from conversational
  context or infer it from phrases like "clean up the branch", "squash before merging", or "get
  this ready to merge" — because it rewrites history and force-pushes, it must not run on its
  own. The explicit /restructure-commits invocation is the required go-ahead.
---

# Prepare a branch for merge

Get the current feature branch into a clean, merge-ready state: rebased on the latest `main`,
collapsed to a tidy commit (one by default), with a message and PR that say what the change
does.

**This runs unattended by design.** Everything it does to history — squash, rebase,
force-push — is confined to this feature branch and is recoverable: it tags a backup of the
branch tip before touching anything (step 3), so the pre-run state is always one
`git reset --hard` away, and the file content is never at risk. The worst case is "re-run it."
Running `/restructure-commits` *is* your consent to the rewrite, so it doesn't stop to ask permission for
any of it. It halts only when it genuinely can't proceed safely — a wrong starting state, or a
rebase conflict it must not resolve on your behalf.

**Arguments set the commit structure.** With no arguments it squashes the branch into one
commit. Pass plain-language instructions to do something else — keep the commits as they are,
or split them, e.g. `/restructure-commits split into two commits: everything Claude-Code-related, and the
rest`. Interpret the instruction and shape the commits accordingly; the rest of the flow is
identical.

## Workflow

### 1. Check preconditions — stop if they fail

First resolve the trunk and the remote — the rest of the workflow branches on these. If a
remote exists, run the Step 2 fetch *before* resolving, so the `origin/*` refs are current;
with no remote, probe the local refs only.

```bash
git remote | grep -q . && HAS_REMOTE=1 || HAS_REMOTE=
# Resolve the trunk; prefer main over master, remote over local.
base=""; trunk=""
for ref in origin/main origin/master refs/heads/main refs/heads/master; do
  if git rev-parse --verify --quiet "$ref" >/dev/null; then
    base="$ref"; trunk="${ref##*/}"; break
  fi
done
```

- **A `main`/`master` trunk must exist.** If the probe leaves `base` empty (no `origin/main`,
  `origin/master`, or local `main`/`master`), **stop** — and do **not** create one:

  > No `main` or `master` trunk found. `/restructure-commits` rebases onto the trunk and can't
  > run without it. Create one first, e.g. `git branch main <ref>` (or `git branch -m main` to
  > rename this branch into the trunk), then re-run.

- **Must be on a feature branch, not the trunk.** The trunk is protected; never rebase or
  rewrite it. If the current branch equals `<trunk>` (or `HEAD` is detached), stop and say so.
- **Working tree must be clean.** A rebase can't run over uncommitted changes, and you don't
  want to sweep stray edits into the squash. If `git status --porcelain` is non-empty, stop
  and show what's dirty — let the user commit or stash first.

### 2. Fetch the latest trunk — if there's a remote

```bash
[ -n "$HAS_REMOTE" ] && git fetch origin
```

Fetching changes nothing locally, so do it up front — when there's a remote, the commit count
and the rebase both need the current `origin/<trunk>`. With no remote, skip this; `<base>` is
the local trunk and there is nothing to fetch.

### 3. Snapshot a backup tag

Before touching anything, tag the branch's current tip so the whole run is reversible. The
rebase and squash are recoverable from the reflog anyway, but an explicit tag is easier to find
and outlives reflog expiry:

```bash
git tag -a "restructure-commits-backup/$(git branch --show-current | tr / -)-$(date -u +%Y%m%dT%H%M%SZ)" \
  -m "pre-/restructure-commits snapshot"
```

Keep it **local — don't push it**; the pre-rewrite commits are local objects, so the tag alone
keeps them recoverable. Hold onto the tag name for the final summary. To undo the whole run:
`git reset --hard <tag>` (then force-push again if you'd already pushed). The tags are cheap and
group under `restructure-commits-backup/`; they can be cleared later with
`git tag -l 'restructure-commits-backup/*' | xargs git tag -d`.

### 4. Determine the commit structure

First the count: `git rev-list --count "$base"..HEAD`.

- **0** → nothing to merge; stop and say the branch matches `<trunk>`.
- Otherwise read the structure from the invocation:
  - **No arguments → squash everything into one commit** (the default).
  - **Arguments → follow them** — "keep as they are", or "split into …" with the groups and
    order the user describes.

### 5. Build the merge-ready commit(s)

Collapse the branch to the target structure. This just re-stacks the commits already on the
branch — everything since the merge-base — with a soft reset and a fresh commit: no replay, no
merge, so it can't conflict, regardless of who authored those commits. (Conflicts can only
arise in step 6, where the branch is replayed onto main's newer commits.) Generate each
commit's message with the **`commit-message`** agent (`subagent_type: dev-workflow:commit-message`)
— tell it which diff to describe — and append the footer to every message:

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

- **Squash all (default):** generate the message from the whole branch diff
  (`git diff "$base"...HEAD`), then collapse to the **merge-base** (not `<base>` directly —
  you haven't rebased yet, so that would fold in the trunk's newer commits):

  ```bash
  git reset --soft $(git merge-base "$base" HEAD)
  git commit -F <message-file>
  ```

- **Single commit, no grouping:** `git commit --amend` to reword it with a freshly generated
  message.
- **Keep as-is:** leave the commits and their messages untouched.
- **Split / custom groups:** uncommit to the merge-base, then for each group in order, stage
  its paths and commit with a message the agent generates from *that group's* staged diff:

  ```bash
  git reset $(git merge-base "$base" HEAD)   # uncommit; changes stay in the working tree
  git add <group-1 paths> && git commit -F <msg-1>   # message from: git diff --cached
  git add <group-2 paths> && git commit -F <msg-2>
  ```

  Map the description to paths (e.g. "Claude Code optimization" → `.claude/**`, `CLAUDE.md`).
  Path-level grouping is straightforward; if one file must split across groups, stage hunks
  with `git add -p` and note that you did.

Don't pause for approval — commit, and report the message(s) at the end so the user can amend
if they want.

### 6. Rebase onto the latest trunk

```bash
git rebase "$base"
```

Because you collapsed first, this usually replays a single commit, so conflicts surface in one
pass. If the rebase hits **conflicts, stop immediately** and hand back with the conflicting
files — resolving someone's merge conflicts unattended is how you silently corrupt their
intent; don't `--skip` or guess. Once the user resolves and runs `git rebase --continue`, the
push and PR steps remain (they can re-invoke `/restructure-commits` to finish).

### 7. Push the rewritten branch — if there's a remote

**No remote (`$HAS_REMOTE` empty) → skip this step and Step 8 entirely.** There's nowhere to
push and no PR to open; note it in the summary (Step 8 covers the wording).

With a remote, the rewrite changed commit SHAs, so push to update it (and any open PR). No
confirmation — `--force-with-lease` is the safeguard:

```bash
git push --force-with-lease     # branch already on the remote
git push -u origin HEAD          # first push of a branch that was never pushed
```

If `--force-with-lease` is **rejected**, stop and surface it — that means someone else pushed
to the branch, which is the one case that genuinely warrants a human look.

### 8. Open or sync the PR

**Local-only (no remote) → skip this step.** With no remote there's no PR; the branch is now a
clean, rebased commit on top of the local `<trunk>`. Move to the summary.

The description is the commit message (single commit) or a short branch summary from the agent
(multiple commits), plus the footer.

**Format the description as GitHub Markdown — don't hard-wrap it.** Commit bodies are wrapped at
~72 columns for terminal `git log`, but a PR description is rendered as Markdown, where those
hard breaks become ragged mid-paragraph wrapping. So when you reuse a single commit's message as
the PR body, **reflow it first** — join each wrapped paragraph back into one line and let GitHub
soft-wrap; write multi-commit summaries unwrapped for the same reason. (The subject/title is
short either way, so it's unaffected.)

Then, with `gh pr view --json number,state,title`:

- **PR already open:** apply the description with `gh pr edit`, keeping the title in sync with
  the commit subject.
- **No PR open:** open one with `gh pr create` — title = the commit subject, body = the
  description.

Neither asks for confirmation; opening/syncing the PR is the point of getting merge-ready.

## Notes

- Unattended by design — it stops only on a bad starting state or a rebase conflict. So **end
  with a summary** that names the resolved `<trunk>` and the mode:
  - **With a remote:** the backup tag (recovery point), the commit message(s), the push result,
    and the PR link, so the user can review, recover, or amend as needed.
  - **Local-only (no remote):** the backup tag, the commit message(s), and a note that push and
    PR were skipped because no remote is configured — e.g. *"Squashed → 1 commit, rebased onto
    local `main`. Skipped push + PR (no remote). `main` not advanced — run `/merge` to
    integrate."*
- Hand the branch back **merge-ready** — `/merge` takes it from there: it merges the PR
  (squash by default) and cleans up the branch.
- This skill resolves the trunk automatically (`main` or `master`, remote preferred over local)
  and squashes the branch to a clean commit; `/merge` then squash-merges that PR by default. If
  your project uses a different trunk name or merge strategy, adjust steps 1–8 and the paired
  `/merge` skill accordingly.
