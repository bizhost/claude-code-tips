#!/bin/bash
set -euo pipefail

print_usage() {
  cat <<'EOF'
Claude Code stack installer (konat / team distribution)

Usage:
  ./install.sh [options]

Default:
  Installs the rtk binary (standalone, rtk-ai/rtk — Headroom NOT used), CBM,
  Claude Code plugins (context-mode, caveman, ponytail, harness,
  andrej-karpathy-skills, superpowers, php-lsp), hooks, statusline, and
  merges settings.json + CLAUDE.md.

  No shell rc is touched.

Options:
  --check        Validate repo settings/hooks without installing.
  --no-caveman   Skip the Caveman plugin and omit it from merged settings.
  --no-rtk       Skip rtk install and strip the `rtk hook claude` hook.
  --sonnet       Use `model: sonnet` + `effortLevel: high` instead of Opus/xhigh.
  -h, --help     Show this help.

Examples:
  ./install.sh
  ./install.sh --no-rtk
  ./install.sh --no-caveman --sonnet
  ./install.sh --check
EOF
}

CHECK_ONLY=0
INSTALL_CAVEMAN=1
INSTALL_RTK=1
MODEL_PROFILE="power"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)      CHECK_ONLY=1; shift ;;
    --no-caveman) INSTALL_CAVEMAN=0; shift ;;
    --no-rtk)     INSTALL_RTK=0; shift ;;
    --sonnet)     MODEL_PROFILE="sonnet"; shift ;;
    -h|--help)    print_usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; print_usage >&2; exit 2 ;;
  esac
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_SOURCE="$REPO_DIR/settings/settings.json"
SETTINGS_TMP=""

cleanup_tmp() { [[ -n "${SETTINGS_TMP:-}" ]] && rm -f "$SETTINGS_TMP"; return 0; }
trap cleanup_tmp EXIT

# Apply CLI-flag transforms to the settings source before install/check so the
# merge and validator both see the same shape the user asked for.
prepare_settings_source() {
  local filter='.'
  if [[ "$INSTALL_CAVEMAN" -eq 0 ]]; then
    filter="$filter | del(.enabledPlugins[\"caveman@caveman\"]) | del(.extraKnownMarketplaces.caveman)"
  fi
  if [[ "$INSTALL_RTK" -eq 0 ]]; then
    # Drop the `rtk hook claude` entry from every hook group; prune emptied groups.
    filter="$filter | .hooks.PreToolUse |= map(.hooks |= map(select(.command != \"rtk hook claude\"))) | .hooks.PreToolUse |= map(select((.hooks | length) > 0))"
  fi
  if [[ "$MODEL_PROFILE" == "sonnet" ]]; then
    filter="$filter | .model = \"sonnet\" | .effortLevel = \"high\""
  fi
  if [[ "$filter" != "." ]]; then
    SETTINGS_TMP="$(mktemp)"
    jq "$filter" "$REPO_DIR/settings/settings.json" > "$SETTINGS_TMP"
    SETTINGS_SOURCE="$SETTINGS_TMP"
  fi
}

# ── Validator mode ──
if [[ "$CHECK_ONLY" -eq 1 ]]; then
  echo "=== install.sh --check ==="
  fail=0

  if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: jq not installed (required by hooks + check mode)"; fail=1
  else
    prepare_settings_source
    jq empty "$SETTINGS_SOURCE" 2>/dev/null || { echo "FAIL: settings/settings.json is not valid JSON"; fail=1; }
  fi

  # Every ~/.claude/hooks/<name> command in settings must exist in repo hooks/
  if command -v jq >/dev/null 2>&1; then
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue
      hook_path="${cmd//\~/$HOME}"; hook_path="${hook_path%% *}"
      [[ "$hook_path" == "$HOME/.claude/hooks/"* ]] || continue
      hook_name="${hook_path##*/}"
      [[ -f "$REPO_DIR/hooks/$hook_name" ]] || { echo "FAIL: settings references hook '$hook_name' but $REPO_DIR/hooks/$hook_name missing"; fail=1; }
    done < <(jq -r '[.. | objects | select(.command? != null) | .command] | .[]' "$SETTINGS_SOURCE")
  fi

  # CLAUDE.md.example @-includes must be shipped alongside it
  if [[ -f "$REPO_DIR/CLAUDE.md.example" ]]; then
    while IFS= read -r inc; do
      [[ -f "$REPO_DIR/$inc" ]] || { echo "FAIL: CLAUDE.md.example @-includes '$inc' but $REPO_DIR/$inc missing"; fail=1; }
    done < <(grep -oE '^@[A-Za-z0-9._/-]+' "$REPO_DIR/CLAUDE.md.example" 2>/dev/null | sed 's/^@//')
  fi

  if [[ $fail -eq 0 ]]; then
    echo "OK: settings valid, all hook paths and @-includes resolve"; exit 0
  fi
  exit 1
fi

echo "=== Claude Code stack — install ==="
echo "Model profile: $([[ "$MODEL_PROFILE" == sonnet ]] && echo sonnet/high || echo opus/xhigh)"
echo "Caveman: $([[ "$INSTALL_CAVEMAN" -eq 1 ]] && echo enabled || echo skipped)"
echo "RTK: $([[ "$INSTALL_RTK" -eq 1 ]] && echo 'enabled (rtk hook claude)' || echo 'skipped')"
echo ""

# ── 0. Sanity-check required tools ──
missing=""
for cmd in git curl jq python3; do command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"; done
if [[ -n "$missing" ]]; then
  echo "❌ Missing required tools:$missing"
  echo "   macOS:  brew install$missing"
  echo "   Debian: sudo apt-get install -y$missing"
  exit 1
fi

prepare_settings_source

# ── 1. rtk binary (standalone — rtk-ai/rtk; Headroom NOT used) ──
# `rtk hook claude` (PreToolUse) needs the rtk binary on PATH. Installed via the
# official standalone installer — no Headroom, no shell rc changes. Our
# settings.json already wires the hook, so we install the binary only (skip
# `rtk init`, which would add its own duplicate hook).
if [[ "$INSTALL_RTK" -eq 1 ]]; then
  echo "→ Installing rtk (standalone, rtk-ai/rtk)..."
  if command -v rtk >/dev/null 2>&1; then
    echo "  ✓ rtk already on PATH ($(rtk --version 2>/dev/null))"
  else
    if curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh 2>/dev/null; then :
    elif command -v brew  >/dev/null 2>&1 && brew install rtk 2>/dev/null; then :
    elif command -v cargo >/dev/null 2>&1 && cargo install --git https://github.com/rtk-ai/rtk 2>/dev/null; then :
    else
      echo "  ⚠ rtk auto-install failed. Install manually (any one):"
      echo "      curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
      echo "      brew install rtk                              # macOS"
      echo "      cargo install --git https://github.com/rtk-ai/rtk"
    fi
    command -v rtk >/dev/null 2>&1 \
      && echo "  ✓ rtk installed ($(rtk --version 2>/dev/null))" \
      || echo "  ⚠ rtk still not on PATH — ensure its install dir (usually ~/.local/bin) is on PATH."
  fi
else
  echo "→ Skipping rtk (--no-rtk); 'rtk hook claude' stripped from merged settings."
fi

# ── 2. codebase-memory-mcp ──
# Delegate to CBM's official installer. On Linux it fetches the fully-static
# *-portable build (the standard build dynamically links glibc 2.38+ and fails
# on older distros/containers with "version `GLIBC_2.38' not found"), verifies
# the binary runs, and installs to ~/.local/bin. Reinstall if an existing binary
# won't run here (e.g. a stale glibc-linked build) — a plain -x check can't tell.
echo "→ Installing codebase-memory-mcp..."
CBM_BIN="$HOME/.local/bin/codebase-memory-mcp"
CBM_INSTALLER="https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh"
if command -v timeout >/dev/null 2>&1; then CBM_TO="timeout 60"; else CBM_TO=""; fi
if [[ -x "$CBM_BIN" ]] && $CBM_TO "$CBM_BIN" --version >/dev/null 2>&1; then
  echo "  ✓ CBM already installed and runnable ($($CBM_TO "$CBM_BIN" --version 2>/dev/null))"
else
  [[ -x "$CBM_BIN" ]] && echo "  … existing CBM binary won't run here — reinstalling via official installer"
  if curl -fsSL "$CBM_INSTALLER" | bash; then
    echo "  ✓ CBM installed via official installer"
  else
    echo "  ⚠ CBM install failed. Run manually:  curl -fsSL $CBM_INSTALLER | bash"
  fi
fi

# ── 3. Claude Code plugins ──
# Plugin install (not raw `mcp add`) so context-mode tools resolve under the
# mcp__plugin_context-mode_context-mode__* namespace the skills expect.
echo "→ Installing Claude Code plugins..."
if ! command -v claude >/dev/null 2>&1; then
  echo "  ⚠ 'claude' CLI not on PATH — install Claude Code, then re-run ./install.sh."
else
  # marketplace <slug>  <github repo>
  add_marketplace() { claude plugin marketplace add "$2" 2>/dev/null || echo "  (add marketplace $2 manually)"; }
  install_plugin()  { claude plugin install "$1" 2>/dev/null || echo "  (install $1 manually)"; }

  add_marketplace context-mode      mksglu/context-mode
  add_marketplace ponytail          DietrichGebert/ponytail
  add_marketplace harness-marketplace revfactory/harness
  add_marketplace karpathy-skills   forrestchang/andrej-karpathy-skills
  [[ "$INSTALL_CAVEMAN" -eq 1 ]] && add_marketplace caveman JuliusBrussee/caveman

  install_plugin context-mode@context-mode
  install_plugin ponytail@ponytail
  install_plugin harness@harness-marketplace
  install_plugin andrej-karpathy-skills@karpathy-skills
  install_plugin superpowers@claude-plugins-official
  install_plugin php-lsp@claude-plugins-official
  [[ "$INSTALL_CAVEMAN" -eq 1 ]] && install_plugin caveman@caveman
fi

# ── Helpers ──
cp_with_backup() {
  local src="$1" dst="$2"
  if [[ -f "$dst" ]] && ! cmp -s "$src" "$dst"; then cp "$dst" "$dst.bak.$(date +%s).$$"; fi
  cp "$src" "$dst"
}

# Prepend framework body into ~/.claude/CLAUDE.md inside <!--cct--> markers.
# Re-runs replace the block in place; content outside markers is preserved.
inject_claude_md() {
  local target="$HOME/.claude/CLAUDE.md" source="$REPO_DIR/CLAUDE.md.example"
  local ms='<!--cct-->' me='<!--/cct-->'
  _write_block() {
    echo "$ms"; cat "$source"
    [[ -z "$(tail -c 1 "$source" 2>/dev/null)" ]] || echo
    echo "$me"
  }
  if [[ ! -f "$target" ]]; then _write_block > "$target"; echo "  ✓ CLAUDE.md created (wrapped in <!--cct--> markers)"; return; fi
  if [[ -L "$target" ]]; then
    local r; r="$(readlink -f "$target" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$target")"
    echo "  ℹ CLAUDE.md is a symlink → $r (editing the real file)"; target="$r"
  fi
  if grep -qF "$ms" "$target" && ! grep -qF "$me" "$target"; then
    echo "  ✗ CLAUDE.md has <!--cct--> start but no end marker. Fix manually. Aborting CLAUDE.md step."; return 1
  fi
  local bs; bs="$(date +%s).$$"
  if grep -qF "$ms" "$target"; then
    awk -v ms="$ms" -v me="$me" -v src="$source" '
      $0==ms{print; while((getline l<src)>0)print l; close(src); skip=1; next}
      $0==me{print; skip=0; next} !skip{print}' "$target" > "$target.tmp"
    if cmp -s "$target" "$target.tmp"; then rm -f "$target.tmp"; echo "  ✓ CLAUDE.md block already up to date"
    else cp "$target" "$target.bak.$bs"; mv "$target.tmp" "$target"; echo "  ✓ CLAUDE.md block updated (content outside markers preserved)"; fi
  else
    { _write_block; echo ""; cat "$target"; } > "$target.tmp"
    cp "$target" "$target.bak.$bs"; mv "$target.tmp" "$target"; echo "  ✓ CLAUDE.md prepended (your existing content kept below the block)"
  fi
}

# Deep jq merge: keep user model/effort/permissions/env; we own hooks; union plugins.
merge_settings_json() {
  local target="$HOME/.claude/settings.json" source="$SETTINGS_SOURCE"
  if [[ ! -f "$target" ]]; then cp "$source" "$target"; echo "  ✓ settings.json created"; return; fi
  if [[ -L "$target" ]]; then
    local r; r="$(readlink -f "$target" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$target")"
    echo "  ℹ settings.json is a symlink → $r (editing the real file)"; target="$r"
  fi
  local bs; bs="$(date +%s).$$"
  if jq -s '
    .[0] as $ours | .[1] as $theirs |
    ($ours * $theirs)
    | .hooks = $ours.hooks
    | .env = (($theirs.env // {}) * ($ours.env // {}))
    | .enabledPlugins = (($theirs.enabledPlugins // {}) * ($ours.enabledPlugins // {}))
    | .extraKnownMarketplaces = (($theirs.extraKnownMarketplaces // {}) * ($ours.extraKnownMarketplaces // {}))
    | .model //= $ours.model
    | .effortLevel //= $ours.effortLevel
    | .advisorModel //= $ours.advisorModel
    | .statusLine //= $ours.statusLine
  ' "$source" "$target" > "$target.tmp" 2>/dev/null; then
    if diff -q <(jq -S . "$target" 2>/dev/null) <(jq -S . "$target.tmp" 2>/dev/null) >/dev/null 2>&1; then
      rm -f "$target.tmp"; echo "  ✓ settings.json already up to date"
    else
      cp "$target" "$target.bak.$bs"; mv "$target.tmp" "$target"
      echo "  ✓ settings.json merged (your model/effortLevel/permissions preserved if set)"
    fi
  else
    rm -f "$target.tmp"; cp "$target" "$target.bak.$bs"; cp "$source" "$target"
    echo "  ⚠ jq merge failed — wrote ours; your file backed up at $target.bak.$bs"
  fi
}

# ensure_mcp_json: register the codebase-memory-mcp server in ~/.claude/.mcp.json
# ourselves (with the installed binary's absolute path) rather than trusting
# `cbm setup claude-code`, which no-ops when the claude CLI isn't present.
# Merges into an existing file, preserving any other MCP servers.
ensure_mcp_json() {
  local target="$HOME/.claude/.mcp.json" bin="$HOME/.local/bin/codebase-memory-mcp"
  [[ -x "$bin" ]] || { echo "  - CBM binary absent — skipping .mcp.json registration"; return 0; }
  mkdir -p "$HOME/.claude"
  if [[ -f "$target" ]]; then
    local tmp; tmp="$(mktemp)"
    if jq --arg b "$bin" '.mcpServers["codebase-memory-mcp"] = {"command":$b}' "$target" > "$tmp" 2>/dev/null; then
      if diff -q <(jq -S . "$target" 2>/dev/null) <(jq -S . "$tmp" 2>/dev/null) >/dev/null 2>&1; then
        rm -f "$tmp"; echo "  ✓ .mcp.json already registers codebase-memory-mcp"
      else
        cp "$target" "$target.bak.$(date +%s).$$"; mv "$tmp" "$target"; echo "  ✓ .mcp.json: codebase-memory-mcp registered (other servers preserved)"
      fi
    else
      rm -f "$tmp"; echo "  ⚠ .mcp.json exists but isn't valid JSON — left untouched"
    fi
  else
    jq -n --arg b "$bin" '{mcpServers:{"codebase-memory-mcp":{command:$b}}}' > "$target"
    echo "  ✓ .mcp.json created (codebase-memory-mcp registered)"
  fi
}

# ── 5. Copy hooks, rules, commands ──
echo "→ Copying hooks, rules, commands..."
mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/rules" "$HOME/.claude/commands"
for src in "$REPO_DIR/hooks/"*;      do [[ -f "$src" ]] && cp_with_backup "$src" "$HOME/.claude/hooks/$(basename "$src")"; done
for src in "$REPO_DIR/rules/"*.md;   do [[ -f "$src" ]] && cp_with_backup "$src" "$HOME/.claude/rules/$(basename "$src")"; done
for src in "$REPO_DIR/commands/"*.md; do [[ -f "$src" ]] && cp_with_backup "$src" "$HOME/.claude/commands/$(basename "$src")"; done
chmod +x "$HOME/.claude/hooks/"* 2>/dev/null || true

# ── 6. Statusline ──
echo "→ Installing statusline..."
cp_with_backup "$REPO_DIR/statusline/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
chmod +x "$HOME/.claude/statusline-command.sh"

# ── 8. RTK.md (referenced by CLAUDE.md via @RTK.md) ──
if [[ -f "$REPO_DIR/RTK.md" ]]; then
  echo "→ Installing RTK.md..."
  cp_with_backup "$REPO_DIR/RTK.md" "$HOME/.claude/RTK.md"
fi

# ── 8b. Register codebase-memory-mcp as an MCP server ──
echo "→ Registering codebase-memory-mcp (.mcp.json)..."
ensure_mcp_json

# ── 9. CLAUDE.md framework block ──
echo "→ Injecting CLAUDE.md framework block..."
inject_claude_md

# ── 10. settings.json deep merge ──
echo "→ Merging settings.json..."
merge_settings_json

# ── 11. Validate ──
echo "→ Validating..."
if "$REPO_DIR/install.sh" --check >/dev/null 2>&1; then
  echo "  ✓ settings, hook paths, and @-includes resolve"
else
  echo "  ⚠ ./install.sh --check reported issues — re-run for details"
fi

echo ""
echo "=== Installation Complete ==="
echo "Next steps:"
echo "  1. Ensure ~/.local/bin is on PATH (rtk + cbm live there)."
echo "  2. Start 'claude' in a project — CBM prompts to index on first use."
echo "  3. Re-run './install.sh --check' anytime to validate config."
echo ""
echo "Repos:  CBM https://github.com/DeusData/codebase-memory-mcp"
echo "        context-mode https://github.com/mksglu/context-mode"
echo "        rtk https://github.com/rtk-ai/rtk"
