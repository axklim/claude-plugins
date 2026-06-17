---
name: docs
description: >-
  Update project documentation (README.md, CLAUDE.md, and other *.md files) so it
  reflects recent code changes. Use this whenever the user runs /docs or asks to
  "update docs", "update documentation", "sync the docs", "refresh the README",
  "document this change", or asks whether the README/CLAUDE.md need updating after a
  feature, config change, or refactor — even if they don't say the word "skill". It
  dispatches the bundled `documentation` review agent to find gaps, then applies the
  fixes and reports what changed.
---

# Update documentation

Keep this project's docs aligned with the code. The heavy lifting of *deciding what
needs to change* belongs to the `documentation` agent — it has the gap-detection rules and
a per-project memory of each repo's doc conventions. This skill's job is to run that agent,
then **apply** the changes it surfaces (the agent itself is deliberately report-only) and tell
the user what moved.

Treat the agent as the single source of truth for *what* to document. Don't re-implement
its gap-detection logic here — if its rules need tuning, that lives in the `documentation`
agent definition, not in this skill.

## Workflow

### 1. Establish scope

By default, document the **recent changes** — uncommitted work plus commits on the
current branch. You don't need to compute the diff yourself; the agent inspects git
(`git diff`, `git diff --staged`, `git diff main...HEAD`) on its own.

If the user pointed at a narrower scope — "update docs for the new auth feature", "since the
last release", "just the README" — carry that hint into the agent prompt so it anchors on the
right changes.

### 2. Dispatch the documentation agent

Use the Task/Agent tool with `subagent_type: dev-workflow:documentation` (the agent is bundled
with this plugin, so it resolves under the plugin's namespace — if you rename the plugin, update
this identifier). Pass along the scope hint (or "recent changes on this branch" by default) and
ask it to report documentation gaps in its usual format. It returns either a set of gap
entries — each with **Target File**, **Missing**, **Section**, and **Suggested content** — or the
line "No documentation updates needed for these changes."

### 3. If there are no gaps, stop

Relay "No documentation updates needed for these changes." Make no edits. Don't invent
work the agent didn't find.

### 4. Apply each gap

For every reported gap, open the target file and integrate the change:

- **Match the file's voice.** Read the surrounding sections first and mirror the existing
  heading style, terminology, code-block conventions, and level of detail. The agent's
  "Suggested content" is a draft to adapt, not text to paste verbatim — make it read like
  the rest of the document.
- **Place it where it belongs.** Use the agent's "Section" pointer, but trust the file:
  if a more natural home exists, use it. Add a new heading only when no existing section
  fits.
- **Create a file only when warranted.** If the agent says a doc should exist but
  doesn't, create it only when the change clearly justifies a new document; otherwise fold
  the content into an existing doc.
- **Stay surgical.** Edit only what the gap calls for. Don't reformat, reorder, or
  rewrite unrelated content.
- **Don't invent.** If a suggested item references something you can't confirm in the
  actual changes, skip it and note why rather than documenting a feature that isn't there.

Only touch **project** docs (this repo's README.md, CLAUDE.md, and other *.md files).
Never edit the user's global `~/.claude/CLAUDE.md`.

### 5. Summarize and hand back

Report concisely:

- Which files you changed and which sections (e.g. "README.md → added 'Webhook endpoints'
  under Endpoints; CLAUDE.md → noted the new retry convention").
- Anything the agent flagged that you intentionally left out, and why.

Stop there. Don't commit or push — leave that to the user, who reviews changes
commit-by-commit.

## Notes

- README.md is for humans; CLAUDE.md is for AI agents. A single code change can warrant
  edits to both — apply each separately, in the register that fits its audience.
- If the agent's report is ambiguous about placement or wording, resolve it with the file
  in front of you rather than guessing — you have Edit access and full context the agent
  was working from a diff.
