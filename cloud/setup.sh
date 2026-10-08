#!/bin/bash
# ERZEUGT von tools/cloud_setup_erzeugen.sh – nicht von Hand ändern.
# Schreibt die Mods dieses Repositorys bei jedem Start einer Cloud-Sitzung
# nach ~/.claude/comply4u-mods und installiert sie für den Benutzer.
# Bricht den Sitzungsstart nie ab.
(
set -e
MP="$HOME/.claude/comply4u-mods"
mkdir -p "$MP/.claude-plugin"
cat > "$MP/.claude-plugin/marketplace.json" <<'__ENDE_DER_DATEI__'
{
  "name": "comply4u-mods",
  "owner": { "name": "COMPLY4U" },
  "plugins": [
    {
      "name": "kontextanzeige",
      "source": "./plugins/kontextanzeige",
      "description": "Zeigt die Füllung des Kontextfensters als Prozentangabe in der Statuszeile und warnt ab 70 % und 85 %."
    }
  ]
}
__ENDE_DER_DATEI__
mkdir -p "$MP/plugins/kontextanzeige/.claude-plugin"
cat > "$MP/plugins/kontextanzeige/.claude-plugin/plugin.json" <<'__ENDE_DER_DATEI__'
{ "name": "kontextanzeige", "version": "0.1.0", "description": "Zeigt die Füllung des Kontextfensters als Prozentangabe in der Statuszeile und warnt ab 70 % und 85 %." }
__ENDE_DER_DATEI__
mkdir -p "$MP/plugins/kontextanzeige/hooks"
cat > "$MP/plugins/kontextanzeige/hooks/hooks.json" <<'__ENDE_DER_DATEI__'
{ "modules": ["./register.ts"] }
__ENDE_DER_DATEI__
mkdir -p "$MP/plugins/kontextanzeige/hooks"
cat > "$MP/plugins/kontextanzeige/hooks/register.ts" <<'__ENDE_DER_DATEI__'
import type { EngineInterface, Register, SessionContextUsage } from 'claude-code'

/** Ab hier wird gewarnt: erst ein Hinweis, dann die Aufforderung zum Chatwechsel. */
export const HINWEIS_AB = 70
export const WARNUNG_AB = 85

const tausend = (n: number) => `${Math.round(n / 1000)}k`

export function statuszeile(context: SessionContextUsage): string {
  const { percent, tokens, window } = context
  if (percent === undefined) return 'Kontext: – (erscheint nach der ersten Antwort)'
  const menge = tokens === undefined ? '' : ` · ${tausend(tokens)} / ${tausend(window)}`
  if (percent >= WARNUNG_AB) return `⛔ Kontext ${percent} %${menge} – jetzt neuen Chat beginnen`
  if (percent >= HINWEIS_AB) return `⚠ Kontext ${percent} %${menge} – bald neuen Chat beginnen`
  return `Kontext ${percent} %${menge}`
}

/** Die höchste überschrittene Schwelle, 0 darunter. */
const stufe = (percent: number | undefined) =>
  percent === undefined ? 0 : percent >= WARNUNG_AB ? WARNUNG_AB : percent >= HINWEIS_AB ? HINWEIS_AB : 0

// Zuletzt gemeldete Schwelle: Jede Schwelle meldet sich einmal beim
// Überschreiten; fällt die Füllung (nach /compact), wird wieder gemeldet.
let gemeldet = 0

function zeige($: EngineInterface, context: SessionContextUsage): void {
  $.ui.status(statuszeile(context))
  const jetzt = stufe(context.percent)
  if (jetzt > gemeldet) {
    $.ui.toast(
      jetzt >= WARNUNG_AB
        ? `Kontextfenster zu ${context.percent} % voll – jetzt einen neuen Chat beginnen.`
        : `Kontextfenster zu ${context.percent} % voll – bald einen neuen Chat beginnen.`,
      { timeoutMs: 8000 },
    )
  }
  gemeldet = jetzt
}

export const register: Register = on => {
  gemeldet = 0

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    zeige($, (await $.session.usage()).context)
    return result
  })

  on('session.measure', ($, e, next) => {
    if (e.changed.includes('context')) zeige($, e.context)
    return next(e)
  })
}
__ENDE_DER_DATEI__
if command -v claude >/dev/null 2>&1; then
  claude plugin marketplace add "$MP" >/dev/null 2>&1 || true
  claude plugin install kontextanzeige@comply4u-mods --scope user >/dev/null 2>&1 || true
fi
) || echo "comply4u-mods: Einrichtung übersprungen" >&2
