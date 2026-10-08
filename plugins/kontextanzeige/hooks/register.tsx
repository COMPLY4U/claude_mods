import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, SessionContextUsage } from 'claude-code'


/** Herkunftsarten einer Nachricht, die die Person selbst geschrieben hat. */
const VON_DER_PERSON: ReadonlySet<string> = new Set(['composer', 'bridge', 'sdk'])

/** Die zuletzt gezeigte Zeile: Statuszeile und Band über dem Eingabefeld lesen dieselbe. */
const zeile = atom({ plugin: 'kontextanzeige', key: 'zeile' } as const, null)


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

/**
 * Die Zeile, mit der Claude seine Antwort beginnt. Sie ist die einzige Anzeige,
 * die jede Oberfläche zeigt: Die Desktop-App zeichnet bei Cloud-Sitzungen
 * weder Statuszeile noch Band noch Einblendung.
 */
export function antwortzeile(percent: number): string {
  if (percent >= WARNUNG_AB) return `_⛔ Kontext: ${percent} % – jetzt neuen Chat beginnen_`
  if (percent >= HINWEIS_AB) return `_⚠ Kontext: ${percent} % – bald neuen Chat beginnen_`
  return `_Kontext: ${percent} %_`
}

/** Was der Nachricht unsichtbar für das Modell beiliegt. */
export function anweisung(context: SessionContextUsage): string | undefined {
  if (context.percent === undefined) return undefined
  const menge = context.tokens === undefined ? '' : ` (${tausend(context.tokens)} von ${tausend(context.window)} Token)`
  return [
    `[Mod kontextanzeige] Das Kontextfenster dieses Chats ist vor dieser Nachricht zu ${context.percent} % gefüllt${menge}.`,
    'Beginne deine Antwort mit genau dieser Zeile und einer Leerzeile danach, ohne sie zu kommentieren:',
    antwortzeile(context.percent),
  ].join('\n')
}

/** Die höchste überschrittene Schwelle, 0 darunter. */
const stufe = (percent: number | undefined) =>
  percent === undefined ? 0 : percent >= WARNUNG_AB ? WARNUNG_AB : percent >= HINWEIS_AB ? HINWEIS_AB : 0

// Zuletzt gemeldete Schwelle: Jede Schwelle meldet sich einmal beim
// Überschreiten; fällt die Füllung (nach /compact), wird wieder gemeldet.
let gemeldet = 0

async function zeige($: EngineInterface, context: SessionContextUsage): Promise<void> {
  const text = statuszeile(context)
  $.ui.status(text)
  await update($, zeile, () => text)
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
    await zeige($, (await $.session.usage()).context)
    return result
  })

  on('session.measure', async ($, e, next) => {
    if (e.changed.includes('context')) await zeige($, e.context)
    return next(e)
  })

  // Nur an Nachrichten der Person (Eingabefeld, App, Cloud-Sitzung):
  // Benachrichtigungen, andere Sitzungen und Plugins bekommen keine Zeile.
  on('prompt.submit', async ($, e, next) => {
    if (!VON_DER_PERSON.has(e.origin.kind)) return next(e)
    const text = anweisung((await $.session.usage()).context)
    return next(text === undefined ? e : { ...e, context: [...(e.context ?? []), text] })
  }).catch(($, e, next) => next(e)) // ein Fehler hier hält keine Nachricht auf

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const text = await read($, zeile)
    if (text === null || e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box>
        <Text dimColor>{text}</Text>
      </Box>
    )
  })
}
