<!-- second-brain:recall -->
## Second brain

You keep a personal knowledge vault (a "second brain") at `<VAULT_PATH>`. Consult it on demand:

- *What did I do / when* → read `<VAULT_PATH>/journal/<YYYY-MM>/<YYYY-MM-DD>.md`.
- *What do I know about X* → navigate `<VAULT_PATH>/index.md` → `wiki/index.md` → the topic's
  `index.md` → the note, following `summary:` frontmatter.

Read the vault when the user asks about past work, prior decisions, or what they know about a
topic — cite the source note and verify against its `source:` provenance. File new sessions by
running `/second-brain:file-inbox` from inside the vault.
<!-- /second-brain:recall -->
