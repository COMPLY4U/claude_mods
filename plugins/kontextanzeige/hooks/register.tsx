import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, SessionContextUsage } from 'claude-code'


/** Herkunftsarten einer Nachricht, die die Person selbst geschrieben hat. */
const VON_DER_PERSON: ReadonlySet<string> = new Set(['composer', 'bridge', 'sdk'])

/** Die zuletzt gezeigte Zeile: Statuszeile und Band über dem Eingabefeld lesen dieselbe. */
const zeile = atom({ plugin: 'kontextanzeige', key: 'zeile' } as const, null)


/** Ab hier wird gewarnt: erst ein Hinweis, dann die Aufforderung zum Chatwechsel. */
export const HINWEIS_AB = 70
export const WARNUNG_AB = 85

/** Tausender in k, mit deutschem Tausenderpunkt: 251k, 1.000k. */
const tausend = (n: number) => `${String(Math.round(n / 1000)).replace(/\B(?=(\d{3})+$)/g, '.')}k`

/** Segmente des Balkens; eines steht für 5 %. */
export const SEGMENTE = 20

/** Der Balken: gefüllte Segmente für die Füllung, aufgerundet erst ab einem halben Segment. */
export function balken(percent: number): string {
  const voll = Math.min(SEGMENTE, Math.max(0, Math.round((percent / 100) * SEGMENTE)))
  return '█'.repeat(voll) + '░'.repeat(SEGMENTE - voll)
}

/** Farbpunkt und Hinweis je Stufe: grün bis 69 %, gelb ab 70 %, rot ab 85 %. */
function ampel(percent: number): { punkt: string; hinweis: string } {
  if (percent >= WARNUNG_AB) return { punkt: '🔴', hinweis: ' · **jetzt neuen Chat beginnen**' }
  if (percent >= HINWEIS_AB) return { punkt: '🟡', hinweis: ' · bald neuen Chat beginnen' }
  return { punkt: '🟢', hinweis: '' }
}

export function statuszeile(context: SessionContextUsage): string {
  const { percent, tokens, window } = context
  if (percent === undefined) return 'Kontext: – (erscheint nach der ersten Antwort)'
  const menge = tokens === undefined ? '' : ` ${tausend(tokens)} / ${tausend(window)}`
  const { punkt, hinweis } = ampel(percent)
  return `${punkt} Kontext ${percent} % ${balken(percent)}${menge}${hinweis.replace(/\*\*/g, '')}`
}

/**
 * Die Zeile, mit der Claude seine Antwort beginnt, als Zitatblock: Sie ist die
 * einzige Anzeige, die jede Oberfläche zeigt. Die Desktop-App zeichnet bei
 * Cloud-Sitzungen weder Statuszeile noch Band noch Einblendung.
 */
export function antwortzeile(context: SessionContextUsage): string {
  const { percent, tokens, window } = context
  if (percent === undefined) return '> ⚪ **Kontext** · wird ab der nächsten Antwort gemessen'
  const menge = tokens === undefined ? '' : ` ${tausend(tokens)} / ${tausend(window)}`
  const { punkt, hinweis } = ampel(percent)
  return `> ${punkt} **Kontext ${percent} %** \`${balken(percent)}\`${menge}${hinweis}`
}

/** Was der Nachricht unsichtbar für das Modell beiliegt. */
export function anweisung(context: SessionContextUsage): string {
  const stand =
    context.percent === undefined
      ? 'Die Füllung des Kontextfensters ist noch nicht gemessen (erste Nachricht oder direkt nach dem Zusammenfassen).'
      : `Das Kontextfenster dieses Chats ist vor dieser Nachricht zu ${context.percent} % gefüllt.`
  return [
    `[Mod kontextanzeige] ${stand}`,
    'Beginne deine Antwort mit genau dieser Zeile und einer Leerzeile danach, ohne sie zu kommentieren:',
    antwortzeile(context),
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
    return next({ ...e, context: [...(e.context ?? []), text] })
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
