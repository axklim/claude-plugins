# second-brain

A personal memory system for Claude Code. A `SessionEnd` hook captures every session verbatim to
the vault's `raw/`; on demand, skills distill the queue into a **topical wiki** (what you know
about X) and a **temporal journal** (when/what you did) — plain Markdown you can browse in
Obsidian or any editor.

Extracted and generalized so it works in any vault, on any machine or account.

> **⚠️ Privacy — the vault repo is secret-bearing.** Capture is global: every session in every
> project is copied **verbatim** into `raw/**/*.jsonl` and committed to git. Only the derived
> `wiki/`/`journal/` notes are secret-redacted — `raw/` is **not**. Any API key, token, `.env`
> echo, or confidential paste from any session lands in git **history** and survives later
> deletion. **Keep the vault in a private repo; never push it to a shared remote.** `raw/` is
> intentionally tracked (both `file-inbox` and `rebuild-journal` read from it), so it can't simply
> be gitignored without breaking cross-machine use. Run `/second-brain:doctor` to confirm capture.

## What's inside

### Skills (slash commands)

Namespaced under the plugin once installed (e.g. `/second-brain:file-inbox`).

| Skill | Does |
|-------|------|
| `init-vault` | Scaffolds a fresh vault from the bundled template (folder layout, `CLAUDE.md` conventions, `index.md`, `.obsidian/` config, `.gitignore`) and git-inits it. Refuses to overwrite a non-empty directory. |
| `file-inbox` | Files the vault's pending `inbox/` queue into `wiki/` (via the librarian) and `journal/` (via the journal extractor→grouper), then makes one commit. |
| `rebuild-journal` | Re-extracts named sessions and merges their work into journal day-files, non-destructively. |
| `doctor` | Health-checks the capture pipeline — verifies `vault_path` resolves, the vault looks valid, and captures are landing. Run if sessions aren't showing up. |

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

A `SessionStart` command hook (`hooks/session-context.sh`) injects the plugin's canonical vault
conventions (`assets/vault-conventions.md`) into context **when you're working inside the vault**,
so the conventions always match the installed plugin version and update with `/plugin update`. The
scaffolded vault's own `CLAUDE.md` is just a thin stub. Outside the vault this hook does nothing.

## Setup

```bash
# 1. Add the marketplace (once)
/plugin marketplace add axklim/claude-plugins

# 2. Install the plugin
/plugin install second-brain@axklim

# 3. Set your vault path when prompted (userConfig: vault_path),
#    or create a fresh vault and point at it:
/second-brain:init-vault ~/Documents/second-brain
```

Then work normally in your other projects — sessions auto-capture to the vault. When you want to
file them: `/second-brain:file-inbox`.

## Recall in other projects

Capture and conventions cover working *inside* the vault. To let Claude consult the brain from
*other* projects, add a small recall block to your user-scope `~/.claude/CLAUDE.md`:
`/second-brain:init-vault` offers to add it for you, and `/second-brain:doctor` reports whether
it's wired. The block tells Claude where the vault is and how to query it on demand (journal for
"what/when", wiki for "what do I know about X"). It's the canonical `assets/recall-instruction.md`.

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

- **It's a Markdown knowledge vault** (browse in Obsidian or any editor), not a code repo: topic folders, atomic notes, `[[wikilinks]]`, YAML
  frontmatter. The scaffolded `CLAUDE.md` documents the conventions.
- **The capture hook is global** — it fires on every session and writes to your configured
  `vault_path`. With no vault configured it is a silent no-op. Sessions run *inside* the vault are
  skipped (self-capture guard).
- **Namespacing.** Skills dispatch the bundled agents by their namespaced ids
  (`second-brain:librarian`, etc.); plugin agents don't resolve by bare name. If you rename this
  plugin, update those references in the three `skills/*/SKILL.md` files.
- **Tests.** `tests/test-session-capture.sh` covers the hook; `tests/librarian/test-tooling.sh`
  self-tests the filing-contract validator.
