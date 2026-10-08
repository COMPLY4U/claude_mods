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
