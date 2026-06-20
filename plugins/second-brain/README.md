# second-brain

A personal memory system for Claude Code, built on an Obsidian vault. A `SessionEnd` hook
captures every session verbatim to the vault's `raw/`; on demand, skills distill the queue into
a **topical wiki** (what you know about X) and a **temporal journal** (when/what you did).

Extracted and generalized so it works in any vault, on any machine or account.

## What's inside

### Skills (slash commands)

Namespaced under the plugin once installed (e.g. `/second-brain:file-inbox`).

| Skill | Does |
|-------|------|
| `init-vault` | Scaffolds a fresh vault from the bundled template (folder layout, `CLAUDE.md` conventions, `index.md`, `.obsidian/` config, `.gitignore`) and git-inits it. Refuses to overwrite a non-empty directory. |
| `file-inbox` | Files the vault's pending `inbox/` queue into `wiki/` (via the librarian) and `journal/` (via the journal extractor→grouper), then makes one commit. |
| `rebuild-journal` | Re-extracts named sessions and merges their work into journal day-files, non-destructively. |

### Agents (subagents)

Dispatched by the skills as `second-brain:<name>`.

| Agent | Role |
|-------|------|
| `librarian` | Files sessions into the topical `wiki/`, merges/dedupes notes, maintains indexes and link-hygiene, records provenance. |
| `journal-extractor` | Reads one session transcript and emits atomic, project-attributed work items as JSON (map stage). |
| `journal-grouper` | Merges work items into one journal day-file with semantic dedup (reduce stage). |

### Hook

A `SessionEnd` command hook (`hooks/hooks.json`) runs `hooks/session-capture.sh` after every
session: it copies the transcript into `raw/<event>/<YYYY-MM>/`, writes write-once metadata, and
enqueues an `inbox/` pointer. No LLM, fast and deterministic.

## Setup

```bash
# 1. Add the marketplace (once)
/plugin marketplace add axklim/claude-plugins

# 2. Install the plugin
/plugin install second-brain@axklim

# 3. Set your vault path when prompted (userConfig: vault_path),
#    or create a fresh vault and point at it:
/second-brain:init-vault ~/notes/brain
```

Then work normally in your other projects — sessions auto-capture to the vault. When you want to
file them: `/second-brain:file-inbox`. Pull updates later with `/plugin update`.

## How the pieces fit

```
every session ──(SessionEnd hook)──> raw/ + inbox/ pointer
/second-brain:file-inbox
   ├─> second-brain:librarian ─────────────> wiki/ (topical)
   └─> second-brain:journal-extractor ──┐
       second-brain:journal-grouper ◄───┘──> journal/ (temporal)
/second-brain:rebuild-journal ──> re-extract named sessions ──> journal/
/second-brain:init-vault ──> scaffolds a fresh vault from assets/vault-template/
```

## Notes & assumptions

- **It's an Obsidian vault**, not a code repo: topic folders, atomic notes, `[[wikilinks]]`, YAML
  frontmatter. The scaffolded `CLAUDE.md` documents the conventions.
- **The capture hook is global** — it fires on every session and writes to your configured
  `vault_path`. With no vault configured it is a silent no-op. Sessions run *inside* the vault are
  skipped (self-capture guard).
- **Namespacing.** Skills dispatch the bundled agents by their namespaced ids
  (`second-brain:librarian`, etc.); plugin agents don't resolve by bare name. If you rename this
  plugin, update those references in the three `skills/*/SKILL.md` files.
- **Tests.** `tests/test-session-capture.sh` covers the hook; `tests/librarian/test-tooling.sh`
  self-tests the filing-contract validator.
