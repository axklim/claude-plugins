---
name: rebuild-journal
description: >-
  Re-extract one or more captured sessions and merge their work into the journal day-files,
  non-destructively (never deletes a journal file). Run from inside a second-brain vault, naming
  the session ids to rebuild, e.g. "/second-brain:rebuild-journal <sid>, <sid>". To force a clean
  reformat of a day, the user deletes that day-file first, then runs this naming every session
  that touched it.
---

# Rebuild journal day-files

You are rebuilding journal day-files from named sessions. The user passes a comma/space-separated
list of session ids (full UUIDs or unambiguous prefixes) as the argument. Run from the vault root.

This is **non-destructive**: it NEVER deletes a journal file. It re-extracts the named sessions
and merges their bullets into the relevant day-files (creating any that are absent), deduping.

## Steps

1. **Resolve sessions.** For each id in the argument, glob `raw/**/<id>*.jsonl`. Map each to its
   sid (filename up to the first `.`) and its raw directory. Drop duplicate sids. Report and skip
   any id that matches no transcript. If nothing resolves, say so and STOP.

2. **Pre-flight.** Print the resolved sids you will process.

3. **Extract (map).** For each resolved session, dispatch the **`second-brain:journal-extractor`**
   subagent, telling it the sid and its raw dir. Parse each returned message as a JSON array of
   items; tag every item with its source sid. If a subagent returns no parseable items, report it
   and continue.

4. **Group (reduce).** Bucket all items by their `day`. For each day, dispatch the
   **`second-brain:journal-grouper`** subagent with: `date` = that day, `items` = that day's items
   (`project/theme/text/wiki`), and `sessions` = the full UUIDs of the sids that contributed items
   to that day. The grouper merges into the existing day-file (or creates it), deduping.

5. **Commit.** `git add journal/` then commit
   `refactor(journal): rebuild <N> day-file(s) from <M> session(s)` (scope by the dominant
   project if obvious). **Never `git push`.**

6. **Report:** sessions processed, day-files written, the commit SHA.
