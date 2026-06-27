# dev-workflow: `/merge` defaults to squash, with strategy override args

**Date:** 2026-06-27
**Status:** Approved design — ready for implementation plan.

## Problem

`/merge` hardcodes `gh pr merge <n> --rebase --delete-branch` on the remote path. Rebase-merge
was chosen to pair with `/restructure-commits`, which collapses the branch to one clean commit so
the rebase lands that exact commit on the trunk. But it forces the full lifecycle: to get a tidy
single commit on `main` you must run `/premerge` (or `/restructure-commits`) first. A common case
is wanting to merge **without** that prep — a branch with several WIP commits that should land as
one commit on `main`. Today `/merge --rebase` would replay every commit individually, so the only
way to squash is to drop to raw `gh`.

A squash merge collapses any number of branch commits into one commit on the trunk regardless of
prep, so it is the better default: it is identical in effect to rebase for an already-squashed
branch (squash of one commit ≈ that commit), and it cleanly handles the skip-prep case.

## Design overview

Change the **default merge strategy on the remote/PR path from rebase to squash**, and make the
strategy selectable by an optional argument. Everything else in `/merge` is unchanged — branch
deletion, trunk checkout + update, backup-tag cleanup, prune, preconditions, and the local-only
fast-forward path.

### Strategy argument

`/merge` takes one optional token selecting the `gh pr merge` strategy. Default (no arg) is
squash:

| Invocation | `gh pr merge` flag |
|---|---|
| `/merge` | `--squash` (new default) |
| `/merge squash` | `--squash` (explicit, same as default) |
| `/merge rebase` | `--rebase` (verbatim clean commits — the old default) |
| `/merge merge` | `--merge` (merge commit) |

Parsing: case-insensitive match of the first argument token against `squash` / `rebase` /
`merge`; empty or unrecognized → squash (the default). The resolved strategy is named in the final
report so the chosen mode is never silent.

### Squash commit message

`gh pr merge --squash` would otherwise let GitHub synthesize the commit message from the PR title
+ commit list. To keep `main`'s history as clean as `--rebase` did (which lands the
`/restructure-commits` message verbatim), the squash commit reuses the PR's own title and body.
Read them in Step 1 (`gh pr view --json number,state,title,url,body`).

A PR always has a title, so only the **body** can be missing. When the PR body is empty (the
typical skip-premerge case), generate one rather than fall back to GitHub's commit-message list —
**only the body is ever generated; the title is left as-is:**

1. Dispatch the **`commit-message`** agent (`subagent_type: dev-workflow:commit-message`) on the
   branch diff `git diff <base>...HEAD`, where `<base>` is the resolved trunk. Use its generated
   message as the PR body — prefer the body paragraphs; a subject-only result becomes a one-line
   body.
2. Append the footer (`🤖 Generated with [Claude Code](https://claude.com/claude-code)`), matching
   `/restructure-commits`.
3. Update the PR with it: `gh pr edit <n> --body "<generated body>"`, so the PR record and the
   squash commit agree.

After this the PR body is guaranteed non-empty, so the merge command is uniform — no conditional
`--body`, no reliance on GitHub's defaults:

- **Subject** → `--subject "<pr title>"`, the PR title verbatim. (The `(#N)` traceability suffix
  GitHub adds to its *default* squash title may or may not be auto-appended when an explicit
  `--subject` is given — confirm during the manual walk and append `(#<n>)` ourselves only if
  GitHub does not.)
- **Body** → `--body "<pr body>"` (the original PR body, or the just-generated one).

This applies only to `--squash`. `--rebase` and `--merge` keep their existing message behavior
(`--rebase` lands the commits as-is; `--merge` uses GitHub's merge-commit message), so the
body-generation step and the `--subject`/`--body` flags are squash-only.

### Scope decisions

- **Remote/PR path only — with a local gate.** Strategy is a `gh pr merge` concept. For a bare
  `/merge` the local-only path stays `git merge --ff-only` + `git branch -d`; it already requires a
  branch that `/restructure-commits` rebased onto the trunk, so it is already a clean single-commit
  integration, and `--ff-only` must not become a merge commit on the trunk. **An explicit strategy
  token in a local-only repo is an error:** `/merge squash` / `rebase` / `merge` with no remote
  **stops** and redirects to `/premerge` (or `/restructure-commits`) then plain `/merge` — local
  can't honor a PR-merge strategy, and reproducing it would duplicate `/restructure-commits`.
- **No relaxation of the "PR must exist" precondition.** `gh pr merge` needs an open PR regardless
  of strategy; creating one stays the job of `/premerge` / `/restructure-commits` / `/commit-push-pr`.
- The argument selects strategy only — it does not change branch deletion, cleanup, or any other
  step.

## Per-file changes

### `plugins/dev-workflow/skills/merge/SKILL.md` (the real change)

- **Frontmatter `description`** — replace "(rebase-merge)" framing with squash-by-default, and
  mention the optional `squash`/`rebase`/`merge` override so the model knows the args when invoking.
- **Intro (line ~14)** — "rebase-merge its PR" → squash-by-default wording.
- **New `## Arguments` section** — document the strategy token table and the default, matching the
  style of the `## Arguments` sections in `premerge` / `restructure-commits`.
- **Step 1** — add `body` to the `gh pr view --json …` field list so the squash subject/body are
  available.
- **Step 2 (remote merge)** — resolve the strategy from the argument; build the `gh pr merge`
  command accordingly. For squash, first ensure the PR body is non-empty (if empty, generate it
  via the `commit-message` agent and `gh pr edit` it onto the PR, per the message rule above),
  then merge:
  ```bash
  gh pr merge <n> --squash --subject "<pr title>" --body "<pr body>" --delete-branch
  ```
  Keep the existing "if GitHub rejects the merge, stop and surface why; don't use `--admin`" note.
- **Step 6 (report)** — "PR merged (rebase)" → name the resolved strategy (e.g. "PR merged
  (squash)").
- **Notes** — update "merges via rebase" to "merges via squash by default (override with
  `rebase`/`merge`)"; keep the "adjust the strategy flag for your project" guidance.

### `plugins/dev-workflow/skills/restructure-commits/SKILL.md` (wording only)

- Line ~207: "`/merge` takes it from there: it merges the PR (rebase-merge) and cleans up" →
  reflect squash-by-default.
- Line ~210: "merges via **rebase**. If your project uses a different trunk name or merge
  strategy, adjust …" → squash-by-default wording. No behavior change: `restructure-commits` still
  squashes the branch to one clean commit (that commit becomes the PR title/body the squash merge
  now reuses, so the lifecycle stays coherent).

### `plugins/dev-workflow/skills/premerge/SKILL.md` (wording only)

- Line ~114: "merges via **rebase** — the same handling …" → squash-by-default wording.

### `plugins/dev-workflow/README.md` (wording only)

- Line ~42: "rebase-merges its PR into the trunk" → "squash-merges its PR into the trunk (override
  with `rebase`/`merge`)".

## Verification

These are markdown skills with no test harness, so verification is reading-level plus a manual
walk in a throwaway repo. Cover:

1. **Default squash, after `/premerge` (1 clean commit):** `/merge` runs `gh pr merge --squash`
   with `--subject`/`--body` from the PR; the commit on `main` matches the `/restructure-commits`
   message; branch deleted, trunk updated, tags cleared. Confirm here whether GitHub appends
   `(#N)` to the explicit subject (settles the open question in the message rule above).
2. **Default squash, skip premerge (several commits), PR body written:** one squash commit using
   the PR title/body.
3. **Default squash, skip premerge (several commits), empty PR body:** `commit-message` agent
   generates a body from the branch diff; `/merge` updates the PR body via `gh pr edit`, then
   squashes with `--subject "<pr title>" --body "<generated body>"`; the PR record and the merge
   commit match. The PR title is untouched.
4. **Override `/merge rebase`:** falls back to `gh pr merge --rebase` (old behavior) with no
   `--subject`/`--body`.
5. **Override `/merge merge`:** `gh pr merge --merge`.
6. **Local-only (no remote):** bare `/merge` fast-forwards (`git merge --ff-only` + `git branch
   -d`) as before; an explicit `/merge squash` / `rebase` / `merge` **stops** with the redirect to
   `/premerge` + plain `/merge` and changes nothing.
7. **Consistency:** grep the dev-workflow docs for "rebase-merge" / "merges via rebase" and
   confirm no stale references remain.

## Out of scope

- Reproducing a squash/rebase/merge strategy locally (the local path fast-forwards; an explicit
  strategy token there is gated with a redirect to `/premerge` + plain `/merge`, not implemented).
- Relaxing the "open PR must exist" precondition / creating a PR inside `/merge`.
- Regenerating the PR title, or overwriting a non-empty PR body (only an empty body is filled,
  via the `commit-message` agent).
- Per-strategy behavior for `--merge`/`--rebase` messages — left to GitHub's defaults.
