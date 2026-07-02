---
name: babysit
description: >-
  Shepherd an already-open PR through CI until it is merge-ready or genuinely blocked. Use when the
  user runs /babysit or asks to "babysit the PR", "watch the PR", "keep an eye on the PR",
  "monitor CI", "poll the checks", or "wait for CI to go green". It watches the checks; when a
  REQUIRED check fails it reads the failure log, fixes mechanical breakage, pushes, and re-watches —
  then reports the one real blocker if any remains. Defaults to the current branch's PR; accepts an
  optional PR number or URL. It only watches an open PR and fixes what breaks CI — it does not open
  PRs, rebase, or merge.
---

# Babysit a PR through CI

Take an **already-open** PR and shepherd it to a settled state — every required check green (so it
can be merged), or a clearly named blocker that needs a human. Babysitting **never opens PRs,
rebases, or merges**; it watches an open PR converge and, once CI is green, hands back to the user.

**The one insight that makes this skill work: not every red check blocks the merge.** A PR's base
branch declares a set of *required* status checks; only those gate the merge. Coverage gates,
security scanners, and informational bots are usually **advisory** — red, loud, and irrelevant to
whether the PR can land. Babysitting means chasing the required checks to green and refusing to be
dragged into the advisory ones. Get that distinction right and the rest is mechanical.

## Arguments

One optional token names the PR; with no argument it targets **the current branch's PR**.

| Invocation | Target |
|---|---|
| `/babysit` | the current branch's PR (`gh pr view`) |
| `/babysit 123` | PR #123 in this repo |
| `/babysit https://github.com/owner/repo/pull/123` | that PR (may be another repo) |

## Workflow

### 1. Resolve the target PR

Default to the current branch's PR; use the argument if one was given. Capture the number, base
branch, head branch, and state up front — the rest of the flow keys off the **base branch** (its
protection rules) and the PR number.

```bash
gh pr view [<number>|<url>] \
  --json number,state,url,headRefName,baseRefName,mergeStateStatus,reviewDecision,statusCheckRollup
```

If there's no open PR for the branch, stop and say so — there's nothing to babysit (opening a PR is
out of scope). Derive `owner/repo` from the PR URL (it may differ from the local repo when a
URL argument points elsewhere).

### 2. Separate REQUIRED checks from advisory ones — do this first

This is the step that everything else depends on. Read the base branch's protection to learn which
check contexts actually gate the merge:

```bash
gh api "repos/{owner}/{repo}/branches/{base}/protection/required_status_checks" \
  --jq '.contexts[]?, .checks[]?.context'
```

Every context this returns is **required** — a red one blocks the merge and is yours to fix. A
check **not** in this set is **advisory**: note it, but do **not** chase it, and **never game it**.
Turning an advisory coverage check green by adding files to a coverage `exclude`, relaxing a
scanner threshold, or similar is off-limits — you'd be defeating the metric, not the problem it
measures. Leave advisory red alone and say so in the report.

*(Real example: a PR showed `test-coverage` red, but protection required only
`continuous-integration/jenkins/pr-merge`. Correct move — leave `test-coverage` alone, drive only
the Jenkins check.)*

If the protection endpoint is forbidden or 404s (no admin read, or checks configured via rulesets
rather than classic protection), fall back to GitHub's own verdict — `mergeStateStatus` and the
required-marking `gh` shows on each check — or ask the user which checks are required rather than
guessing. Don't assume every red check is required.

### 3. Watch CI to a terminal state

Prefer the built-in watcher; fall back to a bounded poll loop where `--watch` isn't available:

```bash
gh pr checks <number> --watch --interval 30   # interval is seconds
```

**Match the cadence to the pipeline.** A build that takes 20 minutes doesn't need polling every few
seconds — that's just noise and rate-limit pressure. Pick an interval proportional to how long the
pipeline runs (tens of seconds for quick suites, a minute or more for long ones).

**Guard the startup race.** Right after a push, the *old* run's results may still be showing while
the new run hasn't registered yet — a "terminal" verdict read in that window is stale. Before you
trust a green/red conclusion, confirm the checks belong to the **current** head SHA (a fresh run has
appeared and reached a terminal conclusion), not the previous push's.

A terminal state is: all required checks green (→ step 7), or a required check failed (→ step 4).

### 4. On a REQUIRED check failure, read the log and diagnose — don't guess

Get the *actual* failure output before proposing any fix. Locate the failing check's details link
from `statusCheckRollup` (step 1's JSON), then branch on where it runs:

- **GitHub Actions:** `gh run view <run-id> --log-failed` prints just the failed steps' logs.
- **External CI (Jenkins & friends, e.g. `ci.aws.*`):** fetch the console log — Jenkins exposes it
  at `.../<build>/consoleText`. **Defer to any project-specific rule for reaching internal CI
  hosts:** some orgs require browser automation rather than a plain fetch for their internal CI (for
  instance, a repo's CLAUDE.md may mandate the Chrome tools for `ci.aws.ozean12.com`). Honor that
  rule instead of blindly curling.

**Watch for version-sensitive tooling.** A linter or formatter pinned to an `@auto`-style,
version-dependent ruleset can render *opposite* verdicts locally and in CI when the two run
different tool versions (real case: `php-cs-fixer` with `@auto` — local `3.92.5` vs CI `3.85.1`
disagreed on the same file). The failure log is the source of truth: reproduce against it, and when
local and CI conflict, **trust CI's version**, not your machine's.

### 5. Fix and push — or stop and surface

- **Mechanical / unambiguous** (formatting, lint autofix, an obvious config or import fix): apply
  it directly, commit, and push so CI re-runs.
- **Touches program logic, is ambiguous, or is risky:** **stop.** Report the root-cause diagnosis
  and a proposed fix, and let the user decide — don't push a guess at behavior.

Respect the standing safety rules whichever path you take: **never push to `main`/`master`**, never
force-push without a real reason, and honor the repo's push/PR conventions (some repos push a
feature branch to a fork, not `origin`). Pushing a mechanical fix to the PR's own feature branch is
the expected action here; anything beyond that waits for the user.

### 6. Loop

After a push, go back to step 3 and watch the **new** run (mind the startup race from step 3).
Repeat — diagnose, fix, push, re-watch — until the required checks are green or a failure needs a
human decision.

### 7. Classify the remaining blocker — and know when to stop

Green required checks don't always mean "mergeable." Once CI is green, read the PR's merge state
(`mergeStateStatus`, `reviewDecision`) and classify what's left:

- **`REVIEW_REQUIRED` / approval pending** — a human gate, not a CI problem. **Report it and stop
  polling.** Don't loop waiting on a person; optionally offer to resume watching on an interval if
  the user wants.
- **Merge conflict / behind base** — also not a CI failure. Surface it and hand back to the user to
  rebase — babysitting doesn't rebase.
- **Clean and mergeable** — done; the PR is ready to merge.

Optionally, surface any **new review comments** posted since babysitting started, so the user sees
feedback that landed while CI churned.

### 8. Report

At every settle point, report concisely — a small table plus the bottom line:

| Check | Result | Required? |
|---|---|---|
| continuous-integration/jenkins/pr-merge | ✅ pass | required |
| test-coverage | ❌ fail | advisory — ignored |

State what's green, which red checks are advisory-and-left-alone (and why), and the **single real
blocker** if one remains (a required failure needing a human, or a review/conflict gate).

## Principles

- **Required-vs-advisory is king.** Only base-branch-required checks block the merge. Everything
  else is noise you *note*, not noise you *chase*.
- **Logs before guesses.** Never propose a fix from a check's red X alone — pull the failure log and
  diagnose the root cause first.
- **Trust CI's tool versions.** When a version-sensitive linter/formatter disagrees between local
  and CI, CI's verdict wins; reproduce against its version.
- **Don't game advisory gates.** Never manipulate a metric (coverage excludes, scanner thresholds)
  just to flip a non-required check green.
- **Stop at human-gated states.** Required-review approval and merge conflicts aren't CI problems —
  report them and stop; don't poll a human forever.

## Notes

- **Scope: an already-open PR only.** Babysitting watches, diagnoses, and applies mechanical fixes.
  It does **not** open PRs, rebase, restructure commits, or merge — those are separate steps done
  before or after. If babysitting hits a conflict or a needed rebase, it hands back to the user.
- **When to reach for it:** the PR is open and you just need CI to converge before merging.
- The only history this skill adds is mechanical fix commits on the PR's own feature branch, pushed
  so CI re-runs. It never touches the trunk.
