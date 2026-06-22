---
name: premerge
description: >-
  Get the current feature branch fully merge-ready in one step: sync the docs to the code, then
  rebase onto main, squash to a clean commit, force-push, and open/sync the PR. It chains the
  `docs` and `restructure-commits` skills — the everyday "get this merge-ready" command at the
  front of the premerge → review → merge lifecycle. Pass "no docs" (or --no-docs) to skip the docs
  pass; any other plain-language instruction (e.g. "split into two commits: …") is passed through
  to control the commit structure. Run this ONLY when the user explicitly invokes /premerge. Never
  trigger it from conversational context or infer it from phrases like "ship it", "that's ready",
  or "get this merge-ready" — because it rewrites history and force-pushes, it must not run on its
  own. The explicit /premerge invocation is the required go-ahead.
---

# Premerge — get the branch merge-ready (docs + restructure-commits)

Take the current feature branch all the way to merge-ready in one command: bring the docs in line
with the code, then collapse the branch to a clean, rebased commit with an open PR. **/premerge
doesn't reimplement any of that** — it sequences two skills that already do it, in the order that
makes them compose:

1. **`docs`** — find documentation gaps from the branch's changes, apply them, and commit a single
   `docs:` commit (no push). This returns the working tree to clean.
2. **`restructure-commits`** — rebase onto the latest `main`, squash to a clean commit (folding in
   that `docs:` commit), force-push, and open or sync the PR.

The result is the start of the lifecycle: **/premerge → review → /merge**. For the
prepare-*without*-docs path, run `/restructure-commits` directly — or pass `no docs` here, which
makes /premerge identical to it.

**Same safety contract as `/restructure-commits`.** Everything it rewrites is confined to this
feature branch and is recoverable — `restructure-commits` tags a backup of the branch tip before
touching history, so the pre-run state is always one `git reset --hard` away. Invoking `/premerge`
*is* your consent to the docs commit, the squash, the rebase, and the force-push, so it runs
unattended. It halts only when it genuinely can't proceed safely: a wrong starting state, or a
rebase conflict it must not resolve on your behalf.

## Arguments

The invocation carries two independent things — a docs toggle and a commit-structure instruction:

- **No arguments** → sync docs, then squash the branch into one commit (the default).
- **A skip-docs signal** (`no docs`, `--no-docs`, `skip docs`, `without docs`) → skip step 2; go
  straight to `restructure-commits`. Equivalent to running `/restructure-commits` on its own.
- **Anything else** (e.g. `split into two commits: everything Claude-Code-related, and the rest`,
  or `keep commits as they are`) → a commit-structure instruction; pass it through verbatim to
  `restructure-commits`.
- **Both can combine:** `/premerge no docs, keep commits as they are` skips docs *and* forwards the
  structure instruction.

## Workflow

### 1. Check preconditions up front — stop if they fail

Check these *before* running anything, so /premerge never leaves a half-done run (docs committed but
no PR opened):

- **Must be on a feature branch, not `main`.** `main` is protected; never rewrite it. If `HEAD` is
  `main` (or detached), stop and say so.
- **Working tree must be clean.** `docs` commits its own edits, and `restructure-commits` refuses to
  squash over uncommitted changes. If `git status --porcelain` is non-empty, stop and show what's
  dirty — let the user commit or stash first.

(`restructure-commits` re-checks both in its own step 1; checking here too just avoids starting a
run that can't finish.)

### 2. Sync the docs — unless skipped

Unless the invocation gave a skip-docs signal, invoke the **`docs`** skill via the Skill tool
(`dev-workflow:docs` — plugin skills resolve under the plugin namespace; if you rename the plugin,
update this identifier). It runs the documentation agent, applies any gaps, and commits a single
`docs:` commit — or reports "No documentation updates needed" and commits nothing. Either way it
leaves the tree clean. **Don't duplicate its logic here** — let the skill do its job, then continue.

If docs were skipped, note that in the final summary and move straight to step 3.

### 3. Restructure the branch and open the PR

Invoke the **`restructure-commits`** skill via the Skill tool (`dev-workflow:restructure-commits`),
forwarding any commit-structure instruction from the invocation as its arguments (or none, for the
default squash). It fetches `main`, tags a backup, builds the merge-ready commit(s) — folding the
`docs:` commit into the squash — rebases onto the latest `main`, force-pushes, and opens or syncs
the PR.

If it stops on a rebase conflict (or a rejected `--force-with-lease`), hand back exactly as it does
— don't paper over it. The user resolves, then re-invokes `/premerge` (or `/restructure-commits`) to
finish.

### 4. Summarize

Give one combined report so the user can review, recover, or amend:

- **Docs:** what the docs pass changed (files / sections) and the `docs:` commit subject — or that
  it was skipped, or found no gaps.
- **Restructure:** the backup tag (recovery point), the final commit message(s), the push result,
  and the PR link.

## Notes

- /premerge is the **front of the lifecycle**: it makes a branch merge-ready, the user reviews, then
  `/merge` lands it on `main` and cleans up.
- It adds nothing to history that `docs` and `restructure-commits` don't already do — it just runs
  them in the right order behind one precondition guard. **If either step's behavior needs to
  change, change it in that skill, not here.**
- Skipping docs (`no docs`) makes /premerge identical to `/restructure-commits`; that standalone
  skill is the canonical no-docs path.
- Assumes `main` is the protected trunk and the project merges via rebase — the same assumptions as
  the skills it chains. Adjust them there if your project differs.
