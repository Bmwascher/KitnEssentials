#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║  dev/scripts/setup-lua-toolchain.sh                      ║
# ║  Installs the headless test toolchain on Debian/Ubuntu.  ║
# ╚══════════════════════════════════════════════════════════╝
#
# Installs: lua5.4, luarocks, busted, luacheck, luafilesystem.
#
# Used by BOTH:
#   • GitHub Actions CI            (.github/workflows/test.yml)
#   • Claude Code on the web       — point the cloud environment's setup
#     script at this file so every cloud session has luacheck + busted and
#     the recurring "no Lua interpreter / no busted on this box" message
#     stops appearing.
#
# Safe to re-run. Requires sudo (CI runners and the cloud image both allow it).
set -euo pipefail

echo "==> apt: lua5.4 + luarocks + prebuilt busted/luafilesystem"
sudo apt-get update -qq
# busted + luafilesystem come prebuilt from apt (no compile step to fail on a
# clean runner); they pull the matching lua interpreter as a dependency.
sudo apt-get install -y -qq lua5.4 liblua5.4-dev luarocks lua-busted lua-filesystem

echo "==> luarocks: luacheck (not packaged in apt; pure-Lua, version-tolerant)"
sudo luarocks install luacheck

echo "==> versions"
lua5.4 -v
busted --version
luacheck --version | head -1
echo "Lua test toolchain ready."
