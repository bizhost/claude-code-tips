# Stack rules — drop your own here

Files in `~/.claude/rules/<stack>.md` are skill-gated checklists Claude reads
before touching code in that stack. Frontmatter `paths:` scopes a rule to matching
files (across **every project on this machine**); without `paths:`, the rule loads
globally. Each rule starts with `Invoke <skill-name> FIRST` — that's the
load-bearing line.

A **skill** is a Markdown file at `~/.claude/skills/<name>/SKILL.md` (or one a
plugin installs). Browse `~/.claude/skills/` or ask Claude "find a skill for X".
The skill name in your rule must match a real skill name exactly.

This repo ships `rules/` **empty** (just this README). Stack rules are
project-specific — flutter rules look nothing like react rules — so listing mine
would either pollute your context or imply they apply when they don't.

## Quick start

Save as `rules/<stack>.md` in this repo, run `./install.sh` to copy it to
`~/.claude/rules/`. Or write directly to `~/.claude/rules/<stack>.md`.

```markdown
---
paths:
  - "**/*.<ext>"          # ** is recursive — **/*.py matches src/a.py and src/sub/b.py
  - "**/<config-file>"
---
# <Stack> gate
Invoke `<skill-name>` skill FIRST. No skip.

Self-check before returning:
1. <footgun #1 — concrete, file:line style if you can>
2. <footgun #2>
3. <...stop at 7. More than that and you're documenting, not gating>
```

The first body line after the frontmatter MUST be `Invoke <skill-name> FIRST` —
Claude reads that line as the routing directive. A heading or comment above it
breaks the gate.

### Worked example — TypeScript

```markdown
---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/tsconfig*.json"
---
# TypeScript gate
Invoke `typescript-expert` skill FIRST. No skip.

Self-check before returning:
1. No `any` — use `unknown` then narrow, or write the proper type
2. No `as` casts unless commenting why the runtime guarantees the cast
3. No `enum` — use `as const` objects
4. Discriminated unions for state, never optional fields that are sometimes-set
5. `import type { Foo }` for type-only imports so they get stripped at runtime
```

If no skill matches your stack, keep the same shape but drop the `Invoke` line —
the numbered self-check is what does the work; the skill route is the fast-path
when one exists.

## Why a numbered checklist beats prose

Claude reads numbered lists as a routine to execute. "Always check mounted" gets
ignored. "1. `if (!ref.mounted) return;` after every `await`" gets ticked off.
Keep items concrete — paste the exact line you want, not a description of it.
