<!-- second-brain:recall -->
## Second brain (your memory)

You keep a personal knowledge vault (a "second brain") at `<VAULT_PATH>`. Treat it as **your own
memory** — consult it **proactively**, not only when the user asks.

**Check the vault before asking the user** whenever you need information you don't already have:
a prior decision, how something was done before, a convention you established, or what's known
about a topic. Also read it when the user asks about past work or what they know about X.

- *What did I do / when* → read `<VAULT_PATH>/journal/<YYYY-MM>/<YYYY-MM-DD>.md`.
- *What do I know about X* → navigate `<VAULT_PATH>/index.md` → `wiki/index.md` → the topic's
  `index.md` → the note, following `summary:` frontmatter.

Cite the source note and verify against its `source:` provenance. File new sessions by running
`/second-brain:file-inbox` from inside the vault.
<!-- /second-brain:recall -->
