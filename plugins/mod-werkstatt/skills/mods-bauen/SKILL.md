---
name: mods-bauen
description: Wie bei COMPLY4U Mods (Plugins aus Function Hooks) für Claude Code gebaut, getestet und über den Marketplace COMPLY4U/claude_mods in alle Cloud-Sitzungen verteilt werden – mit den Fallstricken, die beim Bau der Kontextanzeige aufgefallen sind (Desktop-App zeichnet bei Cloud-Sitzungen keine Statuszeile, gespeichertes Setup-Skript, privates Repository nicht abrufbar). Verwende diesen Skill immer, wenn jemand einen Mod, ein Plugin, eine Anzeige, Statuszeile, Einblendung, einen Hook oder eine automatische Ergänzung in Claude Code haben, ändern oder verteilen will, wenn es um das Repository claude_mods, die Kontextanzeige, das Setup-Skript der Cloud-Umgebung oder „ABRUF“ geht – auch wenn das Wort „Mod“ nicht fällt.
---

# Mods bauen und verteilen (COMPLY4U)

Dieser Skill hält fest, was beim Bau der `kontextanzeige` erarbeitet wurde. Er ergänzt den
eingebauten Skill `plugin-authoring` (die API selbst) um das, was nur bei uns gilt: wie die
Mods verteilt werden und was in Cloud-Sitzungen der Desktop-App tatsächlich ankommt.

**Lade vor dem ersten Schreiben eines Hooks-Moduls den Skill `plugin-authoring`.** Erst er
startet die Beobachtung des Mod-Ordners (Hot Reload) und nennt den Pfad der Typdatei dieser
Claude-Code-Fassung. Die API ändert sich zwischen Fassungen; schlage Ereignisse und Felder
in der Typdatei nach (`grep -n "'session.measure'"` usw.), statt sie aus dem Gedächtnis zu
schreiben.

## Wer hier fragt

Die Person ist fachlich versiert, aber keine Entwicklerin. Sie arbeitet in der Claude-Desktop-App
mit **Cloud-Sitzungen** (Umgebung „Default“), auf Deutsch. Erkläre Schritte in der App mit
Ort und Beschriftung („Umgebung bearbeiten → Setup-Skript“), nicht mit Fachbegriffen.

## Wie die Verteilung funktioniert

- **Repository:** `COMPLY4U/claude_mods`, öffentlich, zugleich Marketplace `comply4u-mods`
  (`.claude-plugin/marketplace.json`). Jeder Mod liegt unter `plugins/<name>/`.
- **Setup-Skript der Cloud-Umgebung** (`cloud/setup.sh`, in der App unter *Umgebung
  bearbeiten → Setup-Skript* eingetragen): klont das Repository nach
  `~/.claude/comply4u-mods`, installiert **jeden Eintrag** des Marketplace für den Benutzer
  und schreibt `~/.claude/comply4u-mods-setup.log`. Es bricht den Sitzungsstart nie ab.
- **Das Ergebnis des Setup-Skripts wird gespeichert.** Das Startprotokoll eines neuen Chats
  meldet dann „Setup script cached from previous run“. Neu ausgeführt wird es erst, wenn sich
  sein Text ändert. Eine neue Fassung kommt deshalb erst an, wenn die Person die Zeile
  `# ABRUF=<n>` im Setup-Skript um eins erhöht und speichert. Sag ihr das nach jeder
  veröffentlichten Änderung ausdrücklich, mit der neuen Zahl.
- **Warum öffentlich:** Ein Chat erreicht ein privates Repository nur, wenn es beim Start
  ausgewählt ist. Ein eigenes Token hilft nicht: Der Proxy des Containers ersetzt jede
  mitgegebene Anmeldung durch die Berechtigung der Sitzung (geprüft mit einem absichtlich
  falschen Token, das trotzdem eine gültige Antwort bekam).
- **Wer auf `main` schreibt, bestimmt, was in allen neuen Chats läuft.** Schreibrecht nur
  wenigen geben; Änderungen möglichst als Pull Request, den die Person annimmt.

## Was in Cloud-Sitzungen der Desktop-App ankommt

Gemessen, nicht vermutet: `$.session.surfaces()` liefert dort `[]`. Die App zeichnet bei
Cloud-Sitzungen **weder Statuszeile (`$.ui.status`) noch Band (`AbovePrompt`) noch
Einblendung (`$.ui.toast`) noch Panes**. Ein Mod läuft trotzdem, seine Hooks feuern, er
bekommt Daten – er kann sie nur nicht zeigen.

**Was ankommt, ist der Antworttext.** Der bewährte Weg:

1. `on('prompt.submit', …)` hängt der Nachricht über `context` eine Anweisung an; sie
   erreicht nur das Modell, die Person sieht sie nicht.
2. Die Anweisung enthält die fertige Zeile, die die Antwort beginnen soll. **Die Form baut der
   Code, nicht das Modell** – sonst sieht die Zeile in jeder Antwort anders aus.
3. Nur an Nachrichten der Person: `e.origin.kind` ist in Cloud-Sitzungen `composer`
   (gemessen); `bridge` und `sdk` gehören ebenfalls dazu. Benachrichtigungen, andere
   Sitzungen und Plugins bekommen keine Zeile. `e.origin` ist **immer** gesetzt – eine
   Prüfung auf `undefined` übergeht jede Nachricht.
4. Den Hook mit `.catch(($, e, next) => next(e))` absichern: Ein Fehler darf keine Nachricht
   aufhalten.

**Nicht `prompt.compose` für Werte, die sich je Nachricht ändern.** Ein Abschnitt im
Systemprompt, der sich jede Runde ändert, bricht den Prompt-Cache für den ganzen Verlauf
dahinter – das kostet bei jedem Chat viel. `context` an der Nachricht lässt den Cache stehen.

Statuszeile und Band trotzdem mitliefern: In lokalen Sitzungen (Terminal, Desktop-App mit
lokalem Ordner) werden sie gezeichnet.

Mehrere Mods, die je eine „erste Zeile“ verlangen, widersprechen sich. Was am Anfang der
Antwort stehen soll, gehört in **einen** Mod und **einen** Zitatblock.

## Daten, die zur Verfügung stehen

`await $.session.usage()` (die einfache Abfrage kostet nichts):

- `context.percent`, `context.tokens`, `context.window` – fehlen bis zur ersten Antwort eines
  Chats und direkt nach dem Zusammenfassen. Das ist kein Fehler; zeige dann einen Hinweis
  („wird ab der nächsten Antwort gemessen“), damit sichtbar ist, dass der Mod läuft.
- `rateLimits[]` mit `kind` (`five_hour`, `seven_day`), `percentUsed`, `resetsAt`.
- `cost` – was die Sitzung bisher gekostet hat, wo die Umgebung das führt.

`on('session.measure', …)` meldet, wenn sich einer dieser Werte ändert (`e.changed`).

## Arbeitsablauf

1. `plugin-authoring` laden. Mod im angegebenen `dev-mods`-Ordner schreiben; die Person
   bestätigt einmal „Enable hot reloading for this session“. Danach lädt jede Änderung am
   Ende der Antwort neu.
2. Prüfen, bevor es irgendwohin geht:
   - `claude plugin validate <mod>`
   - `claude plugin test <mod>` mit mindestens einer `*.test.ts`
   - Typprüfung mit `tsc` (tsconfig außerhalb des Mod-Ordners, siehe
     `references/pruefen.md`)
3. Ist eine Annahme über die Laufzeit unsicher (was kommt an, welche Herkunft, welche
   Oberfläche), **messen statt raten**: vorübergehend mit `$.fs.write` eine JSON-Datei in den
   Scratchpad schreiben, die Person um eine beliebige Nachricht bitten, Datei lesen, Diagnose
   wieder entfernen.
4. In `plugins/<name>/` des Repositorys übernehmen (ohne `.claude-plugin/types/`, das legt
   der Engine selbst an), neuen Mod in `marketplace.json` eintragen, `version` in
   `plugin.json` erhöhen.
5. Setup-Skript in einem leeren Home-Verzeichnis durchspielen – das hat schon zwei Fehler
   gefunden, die sonst jeden Start getroffen hätten:
   `HOME=<leerer Ordner> bash cloud/setup.sh; cat <leerer Ordner>/.claude/comply4u-mods-setup.log; HOME=<leerer Ordner> claude plugin list`
6. Commit und Push (bzw. Pull Request, wenn `main` geschützt ist). Dann der Person sagen:
   `# ABRUF=` im Setup-Skript um eins erhöhen, speichern, neuen Chat starten.

## Fehlersuche in einem anderen Chat

- **Startprotokoll lesen:** `list_events` des Chats mit `kinds: ["env_manager_log"]`. Dort
  steht, ob das Setup-Skript lief, wie lange (ein erfolgreicher Abruf samt Installation
  dauert Sekunden; 0,2 s heißt: sofort gescheitert) oder ob es „cached from previous run“ war.
- **Keine Befehle per Nachricht in einen anderen Chat schicken.** Der andere Chat führt sie zu
  Recht nicht aus, weil sie nicht von der Person kommen. Bitte stattdessen die Person, dort
  „Zeig mir `~/.claude/comply4u-mods-setup.log`“ zu schreiben.
- In der ersten Antwort eines Chats fehlt die Zahl planmäßig (siehe oben); erst die zweite
  Antwort zeigt, ob der Mod läuft.

## Was der Validator und das Testkit verlangen

Die Einzelheiten stehen in `references/pruefen.md`. Lies die Datei, sobald `validate`,
`test` oder `tsc` etwas melden oder bevor du den ersten Test schreibst.
