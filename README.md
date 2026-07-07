# Claude Code Stack — team config

My `~/.claude` setup, packaged for git + team distribution: settings, enforcement
hooks, statusline, and a one-shot idempotent `install.sh`.

Stack: **CBM** (code knowledge graph) + **context-mode** (output sandbox) +
**RTK** (shell-command compression) + **Caveman** / **Ponytail** (output style) +
**Superpowers** / **Harness** / **Karpathy** skills + enforcement hooks.

> `install.sh` installs `rtk` **standalone** (rtk-ai/rtk) — **Headroom is not
> used at all**, and no shell rc is touched. Use `--no-rtk` to skip rtk entirely
> (the `rtk hook claude` hook is then stripped from your merged settings).

## Install

```bash
git clone <your-remote-url> claude-code-tips
cd claude-code-tips && chmod +x install.sh && ./install.sh
```

Sanity-checks `git`/`curl`/`jq`/`python3` first. Installs the rtk binary, the CBM
binary, the Claude Code plugins, hooks, statusline, and merges `settings.json` +
`CLAUDE.md`. **Idempotent** — re-run anytime.

### Flags

```bash
./install.sh --no-rtk       # skip rtk; strips `rtk hook claude` from merged settings
./install.sh --no-caveman   # skip Caveman plugin + omit it from settings
./install.sh --sonnet       # force model sonnet + effortLevel high (default is already sonnet/xhigh)
./install.sh --check        # validate repo wiring only, install nothing
```

### Existing setup? Non-destructive by design

- `~/.claude/CLAUDE.md` — your content preserved. Our framework is injected inside
  `<!--cct-->`/`<!--/cct-->` markers. Re-runs replace only inside the markers.
- `~/.claude/settings.json` — `jq` deep merge. Your `model`/`effortLevel`/
  `permissions`/custom env keys preserved; our `hooks` + framework env added.
- `~/.claude/{hooks,rules,commands}/*` — per-file: an existing target that differs
  is renamed to `<name>.bak.<timestamp>` before overwrite. Identical files are a no-op.
- `~/.claude/agents/*` — untouched. Keep private subagent definitions out of this repo.

### Validate

```bash
./install.sh --check
```

Asserts `settings.json` is valid JSON, every `~/.claude/hooks/*` command resolves
to a file in `hooks/`, and every `@include` in `CLAUDE.md.example` ships alongside it.

## Layout

| Path | Purpose |
|---|---|
| [`install.sh`](./install.sh) | Idempotent installer. `--check` / `--no-rtk` / `--no-caveman` / `--sonnet`. |
| [`settings/settings.json`](./settings/settings.json) | `~/.claude/settings.json` — model, effort, env, hooks, plugins, statusline. |
| [`CLAUDE.md.example`](./CLAUDE.md.example) | Body of `~/.claude/CLAUDE.md`. Injected inside `<!--cct-->` markers. Ends with `@RTK.md`. |
| [`RTK.md`](./RTK.md) | RTK reference, `@`-included by `CLAUDE.md`. Installed to `~/.claude/RTK.md`. |
| [`hooks/`](./hooks/) | Enforcement hooks (`bash-ban-raw-tools`, `cbm-*`, `context-mode-cache-heal.mjs`, `memory-repo-symlink`). |
| [`rules/`](./rules/) | **Empty by design** — your stack-specific gate rules. See [`rules/README.md`](./rules/README.md). |
| [`commands/`](./commands/) | Slash commands (empty by default). |
| [`statusline/statusline-command.sh`](./statusline/statusline-command.sh) | Statusline — user, branch, model, ctx%, usage. |
| [`.bashrc`](./.bashrc) | Drop-in bash config. `install.sh` does **not** touch your shell rc — append/replace manually. Puts `~/.local/bin` (rtk + cbm) on PATH. |

Skills come from the enabled plugins (superpowers / harness / karpathy / ponytail /
caveman); this repo ships no local `skills/`.

## Hook map

```
PreToolUse(Bash)      context-mode + bash-ban-raw-tools + rtk hook claude
PreToolUse(Grep|Glob) cbm-code-discovery-gate
PostToolUse           context-mode + cbm-mcp-marker
PreCompact            context-mode
SessionStart          context-mode + memory-repo-symlink + cbm-session-reminder
                      + context-mode-cache-heal.mjs
SessionStart(startup) cbm-session-reminder + karpathy-guidelines inject
```

## Externals (auto-installed by `install.sh`)

| Tool | Source |
|---|---|
| rtk (standalone) | https://github.com/rtk-ai/rtk |
| codebase-memory-mcp | https://github.com/DeusData/codebase-memory-mcp |
| context-mode plugin | https://github.com/mksglu/context-mode |
| caveman plugin | https://github.com/JuliusBrussee/caveman |
| ponytail plugin | https://github.com/DietrichGebert/ponytail |
| harness plugin | https://github.com/revfactory/harness |
| andrej-karpathy-skills plugin | https://github.com/forrestchang/andrej-karpathy-skills |
| superpowers / php-lsp | `claude-plugins-official` marketplace |
| tavily-cli (optional) | `npm install -g tavily-cli` |
