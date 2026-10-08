#!/bin/bash
# comply4u-mods: holt bei jedem Start einer Cloud-Sitzung die aktuelle Fassung
# von https://github.com/COMPLY4U/claude_mods und installiert alle Mods des
# Marketplace für den Benutzer. Einmal eintragen, danach nie wieder ändern:
# Änderungen an den Mods kommen über GitHub.
# Protokoll: ~/.claude/comply4u-mods-setup.log. Bricht den Sitzungsstart nie ab.
(
  ZIEL="$HOME/.claude/comply4u-mods"
  mkdir -p "$HOME/.claude"
  {
    date
    rm -rf "$ZIEL"
    if ! GIT_TERMINAL_PROMPT=0 timeout 120 git clone --quiet --depth 1 https://github.com/COMPLY4U/claude_mods "$ZIEL"; then
      echo "FEHLER: GitHub-Repository nicht abrufbar, keine Mods installiert."
    elif ! command -v claude >/dev/null 2>&1; then
      echo "FEHLER: Befehl claude nicht gefunden, keine Mods installiert."
    else
      echo "Stand: $(git -C "$ZIEL" log -1 --format='%h %s')"
      claude plugin marketplace add "$ZIEL"
      for MOD in $(python3 -c 'import json, sys; print(*(p["name"] for p in json.load(open(sys.argv[1]))["plugins"]))' "$ZIEL/.claude-plugin/marketplace.json"); do
        claude plugin install "$MOD@comply4u-mods" --scope user
      done
      echo "OK"
    fi
  } > "$HOME/.claude/comply4u-mods-setup.log" 2>&1
) || true
