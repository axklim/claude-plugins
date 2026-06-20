# Second-brain vault conventions

Provided live by the **second-brain** plugin at session start (it updates with the plugin — do
not copy this into the vault). Keep this file compact (it is injected into context).

## What this repository is

This is an **Obsidian vault** used as a personal knowledge base. It holds notes and
structured knowledge — **not** production code. There is nothing to build, lint, test, or
run. Markdown files are the content; `.obsidian/` is editor config, not knowledge.

The "development loop" here is **writing, organizing, and linking notes**. When asked to
add or change knowledge, edit Markdown — don't look for a project to compile.

## Organizing principle: keep knowledge on one topic together

This is the core convention for the vault.

- Organize by **topic**, not by date or file type. Each subject gets its own folder, and
  every note about that subject lives inside it — so related knowledge stays in one place.
- Favor a few broad top-level topic folders over deep nesting. Promote a topic to its own
  folder only once it has enough notes to stand alone; until then keep it as a single note
  inside the nearest existing topic.
- **One note = one idea/thing.** Keep notes atomic with descriptive titles — the filename
  is the note's identity and its `[[link]]` target.
- Connect related notes with `[[wikilinks]]` instead of duplicating content. When topics
  overlap, link them rather than copy.

## Note conventions

- **Frontmatter (properties):** begin each note with YAML frontmatter for metadata Obsidian
  can index — e.g. `tags`, `created`, `aliases`, `source`. Keep keys consistent across notes
  so they stay queryable (Bases and search rely on this).
- **Tags vs. folders:** folders capture a note's primary topic; `tags:` capture cross-cutting
  themes that span folders. Don't encode the same thing as both.
- **Links:** `[[Note title]]`, alias with `[[Note title|shown text]]`, deep-link with
  `[[Note title#Heading]]`. Unresolved links (no target file yet) are intentional — they
  mark notes worth creating later.
- **Attachments:** keep images/PDFs in an `attachments/` folder (top-level or per-topic) and
  embed with `![[file]]`.

## Editing existing notes

- Preserve wikilinks and headings other notes may point at. Renaming a note or heading breaks
  inbound `[[links]]` — if you rename, search the vault for the old title and update referrers.

## Obsidian specifics

- Enabled core plugins (`.obsidian/core-plugins.json`): daily notes, templates, canvas,
  properties, tags, graph, backlinks, bases. No community plugins are installed.
- `.canvas` and `.base` files are JSON managed by Obsidian — edit them in the app, not by
  hand, except for trivial changes. Bases views depend on consistent note frontmatter.
- `.obsidian/workspace.json` is gitignored (volatile per-session UI state); the other
  `.obsidian/` config files are tracked so vault settings travel with the repo.

## Commits & branches

Use **Conventional Commits** with the note's topic as the scope: `type(<topic>): summary`.

- `feat(<topic>):` — add a new note or new knowledge to a topic
- `docs(<topic>):` — expand or clarify an existing note
- `refactor(<topic>):` — reorganize, split, merge, or relink notes without changing meaning
- `chore:` — vault config (`.obsidian/`), `.gitignore`, or other housekeeping (no scope needed)

Branches: short descriptive names with no prefix (e.g. `add-claude-md`, `feat/<topic>`).

## The capture → file pipeline (how to read this vault)

This vault is the **Layer-3 library** of a personal memory system. Sessions are captured
automatically (a global `SessionEnd` hook copies transcripts to `raw/` + queues a pointer in
`inbox/`), and filed on demand by running **`/second-brain:file-inbox`**, which dispatches the `librarian`
(topical `wiki/`) and the journal pipeline (`journal-extractor` → `journal-grouper`, the
temporal `journal/`). The command owns the single commit; the subagents never commit.

- **To find when/what you did:** read `journal/<YYYY-MM>/<YYYY-MM-DD>.md` (temporal index).
  Day-files group work by **project → theme**, link wiki notes with bare `[[name]]`, and carry
  a hidden `<!-- sessions: ... -->` footer (provenance). They are maintained **incrementally**
  (new work is merged in, deduped) — existing content and any manual edits are preserved.
- **To re-derive a session's journal:** run **`/second-brain:rebuild-journal <sid>, ...`** — it re-extracts
  those sessions and merges their bullets into the day-files (non-destructive; never deletes).
  To reformat a day cleanly, delete that day-file yourself and run `/second-brain:rebuild-journal` naming
  every session that touched it.
- **To find what you know about X:** start at root `index.md` → `wiki/index.md` → the topic's
  `index.md` → the note. Navigate by `summary:` frontmatter and the MOC index files.
- **Cite on answer:** when you answer from the wiki, point at the source note and its `source:`
  provenance — verify, don't trust. The `raw/` transcript is ground truth.
- `raw/` (verbatim archive) and `inbox/` (transient, gitignored queue) are machine folders —
  don't hand-edit them. Prefer running `/second-brain:file-inbox` over hand-filing.
- **Never store knowledge content in this file.** `CLAUDE.md` holds instructions only.
