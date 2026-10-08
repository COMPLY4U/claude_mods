# Validator, Testkit und Typprüfung – was dort gilt

## Validator (`claude plugin validate`)

- Eine Hilfsfunktion, der `$` übergeben wird, muss **auf oberster Ebene** stehen
  (`function zeige($: EngineInterface, …)` oder eine `const`, die an eine solche gebunden
  ist). Eine Pfeilfunktion innerhalb von `register` wird abgewiesen.
- Kein dynamisches `import()`, auch nicht in Tests; eigene Dateien über eine
  `import`-Deklaration einbinden.
- Werte in `$.state` (über `atom`) brauchen einen Vertrag: `types/index.d.ts`, in
  `plugin.json` als `"types": "./types/index.d.ts"`. Der Vertrag exportiert **nur Typen**
  (`export type …`) und erweitert `interface PluginState` in `declare module 'claude-code'`.
  Ein `export {}` wird abgewiesen. Im Modul selbst wird der Vertrag nicht importiert.
- Ein `prompt.submit`-Hook gilt als „gating“ und will ein `.catch`.

## Testkit (`claude plugin test`, `import { expect, test } from 'claude-code/testing'`)

- Die Hooks des Tests stehen **unter** dem Plugin und vertreten den Engine. Ein Hook für
  ein Ereignis ohne Ergebnis (`ui.status`, `ui.toast`) muss `{ value: undefined }`
  zurückgeben; `undefined`, `null` und `{}` werden abgewiesen.
- Abfragen wie `session.usage` beantwortet der Test ebenfalls mit `{ value: … }`.
- `$.prompt.submit` aus dem Test trägt die Herkunft eines Plugins, nicht `composer`; ein Mod,
  der nur Nachrichten der Person bedient, übergeht sie. Deshalb die Textbausteine als reine,
  exportierte Funktionen schreiben und diese direkt testen.
- Ereignisse mit Ergebnis (`session.measure`) beantwortet der Test-Hook mit dem passenden
  Ergebnis, z. B. `({ changed: e.changed })`.

## Typprüfung

Vor dem ersten Laden liegt im Mod-Ordner noch keine `tsconfig.json`. Eine eigene außerhalb des
Mod-Ordners anlegen (Scratchpad), mit der Typdatei aus `plugin-authoring`:

```json
{ "compilerOptions": { "target": "es2023", "lib": ["es2023"], "types": [],
    "module": "esnext", "moduleResolution": "bundler", "strict": true,
    "noUncheckedIndexedAccess": true, "noEmit": true, "skipLibCheck": true,
    "jsx": "react", "jsxFactory": "h", "jsxFragmentFactory": "Fragment" },
  "include": ["<Typdatei>", "<mod>/hooks", "<mod>/types"] }
```

`tsc -p <Ordner dieser tsconfig>`. In Tests ohne Endung importieren (`'./register'`),
`'./register.tsx'` verlangt eine Compiler-Option, die hier nicht gesetzt ist.

## Setup-Skript

- `GIT_TERMINAL_PROMPT=0` vor `git clone`, sonst wartet ein Start auf eine Passworteingabe.
- Mod-Namen aus `marketplace.json` als JSON lesen (`python3 -c 'import json…'`), nicht mit
  `sed`: Das Muster `"name"` trifft auch den Eigentümer.
- Gegenprobe mit einem nicht existierenden Repository: Das Protokoll muss den Grund nennen,
  der Rückgabewert 0 sein.
