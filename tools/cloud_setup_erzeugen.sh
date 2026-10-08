#!/bin/bash
# Erzeugt cloud/setup.sh aus den Dateien unter plugins/. Nach jeder Änderung an
# einem Mod ausführen und das Ergebnis mit committen – so laufen Mod und
# Setup-Skript nie auseinander.
set -e
cd "$(dirname "$0")/.."
OUT=cloud/setup.sh
{
  echo '#!/bin/bash'
  echo '# ERZEUGT von tools/cloud_setup_erzeugen.sh – nicht von Hand ändern.'
  echo '# Schreibt die Mods dieses Repositorys bei jedem Start einer Cloud-Sitzung'
  echo '# nach ~/.claude/comply4u-mods und installiert sie für den Benutzer.'
  echo '# Bricht den Sitzungsstart nie ab.'
  echo '('
  echo 'set -e'
  echo 'MP="$HOME/.claude/comply4u-mods"'
  find .claude-plugin plugins -type f ! -path '*/types/*' ! -name '*.test.ts' | sort | while read -r f; do
    echo "mkdir -p \"\$MP/$(dirname "$f")\""
    echo "cat > \"\$MP/$f\" <<'__ENDE_DER_DATEI__'"
    cat "$f"
    echo '__ENDE_DER_DATEI__'
  done
  echo 'if command -v claude >/dev/null 2>&1; then'
  echo '  claude plugin marketplace add "$MP" >/dev/null 2>&1 || true'
  python3 -c 'import json;[print("  claude plugin install %s@comply4u-mods --scope user >/dev/null 2>&1 || true" % p["name"]) for p in json.load(open(".claude-plugin/marketplace.json"))["plugins"]]'
  echo 'fi'
  echo ') || echo "comply4u-mods: Einrichtung übersprungen" >&2'
} > "$OUT"
chmod +x "$OUT"
echo "geschrieben: $OUT"
