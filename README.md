# axklim — Claude Code plugin marketplace

A personal [Claude Code](https://code.claude.com) plugin marketplace. Add it once and the
plugins become installable in any project, on any machine or account.

## Install

```bash
# 1. Register this marketplace (GitHub owner/repo shorthand, or the full git URL)
/plugin marketplace add axklim/claude-plugins
#    or:  /plugin marketplace add https://github.com/axklim/claude-plugins.git

# 2. Install a plugin from it
/plugin install dev-workflow@axklim

# Later: pull updates
/plugin marketplace update
```

> The marketplace name (`axklim`) is what you type after `@` when installing; it's defined in
> `.claude-plugin/marketplace.json`, separate from the repo name.

## Plugins

| Plugin | What it gives you |
|--------|-------------------|
| [`dev-workflow`](plugins/dev-workflow) | Branch/PR lifecycle skills (`/premerge`, `/restructure-commits`, `/merge`), a docs-sync skill (`/docs`), and three review agents (code reviewer, Conventional-Commits message writer, documentation gap-finder). |
| [`second-brain`](plugins/second-brain) | An LLM-wiki memory pattern: a `SessionEnd` hook captures every session, then skills file it into a topical wiki + temporal journal. Plain Markdown — view in Obsidian or any editor. |

## Layout

```
.claude-plugin/marketplace.json   # marketplace manifest (lists the plugins below)
plugins/
├── dev-workflow/
│   ├── .claude-plugin/plugin.json
│   ├── skills/{premerge,restructure-commits,merge,docs}/SKILL.md
│   └── agents/{commit-message,documentation,reviewer}.md
└── second-brain/
    ├── .claude-plugin/plugin.json
    ├── hooks/{hooks.json,session-capture.sh}
    ├── skills/{init-vault,file-inbox,rebuild-journal}/SKILL.md
    ├── agents/{librarian,journal-extractor,journal-grouper}.md
    ├── assets/vault-template/        # scaffolded by /init-vault
    └── tests/
```

The marketplace and the plugin live in this one repo; each plugin entry in
`marketplace.json` points at its folder via a relative `source` path.
