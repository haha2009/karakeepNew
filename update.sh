#!/usr/bin/env bash
# update.sh - 框架更新检查与升级

set -eo pipefail

FWK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${FWK_DIR}/.framework-version"
REGISTRY_URL="https://raw.githubusercontent.com/haha2009/my-claude-fwk/main/.framework-version"

echo "═══════════════════════════════════════════"
echo "  MCF Framework Update"
echo "═══════════════════════════════════════════"
echo ""

# Current version
CURRENT=$(cat "$VERSION_FILE" 2>/dev/null || echo "unknown")
echo "Current version: ${CURRENT}"

# Fetch latest version
echo "Checking for updates..."
LATEST=$(curl -sL "$REGISTRY_URL" 2>/dev/null || echo "unknown")

if [[ "$LATEST" == "unknown" ]]; then
  echo "⚠️ Could not fetch latest version (network issue?)"
  echo "   Check manually: https://github.com/haha2009/my-claude-fwk"
  exit 1
fi

echo "Latest version:  ${LATEST}"
echo ""

if [[ "$CURRENT" == "$LATEST" ]]; then
  echo "✅ Already up to date (v${CURRENT})"
  exit 0
fi

echo "🔄 Update available: v${CURRENT} → v${LATEST}"
echo ""
read -p "Proceed with update? [Y/N]: " CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && { echo "Aborted."; exit 0; }

# Perform update via git
echo ""
echo "Pulling latest changes..."
if git -C "$FWK_DIR" pull origin main 2>/dev/null; then
  echo "✅ Updated to v${LATEST}"
  echo ""
  echo "Next steps:"
  echo "  1. Review CHANGELOG.md for breaking changes"
  echo "  2. Re-inject to projects: bash inject.sh /path/to/project"
else
  echo "❌ Update failed. Try manually:"
  echo "   cd ${FWK_DIR} && git pull origin main"
  exit 1
fi
