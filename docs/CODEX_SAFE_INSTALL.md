# Codex Safe Install

Use this path for local Codex testing from this fork. It avoids `.mcpb`, dynamic release downloads, and upstream self-update.

## Install From `main`

Run from a local Terminal session on macOS:

```bash
cd <repo>
git switch main
git pull --ff-only origin main
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
make release
mkdir -p ~/bin
rm -f ~/bin/CheICalMCP
cp .build/release/CheICalMCP ~/bin/CheICalMCP
chmod +x ~/bin/CheICalMCP
codesign --force --sign - ~/bin/CheICalMCP
~/bin/CheICalMCP --setup
codex mcp add che-ical-mcp -- ~/bin/CheICalMCP
codex mcp get che-ical-mcp
```

If TCC dialogs do not appear, run this from Terminal, not SSH:

```bash
tccutil reset Calendar com.checheng.CheICalMCP
tccutil reset Reminders com.checheng.CheICalMCP
~/bin/CheICalMCP --setup
```

## Runtime Safety Defaults

The hardened branch defaults to `CHE_ICAL_MCP_PROFILE=read` when the variable is absent. That exposes only Calendar/Reminders read/search tools and denies direct mutation calls before handler dispatch.

Use mutation profiles only for controlled local testing:

```bash
CHE_ICAL_MCP_PROFILE=write_safe ~/bin/CheICalMCP
CHE_ICAL_MCP_PROFILE=destructive ~/bin/CheICalMCP
```

`--self-update` is disabled unless the process explicitly sets:

```bash
CHE_ICAL_MCP_ENABLE_SELF_UPDATE=1 ~/bin/CheICalMCP --self-update
```

For Codex, keep `approval_mode = "approve"` on mutation tools in `~/.codex/config.toml` until the hardened branch is installed and verified.
