---
name: file-inbox
description: File the vault's pending inbox/ queue into the wiki and journal, then commit. Run from a second-brain vault to file captured sessions.
---

# File the inbox

You are filing the second-brain vault's pending queue. You are the trigger and the committer;
the subagents never commit. Run from the vault root.

## Step 0 — Pre-flight

List the pending queue:

```bash
ls -1 inbox/ 2>/dev/null | grep -v '^\.keep$' || true
```

If the list is empty, tell the user "inbox is empty — nothing to file" and STOP.

## Steps

1. **Resolve the queue.** For each `inbox/<...>.md` pointer, read its frontmatter
   (`session_id`, `raw_dir`). Build the list of **sessions** to file (sid + raw dir). Skip and
   report any pointer whose frontmatter won't parse.

2. **Wiki.** Dispatch the **`second-brain:librarian`** subagent with the resolved sessions. It
   writes/merges `wiki/` notes + indexes and records `metadata.json` provenance (wiki-only). It
   does not write the journal, delete pointers, or commit.

3. **Journal — extract (map).** For each session, dispatch the **`second-brain:journal-extractor`**
   subagent (sid + raw dir). Parse each returned message as a JSON array of items; tag every
   item with its source sid.

4. **Journal — group (reduce).** Bucket all items by `day`. For each day, dispatch the
   **`second-brain:journal-grouper`** subagent with `date`, that day's `items`, and `sessions` =
   the sids contributing items to that day. The grouper merges into the existing day-file (or
   creates it), deduping. (The librarian ran first, so the grouper's `wiki` links resolve.)

5. **Clear the queue.** `rm` each filed `inbox/` pointer (it is gitignored — never `git rm`).

6. **Commit.** `git add raw/ journal/ wiki/` then one Conventional Commit with the dominant
   topic as scope and no ticket prefix, e.g. `feat(widget-api): file 2 sessions into wiki + journal`.
   **Never `git push`.**

7. **Report:** sessions filed, journal days written, wiki notes created/updated, maintenance
   findings (from the librarian), and the commit SHA.
