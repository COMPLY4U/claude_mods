import { expect, test } from 'claude-code/testing'

import { antwortzeile, anweisung, balken } from './register'

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
  expect(status.at(-1)).toBe('🟢 Kontext 42 % ████████░░░░░░░░░░░░ 84k / 200k')
  expect(toasts).toEqual([])

  await $.session.measure(messung(72))
  await $.session.measure(messung(75))
  expect(status.at(-1)).toContain('🟡 Kontext 75 %')
  expect(toasts.length).toBe(1)

  await $.session.measure(messung(90))
  expect(status.at(-1)).toContain('🔴 Kontext 90 %')
  expect(toasts.length).toBe(2)

  // nach /compact fällt die Füllung, die Warnungen gelten wieder
  await $.session.measure(messung(20))
  await $.session.measure(messung(71))
  expect(toasts.length).toBe(3)
})

test('Balken', () => {
  expect(balken(0)).toBe('░'.repeat(20))
  expect(balken(25)).toBe('█████' + '░'.repeat(15))
  expect(balken(100)).toBe('█'.repeat(20))
  expect(balken(130)).toBe('█'.repeat(20))
})

test('Antwortzeile und Beilage für das Modell', () => {
  const mit = (percent: number) => antwortzeile({ window: 1_000_000, tokens: percent * 10_000, percent })
  expect(mit(25)).toBe('> 🟢 **Kontext 25 %** `█████░░░░░░░░░░░░░░░` 250k / 1.000k')
  expect(mit(70)).toContain('🟡')
  expect(mit(70)).toContain('bald neuen Chat beginnen')
  expect(mit(85)).toContain('🔴')
  expect(mit(85)).toContain('**jetzt neuen Chat beginnen**')
  expect(antwortzeile({ window: 1_000_000 })).toContain('wird ab der nächsten Antwort gemessen')
  expect(anweisung({ window: 1_000_000 })).toContain('noch nicht gemessen')
  const text = anweisung({ window: 1_000_000, tokens: 212_000, percent: 21 })
  expect(text).toContain('zu 21 % gefüllt')
  expect(text).toContain('> 🟢 **Kontext 21 %**')
})
