import { expect, test } from 'claude-code/testing'

import { antwortzeile, anweisung } from './register'

const messung = (percent: number | undefined) => ({
  context: { window: 200_000, ...(percent === undefined ? {} : { percent, tokens: percent * 2000 }) },
  rateLimits: [],
  changed: ['context' as const],
})

test('zeigt die Prozentangabe und warnt je Schwelle genau einmal', async ($, on) => {
  const status: (string | undefined)[] = []
  const toasts: string[] = []
  on('ui.status', (_, e) => { status.push(e.text); return { value: undefined } })
  on('ui.toast', (_, e) => { toasts.push(e.text); return { value: undefined } })
  on('session.measure', (_, e) => ({ changed: e.changed }))

  await $.session.measure(messung(undefined))
  expect(status.at(-1)).toBe('Kontext: – (erscheint nach der ersten Antwort)')

  await $.session.measure(messung(42))
  expect(status.at(-1)).toBe('Kontext 42 % · 84k / 200k')
  expect(toasts).toEqual([])

  await $.session.measure(messung(72))
  await $.session.measure(messung(75))
  expect(status.at(-1)).toContain('⚠ Kontext 75 %')
  expect(toasts.length).toBe(1)

  await $.session.measure(messung(90))
  expect(status.at(-1)).toContain('⛔ Kontext 90 %')
  expect(toasts.length).toBe(2)

  // nach /compact fällt die Füllung, die Warnungen gelten wieder
  await $.session.measure(messung(20))
  await $.session.measure(messung(71))
  expect(toasts.length).toBe(3)
})

test('Antwortzeile und Beilage für das Modell', () => {
  expect(antwortzeile(69)).toBe('_Kontext: 69 %_')
  expect(antwortzeile(70)).toContain('bald neuen Chat')
  expect(antwortzeile(85)).toContain('jetzt neuen Chat')
  expect(anweisung({ window: 1_000_000 })).toBe(undefined)
  const text = anweisung({ window: 1_000_000, tokens: 212_000, percent: 21 }) ?? ''
  expect(text).toContain('zu 21 % gefüllt (212k von 1000k Token)')
  expect(text).toContain('_Kontext: 21 %_')
})
