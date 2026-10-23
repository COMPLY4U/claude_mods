# Repos aktualisieren

Ein Doppelklick holt den aktuellen Stand **aller** GitHub-Repositories von COMPLY4U
auf den eigenen Rechner. Fehlende Repositories werden heruntergeladen – auch neue,
die gerade erst angelegt wurden. Vorhandene werden aktualisiert. Danach kann man in
einem Menü auf einen Zweig wechseln, etwa auf den Zweig, an dem Claude Code gerade
arbeitet.

Es ersetzt die vielen persönlichen `.cmd`-Dateien zum Herunterladen.
Startskripte einzelner Repositories (z. B. `REVCOMP_starten.cmd`, `start_local.cmd`)
ersetzt es **nicht**.

## Einmal einrichten (etwa 5 Minuten)

**1. Git installieren** (falls noch nicht vorhanden). Startmenü → „PowerShell“ öffnen,
diese Zeile einfügen (Rechtsklick fügt ein) und Enter drücken:

```
winget install --id Git.Git -e
```

Erfolg: Am Ende steht „Erfolgreich installiert“. Danach das PowerShell-Fenster
**schließen** und ein neues öffnen.

**2. Werkzeug holen und starten.** Im neuen PowerShell-Fenster diese Zeile einfügen
und Enter drücken:

```
git clone https://github.com/COMPLY4U/claude_mods C:\GitHub\claude_mods; C:\GitHub\claude_mods\arbeitsplatz\Repos_aktualisieren.cmd
```

- Öffnet sich ein Fenster „Connect to GitHub“: **Sign in with your browser** wählen und
  mit dem GitHub-Konto anmelden. Das passiert nur einmal.
- Frage nach dem Ordner: einfach **Enter** (= `C:\GitHub`).
- Frage nach der Desktop-Verknüpfung: **Enter** (= ja).

Erfolg: Eine Übersicht mit allen Repositories erscheint, auf dem Desktop liegt
„Repos aktualisieren“.

**3. Alte Kopien aufräumen** (wer schon Repositories an anderer Stelle hat): Erst
prüfen, dass dort nichts Ungesichertes liegt, dann den alten Ordner löschen. Künftig
nur noch mit `C:\GitHub\…` arbeiten.

## Im Alltag

Doppelklick auf **Repos aktualisieren**. Die Übersicht zeigt je Repository eine Zeile:

| Anzeige | Bedeutung | Was tun |
|---|---|---|
| grün „neu heruntergeladen“ / „aktualisiert“ | alles gut | nichts |
| grau „aktuell“ | nichts Neues | nichts |
| gelb „geöffnet: Datei.pptx“ | Die Datei ist in Office offen und kann nicht ersetzt werden | Datei schließen, erneut starten |
| gelb „Zweig auf GitHub gelöscht“ | Die Arbeit wurde meist schon übernommen | im Menü Nummer eingeben, Hauptzweig wählen |
| gelb „Neuer Claude-Zweig: …“ | Claude Code hat einen neuen Stand hochgeladen | bei Bedarf im Menü auf diesen Zweig wechseln |
| gelb „… eigene Änderung(en) noch nicht auf GitHub“ | Auf diesem Rechner liegt Arbeit, die nicht auf GitHub ist | klären, nicht ignorieren |
| rot „auseinandergelaufen“ | Hier und auf GitHub wurde unabhängig weitergearbeitet | nicht selbst lösen – in Claude Code beschreiben oder Kollegen fragen |

**Zweig wechseln:** Nach der Übersicht die Nummer des Repositorys eingeben, dann die
Nummer des Zweigs. Der Zweig, an dem Claude Code zuletzt gearbeitet hat, steht oben.
Enter beendet.

## Was das Werkzeug nie tut

- **Nichts überschreiben oder löschen.** Aktualisiert wird nur, wenn Git den neuen
  Stand ohne Zusammenführen übernehmen kann. Lokale Änderungen bleiben unangetastet;
  steht eine im Weg, wird das gemeldet.
- **Keine Skripte aus Repositories ausführen.** Nach dem Herunterladen werden
  Einrichtungs- und Startskripte nur genannt. Grund: Was jemand in irgendein
  Repository hochlädt, liefe sonst ungefragt auf jedem Rechner der Firma.
- **Keine Zugangsdaten speichern.** Die Anmeldung bei GitHub verwaltet Git selbst
  (Git Credential Manager).

## Einstellungen (nur bei Bedarf)

Datei: `%LOCALAPPDATA%\Comply4u\repos_abgleich.json` (im Explorer in die Adresszeile
einfügen). Protokoll jedes Laufs: `repos_abgleich.log` daneben.

```json
{
  "zielordner": "C:\\GitHub",
  "organisationen": ["COMPLY4U"],
  "auslassen": ["Name-eines-Repos-das-ich-nicht-brauche"],
  "zusaetzliche_repos": ["https://github.com/anderer-besitzer/repo.git"],
  "github_abfragen": true
}
```

Wird die Datei gelöscht, fragt das Werkzeug beim nächsten Start neu.

**Warum `C:\GitHub` und nicht OneDrive oder der Desktop:** Git-Repositories bestehen aus
hunderten kleiner Dateien, die sich gleichzeitig ändern. OneDrive und SharePoint
erzeugen daraus Konfliktkopien und beschädigen das Repository. Das Werkzeug weist
OneDrive-Ordner deshalb ab. Ein kurzer Pfad direkt unter `C:\` vermeidet außerdem die
Windows-Grenze für lange Dateinamen.

## Technik

- `Repos_aktualisieren.cmd` startet `Technik/repos_aktualisieren.ps1` (Windows
  PowerShell 5.1, keine Installation nötig). Die Startdatei steht in einer einzigen
  Klammer, damit sie sich selbst aktualisieren kann (cmd liest Klammern vollständig
  ein, bevor es sie ausführt).
- Die Liste der Repositories kommt über die GitHub-API
  (`/orgs/COMPLY4U/repos`) mit der Anmeldung, die Git ohnehin gespeichert hat. Ist
  GitHub nicht erreichbar, werden die vorhandenen Ordner trotzdem aktualisiert.
- Abgleich je Repository: `git fetch --prune`, dann `git merge --ff-only`. Vorher wird
  geprüft, ob eine betroffene Datei in Office geöffnet ist (Sperrdatei `~$Name`).
- Einmalig gesetzt: `git config --global core.longpaths true` und `git lfs install`
  (große Dateien wie `.pptx` in `quo-vadis-dora`).
- `-OhneRueckfrage` läuft ohne Menü, z. B. für die Windows-Aufgabenplanung. Rückgabe 1,
  wenn ein Repository rot gemeldet wird.
- Getestet unter PowerShell 7 gegen lokale Test-Repositories (Herunterladen,
  Aktualisieren, lokale Änderungen, geöffnete Datei, eigene und auseinandergelaufene
  Stände, neuer und gelöschter Claude-Zweig, Zweigwechsel, Ersteinrichtung). Noch nicht
  auf einem Windows-Rechner und noch nicht gegen die echte GitHub-API gelaufen.
