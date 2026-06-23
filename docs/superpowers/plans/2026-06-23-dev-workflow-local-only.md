# dev-workflow local-only repo support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/premerge`, `/restructure-commits`, and `/merge` work on repos with no remote and/or a `master` (not `main`) trunk — degrading to a local squash/rebase/fast-forward flow — and halt with clear guidance when no trunk exists, instead of stalling confusingly.

**Architecture:** These three "skills" are **prose Markdown files** (`SKILL.md`) that an agent reads and executes step-by-step — there is no compiled code and no unit-test harness. Each skill gains a small, identical **trunk-resolution** bash snippet and two-axis branching (trunk base: `origin/main`→`origin/master`→local `main`→local `master`→halt; remote: present→push/PR, absent→local-only). The mechanical git recipes (resolve / squash+rebase / fast-forward-merge / halt-on-no-trunk) are covered by one committed shell harness that builds throwaway repos and asserts outcomes; the prose edits are verified by reading them against that harness's recipe.

**Tech Stack:** Markdown (skill instructions), Bash + git + `gh` (the commands the skills run), no test framework.

## Global Constraints

Copied verbatim from `docs/superpowers/specs/2026-06-23-dev-workflow-local-only-design.md`. Every task's requirements implicitly include these:

- **Trunk is `main` OR `master`**, resolved by an ordered probe taking the first ref that exists: `origin/main`, `origin/master`, `refs/heads/main`, `refs/heads/master`. Prefer `main` over `master`, remote over local. The resolved ref is `<base>`, its short name is `<trunk>`.
- **Never create a trunk.** If the probe resolves nothing, **halt** with tailored guidance; establishing a trunk is the user's call. No auto-bootstrap, no "rootless" squash mode.
- **Two independent axes**, resolved up front per skill: trunk base (above) and remote presence (`git remote` non-empty → push + PR; empty → local-only: skip push, skip PR).
- **Always report the resolved mode** in the skill's final summary, naming the actual `<trunk>` — a local-only or halt outcome is never silent.
- **Default remote name is `origin`** (unchanged from today; not generalized).
- **Out of scope:** auto-creating a trunk; trunk names other than `main`/`master`; a `--local` flag.
- The canonical trunk-resolution snippet (use this exact text wherever the snippet appears):

  ```bash
  # Resolve the trunk; prefer main over master, remote over local.
  base=""; trunk=""
  for ref in origin/main origin/master refs/heads/main refs/heads/master; do
    if git rev-parse --verify --quiet "$ref" >/dev/null; then
      base="$ref"; trunk="${ref##*/}"; break
    fi
  done
  # base/trunk empty → halt at the precondition with guidance (do NOT create a trunk).
  ```

---

## File Structure

| File | Change | Responsibility |
|------|--------|----------------|
| `plugins/dev-workflow/scripts/verify-local-only.sh` | **Create** | Executable regression harness: builds throwaway repos for the local-only scenarios and asserts the documented git recipes produce the right state. The one automated check for this change. |
| `plugins/dev-workflow/skills/restructure-commits/SKILL.md` | Modify | Core skill: trunk resolution, new trunk precondition, gate fetch/push/PR on remote, rebase onto `<base>`, mode-aware summary. |
| `plugins/dev-workflow/skills/merge/SKILL.md` | Modify | Add trunk precondition; add local-only merge path (switch `<trunk>`, ff-only, delete branch); gate prune/pull on remote. |
| `plugins/dev-workflow/skills/premerge/SKILL.md` | Modify | Add the trunk-existence precondition to its up-front guards; surface local-only mode in the summary. |
| `plugins/dev-workflow/README.md` | Modify | Document the trunk precondition and local-only behavior in the "Compatibility & assumptions" note. |
| `plugins/dev-workflow/.claude-plugin/plugin.json` | Modify | Version bump `0.2.1` → `0.3.0` (new feature). |

Tasks are ordered so the harness (Task 1) exists before the skill edits it backstops. Task 1 also doubles as the executable definition of the local recipes the prose must match.

---

## Task 1: Verification harness

**Files:**
- Create: `plugins/dev-workflow/scripts/verify-local-only.sh`

**Interfaces:**
- Produces: a standalone script, run as `bash plugins/dev-workflow/scripts/verify-local-only.sh`. Exits `0` if all checks pass, non-zero otherwise. Defines, in one place, the exact `resolve_trunk` snippet and the local-only restructure/merge recipes that Tasks 2–3 transcribe into prose. No arguments, no network, no `gh` (local git only). Cleans up its temp dirs.

- [ ] **Step 1: Write the harness script**

Create `plugins/dev-workflow/scripts/verify-local-only.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# Regression harness for dev-workflow local-only support (issue #10).
# Verifies the git recipes the local-only skill paths document. No remote, no gh.
set -u

pass=0; fail=0
check() { # check "label" <command...>
  local label="$1"; shift
  if "$@"; then echo "PASS: $label"; pass=$((pass+1));
  else echo "FAIL: $label"; fail=$((fail+1)); fi
}

# The canonical trunk-resolution snippet (must match the skills verbatim in spirit).
resolve_trunk() {
  base=""; trunk=""
  for ref in origin/main origin/master refs/heads/main refs/heads/master; do
    if git rev-parse --verify --quiet "$ref" >/dev/null; then
      base="$ref"; trunk="${ref##*/}"; break
    fi
  done
}

# Build a repo whose trunk is $2, with a feature branch 3 commits ahead. No remote.
setup_repo() { # setup_repo <dir> <trunk-name>
  local dir="$1" trunkname="$2"
  git init -q -b "$trunkname" "$dir"
  ( cd "$dir"
    git config user.email t@example.com; git config user.name tester
    printf 'base\n' > f.txt; git add f.txt; git commit -qm "init"
    git checkout -q -b feature
    printf 'a\n' >> f.txt; git commit -qam "wip a"
    printf 'b\n' >> f.txt; git commit -qam "wip b"
    printf 'c\n' >> f.txt; git commit -qam "wip c"
  )
}

# NOTE: the per-scenario work must NOT run inside a ( … ) subshell — `check`
# increments pass/fail, and a subshell's increments would be lost. Use cd + cd back.
root=$(pwd)

# --- Scenarios A (trunk=main) and B (trunk=master): no remote, trunk exists ---
for trunkname in main master; do
  d=$(mktemp -d)
  setup_repo "$d" "$trunkname"
  cd "$d"

  resolve_trunk
  check "[$trunkname] resolve_trunk picks local $trunkname" test "$trunk" = "$trunkname"
  check "[$trunkname] base is local ref" test "$base" = "refs/heads/$trunkname"

  # restructure-commits local recipe: squash to merge-base, rebase onto <base>, no push.
  mb=$(git merge-base "$base" HEAD)
  git reset --soft "$mb"
  git commit -qm "feat: squashed feature work"
  git rebase -q "$base"
  check "[$trunkname] feature is 1 commit ahead of trunk" \
    test "$(git rev-list --count "$trunk"..HEAD)" = "1"
  check "[$trunkname] trunk is an ancestor (rebased cleanly)" \
    test "$(git rev-list --count HEAD.."$trunk")" = "0"
  new_tip=$(git rev-parse HEAD)

  # merge local recipe: switch trunk, ff-only, delete branch.
  feature=$(git branch --show-current)
  resolve_trunk
  git switch -q "$trunk"
  git merge --ff-only -q "$feature"
  git branch -q -d "$feature"
  check "[$trunkname] trunk fast-forwarded to feature tip" \
    test "$(git rev-parse "$trunk")" = "$new_tip"
  check "[$trunkname] feature branch deleted" \
    test -z "$(git branch --list "$feature")"

  cd "$root"; rm -rf "$d"
done

# --- Scenario C: no trunk at all (repro) -> resolution must yield nothing ---
d=$(mktemp -d)
git init -q -b feature "$d"   # initial branch is 'feature'; no main/master ever created
cd "$d"
git config user.email t@example.com; git config user.name tester
printf 'x\n' > f.txt; git add f.txt; git commit -qm "root on feature"
resolve_trunk
check "[no-trunk] resolve_trunk yields empty base (skill must halt)" test -z "$base"
cd "$root"; rm -rf "$d"

echo "----"
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Make it executable and run it**

Run:
```bash
chmod +x plugins/dev-workflow/scripts/verify-local-only.sh
bash plugins/dev-workflow/scripts/verify-local-only.sh
```
Expected: every line `PASS: …`, final line `passed: 13  failed: 0`, exit code `0`.

- [ ] **Step 3: Commit**

```bash
git add plugins/dev-workflow/scripts/verify-local-only.sh
git commit -m "test(dev-workflow): add local-only repo verification harness (#10)"
```

---

## Task 2: `restructure-commits` — trunk resolution, precondition, remote gating

**Files:**
- Modify: `plugins/dev-workflow/skills/restructure-commits/SKILL.md`

**Interfaces:**
- Consumes: the trunk-resolution snippet (Global Constraints); the harness recipe from Task 1 as the source of truth for the local squash+rebase sequence.
- Produces: a skill whose steps reference `<base>`/`<trunk>` instead of hardcoded `main`/`origin/main`, gates fetch/push/PR on remote presence, and adds a trunk precondition.

All edits are within the existing `## Workflow` section. Make them in order.

- [ ] **Step 1: Rewrite Step 1 (preconditions) to add trunk resolution + the trunk precondition**

Find the section that currently reads:

```markdown
### 1. Check preconditions — stop if they fail

- **Must be on a feature branch, not `main`.** `main` is protected; never rebase or rewrite
  it. If `HEAD` is `main` (or detached), stop and say so.
- **Working tree must be clean.** A rebase can't run over uncommitted changes, and you don't
  want to sweep stray edits into the squash. If `git status --porcelain` is non-empty, stop
  and show what's dirty — let the user commit or stash first.
```

Replace it with:

```markdown
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
```

- [ ] **Step 2: Gate the fetch (Step 2) on a remote**

Find:

```markdown
### 2. Fetch the latest main

```bash
git fetch origin
```

Fetching changes nothing locally, so do it up front — the commit count and the rebase both
need the current `origin/main`.
```

Replace with:

```markdown
### 2. Fetch the latest trunk — if there's a remote

```bash
[ -n "$HAS_REMOTE" ] && git fetch origin
```

Fetching changes nothing locally, so do it up front — when there's a remote, the commit count
and the rebase both need the current `origin/<trunk>`. With no remote, skip this; `<base>` is
the local trunk and there is nothing to fetch.
```

- [ ] **Step 3: Make the count use `<base>` (Step 4)**

Find:

```markdown
First the count: `git rev-list --count origin/main..HEAD`.

- **0** → nothing to merge; stop and say the branch matches `main`.
```

Replace with:

```markdown
First the count: `git rev-list --count "$base"..HEAD`.

- **0** → nothing to merge; stop and say the branch matches `<trunk>`.
```

- [ ] **Step 4: Make the squash base use `<base>` (Step 5)**

In Step 5, the squash-all bullet currently reads:

```markdown
- **Squash all (default):** generate the message from the whole branch diff
  (`git diff origin/main...HEAD`), then collapse to the **merge-base** (not `origin/main` —
  you haven't rebased yet, so that would fold in main's newer commits):

  ```bash
  git reset --soft $(git merge-base origin/main HEAD)
  git commit -F <message-file>
  ```
```

Replace with:

```markdown
- **Squash all (default):** generate the message from the whole branch diff
  (`git diff "$base"...HEAD`), then collapse to the **merge-base** (not `<base>` directly —
  you haven't rebased yet, so that would fold in the trunk's newer commits):

  ```bash
  git reset --soft $(git merge-base "$base" HEAD)
  git commit -F <message-file>
  ```
```

And the split/custom-groups bullet currently reads:

```markdown
  ```bash
  git reset $(git merge-base origin/main HEAD)   # uncommit; changes stay in the working tree
  git add <group-1 paths> && git commit -F <msg-1>   # message from: git diff --cached
  git add <group-2 paths> && git commit -F <msg-2>
  ```
```

Replace with:

```markdown
  ```bash
  git reset $(git merge-base "$base" HEAD)   # uncommit; changes stay in the working tree
  git add <group-1 paths> && git commit -F <msg-1>   # message from: git diff --cached
  git add <group-2 paths> && git commit -F <msg-2>
  ```
```

- [ ] **Step 5: Make the rebase use `<base>` (Step 6)**

Find:

```markdown
### 6. Rebase onto the latest main

```bash
git rebase origin/main
```
```

Replace with:

```markdown
### 6. Rebase onto the latest trunk

```bash
git rebase "$base"
```
```

- [ ] **Step 6: Gate push (Step 7) and PR (Step 8) on a remote**

Find the whole of Step 7:

```markdown
### 7. Push the rewritten branch

The rewrite changed commit SHAs, so push to update the remote (and any open PR). No
confirmation — `--force-with-lease` is the safeguard:

```bash
git push --force-with-lease     # branch already on the remote
git push -u origin HEAD          # first push of a branch that was never pushed
```

If `--force-with-lease` is **rejected**, stop and surface it — that means someone else pushed
to the branch, which is the one case that genuinely warrants a human look.
```

Replace with:

```markdown
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
```

Then, at the very start of Step 8 (`### 8. Open or sync the PR`), insert this sentence immediately under the heading, before the existing "The description is …" paragraph:

```markdown
**Local-only (no remote) → skip this step.** With no remote there's no PR; the branch is now a
clean, rebased commit on top of the local `<trunk>`. Move to the summary.
```

- [ ] **Step 7: Make the summary mode-aware (Notes)**

In the `## Notes` section, the first bullet currently reads:

```markdown
- Unattended by design — it stops only on a bad starting state or a rebase conflict. So **end
  with a summary**: the backup tag (recovery point), the commit message(s), the push result,
  and the PR link, so the user can review, recover, or amend as needed.
```

Replace with:

```markdown
- Unattended by design — it stops only on a bad starting state or a rebase conflict. So **end
  with a summary** that names the resolved `<trunk>` and the mode:
  - **With a remote:** the backup tag (recovery point), the commit message(s), the push result,
    and the PR link, so the user can review, recover, or amend as needed.
  - **Local-only (no remote):** the backup tag, the commit message(s), and a note that push and
    PR were skipped because no remote is configured — e.g. *"Squashed → 1 commit, rebased onto
    local `main`. Skipped push + PR (no remote). `main` not advanced — run `/merge` to
    integrate."*
```

- [ ] **Step 8: Verify the recipe still holds + read-through**

Run the harness (it encodes this same squash+rebase recipe):
```bash
bash plugins/dev-workflow/scripts/verify-local-only.sh
```
Expected: `passed: 13  failed: 0`.

Then read `plugins/dev-workflow/skills/restructure-commits/SKILL.md` top to bottom and confirm: no remaining bare `origin/main` outside the resolution snippet's example guidance, every `git` step uses `"$base"`/`<trunk>` or is gated on `$HAS_REMOTE`, and the precondition halts when `base` is empty.

- [ ] **Step 9: Commit**

```bash
git add plugins/dev-workflow/skills/restructure-commits/SKILL.md
git commit -m "feat(dev-workflow): support local-only repos in restructure-commits (#10)"
```

---

## Task 3: `merge` — trunk precondition + local-only merge path

**Files:**
- Modify: `plugins/dev-workflow/skills/merge/SKILL.md`

**Interfaces:**
- Consumes: the trunk-resolution snippet; the harness merge recipe from Task 1 (switch `<trunk>`, `git merge --ff-only`, `git branch -d`).
- Produces: a `/merge` skill that merges via PR when a remote exists and via local fast-forward when it doesn't, with a trunk precondition.

- [ ] **Step 1: Add trunk resolution + precondition to Step 1**

Find:

```markdown
### 1. Identify the branch and its PR

Default to the current branch (or the one the user named); capture the name *before* anything
switches it. Refuse if it's `main`. Find the open PR:

```bash
gh pr view --json number,state,title,url
```

If there's no open PR for the branch, stop and say so — there's nothing to merge.
```

Replace with:

```markdown
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
```

- [ ] **Step 2: Add the local-only merge path to Step 2**

Find:

```markdown
### 2. Merge the PR

Merge straight away — **no confirmation prompt**. The `/merge` invocation is the go-ahead, and
the PR's approval/branch-protection state is GitHub's call, so don't re-ask before merging:

```bash
gh pr merge <n> --rebase --delete-branch
```
```

Replace with:

```markdown
### 2. Merge — PR (remote) or fast-forward (local-only)

**Local-only (no remote) → fast-forward the trunk locally and delete the branch.** This is
safe because `/restructure-commits` already rebased `<feature>` onto the trunk, so `<trunk>` is
an ancestor of the feature tip — the merge is a pure fast-forward, never a merge commit:

```bash
git switch "$trunk"
git merge --ff-only "$feature"
git branch -d "$feature"
```

If `--ff-only` is **rejected**, stop: *"`<trunk>` can't fast-forward to `<feature>` — run
`/restructure-commits` first."* Then skip to Step 4 (Step 3's `git pull` needs a remote).

**With a remote → merge the PR.** Merge straight away — **no confirmation prompt**. The
`/merge` invocation is the go-ahead, and the PR's approval/branch-protection state is GitHub's
call, so don't re-ask before merging:

```bash
gh pr merge <n> --rebase --delete-branch
```
```

- [ ] **Step 3: Gate Step 3 (update local trunk) on a remote**

Find:

```markdown
### 3. Update local main

```bash
git switch main        # usually already here — gh moved off the deleted branch
git pull --ff-only
```

`--ff-only` keeps `main` a clean fast-forward; if it can't, stop and surface that rather than
making a merge commit on a protected branch.
```

Replace with:

```markdown
### 3. Update local trunk — if there's a remote

In local-only mode this is already done: Step 2 fast-forwarded `<trunk>` and you're on it, so
skip. With a remote:

```bash
git switch "$trunk"     # usually already here — gh moved off the deleted branch
git pull --ff-only
```

`--ff-only` keeps the trunk a clean fast-forward; if it can't, stop and surface that rather than
making a merge commit on a protected branch.
```

- [ ] **Step 4: Gate the prune (Step 5) on a remote**

Find:

```markdown
### 5. Prune stale references

```bash
git fetch --prune
```

Drops remote-tracking refs for branches deleted on the remote, so `git branch -a` stays honest.
```

Replace with:

```markdown
### 5. Prune stale references — if there's a remote

```bash
[ -n "$HAS_REMOTE" ] && git fetch --prune
```

Drops remote-tracking refs for branches deleted on the remote, so `git branch -a` stays honest.
With no remote there's nothing to prune.
```

- [ ] **Step 5: Make the report mode-aware (Step 6)**

Find:

```markdown
### 6. Report

Summarize: PR merged (rebase), `main` updated, branch deleted (local + remote), backup tags
cleared.
```

Replace with:

```markdown
### 6. Report

Summarize, naming the resolved `<trunk>` and the mode:
- **With a remote:** PR merged (rebase), `<trunk>` updated, branch deleted (local + remote),
  backup tags cleared.
- **Local-only:** `<trunk>` fast-forwarded to the feature tip, feature branch deleted locally,
  backup tags cleared (no PR / remote involved).
```

- [ ] **Step 6: Verify recipe + read-through**

Run:
```bash
bash plugins/dev-workflow/scripts/verify-local-only.sh
```
Expected: `passed: 13  failed: 0`.

Read `plugins/dev-workflow/skills/merge/SKILL.md` and confirm: the local path uses `git merge --ff-only` + `git branch -d`, every remote-only command is gated on `$HAS_REMOTE` or the PR branch, and the trunk precondition halts when `base` is empty without creating anything.

- [ ] **Step 7: Commit**

```bash
git add plugins/dev-workflow/skills/merge/SKILL.md
git commit -m "feat(dev-workflow): add local-only merge path to /merge (#10)"
```

---

## Task 4: `premerge` — trunk-existence precondition + local mode in summary

**Files:**
- Modify: `plugins/dev-workflow/skills/premerge/SKILL.md`

**Interfaces:**
- Consumes: the trunk-resolution snippet (for the fail-fast precondition only — `premerge` adds no git mutation logic).
- Produces: a `/premerge` that fails fast (before the `docs` pass) when no trunk exists, and whose summary surfaces the local-only mode reported by `restructure-commits`.

- [ ] **Step 1: Add the trunk precondition to Step 1**

Find:

```markdown
- **Must be on a feature branch, not `main`.** `main` is protected; never rewrite it. If `HEAD` is
  `main` (or detached), stop and say so.
- **Working tree must be clean.** `docs` commits its own edits, and `restructure-commits` refuses to
  squash over uncommitted changes. If `git status --porcelain` is non-empty, stop and show what's
  dirty — let the user commit or stash first.

(`restructure-commits` re-checks both in its own step 1; checking here too just avoids starting a
run that can't finish.)
```

Replace with:

```markdown
- **A `main`/`master` trunk must exist.** Probe `origin/main`, `origin/master`, local `main`,
  then local `master` (fetch first if a remote exists); if none resolves, stop with the same
  guidance `restructure-commits` gives — *"No `main` or `master` trunk found … create one first,
  e.g. `git branch main <ref>`, then re-run."* **Don't create it.** Checking here fails fast,
  before the `docs` pass commits anything.
- **Must be on a feature branch, not the trunk.** The trunk is protected; never rewrite it. If
  the current branch is the trunk (`main`/`master`) or `HEAD` is detached, stop and say so.
- **Working tree must be clean.** `docs` commits its own edits, and `restructure-commits` refuses to
  squash over uncommitted changes. If `git status --porcelain` is non-empty, stop and show what's
  dirty — let the user commit or stash first.

(`restructure-commits` re-checks all three in its own step 1; checking here too just avoids starting
a run that can't finish.)
```

- [ ] **Step 2: Surface local-only mode in the summary (Step 4)**

In `### 4. Summarize`, the **Restructure** bullet currently reads:

```markdown
- **Restructure:** the backup tag (recovery point), the final commit message(s), the push result,
  and the PR link.
```

Replace with:

```markdown
- **Restructure:** the backup tag (recovery point), the final commit message(s), and — with a
  remote — the push result and PR link. In a **local-only** repo (no remote), surface what
  `restructure-commits` reported instead: push and PR skipped, and that the user should run
  `/merge` to integrate the rebased branch into the local trunk.
```

- [ ] **Step 3: Read-through (no harness change — premerge adds no git logic)**

Read `plugins/dev-workflow/skills/premerge/SKILL.md` and confirm the precondition list now has three checks (trunk exists, not on trunk, clean tree) and the summary mentions the local-only case. No new git commands were added here, so the Task 1 harness is unaffected; run it once to confirm nothing regressed:

```bash
bash plugins/dev-workflow/scripts/verify-local-only.sh
```
Expected: `passed: 13  failed: 0`.

- [ ] **Step 4: Commit**

```bash
git add plugins/dev-workflow/skills/premerge/SKILL.md
git commit -m "feat(dev-workflow): fail premerge fast when no trunk exists (#10)"
```

---

## Task 5: README + version bump

**Files:**
- Modify: `plugins/dev-workflow/README.md`
- Modify: `plugins/dev-workflow/.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: nothing.
- Produces: user-facing docs for the trunk precondition + local-only behavior, and a `0.3.0` version.

- [ ] **Step 1: Document trunk + local-only in the README**

In `plugins/dev-workflow/README.md`, find the "Trunk & merge strategy" bullet:

```markdown
- **Trunk & merge strategy.** `restructure-commits`/`merge` assume `main` is the protected trunk and the
  project merges by **rebase**. If your repo differs, adjust the default branch name and the
  `gh pr merge` strategy flag (`--squash` / `--merge`) in `skills/merge/SKILL.md`.
```

Replace with:

```markdown
- **Trunk & merge strategy.** The trunk may be **`main` or `master`** (resolved automatically,
  `main` preferred); all three skills **require** one of them to exist and **never create one** —
  if neither exists they halt and tell you to create it (e.g. `git branch main <ref>`). They
  merge by **rebase**; if your repo uses a different strategy, adjust the `gh pr merge` flag
  (`--squash` / `--merge`) in `skills/merge/SKILL.md`.
- **Local-only repos (no remote).** With no remote configured the lifecycle degrades cleanly:
  `restructure-commits` squashes and rebases onto the **local** trunk and **skips push + PR**;
  `/merge` fast-forwards the local trunk to the branch and deletes it. No GitHub, no `gh`
  required. (`scripts/verify-local-only.sh` exercises these paths.)
```

- [ ] **Step 2: Bump the plugin version**

In `plugins/dev-workflow/.claude-plugin/plugin.json`, change:

```json
  "version": "0.2.1",
```

to:

```json
  "version": "0.3.0",
```

- [ ] **Step 3: Verify**

Run:
```bash
grep '"version"' plugins/dev-workflow/.claude-plugin/plugin.json
python3 -c "import json,sys; json.load(open('plugins/dev-workflow/.claude-plugin/plugin.json')); print('plugin.json OK')"
```
Expected: `"version": "0.3.0",` and `plugin.json OK`.

- [ ] **Step 4: Commit**

```bash
git add plugins/dev-workflow/README.md plugins/dev-workflow/.claude-plugin/plugin.json
git commit -m "docs(dev-workflow): document local-only support; bump to 0.3.0 (#10)"
```

---

## Final verification (after all tasks)

- [ ] Run the harness once more: `bash plugins/dev-workflow/scripts/verify-local-only.sh` → `passed: 13  failed: 0`.
- [ ] `grep -rn 'origin/main' plugins/dev-workflow/skills/` → only the guidance/example mentions remain (no live `git` command still hardcodes `origin/main`).
- [ ] `grep -rn 'master' plugins/dev-workflow/skills/ plugins/dev-workflow/README.md` → trunk handling mentions `master` in all three skills + README.
- [ ] Manual walk (optional, highest fidelity): in a throwaway `git init` repo, follow each skill's prose literally for scenario 2 (main, no remote) and scenario 4 (no trunk) and confirm the documented outcome.
