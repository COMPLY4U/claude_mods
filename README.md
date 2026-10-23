# claude_mods

Eigene Mods (Plugins aus Function Hooks) für Claude Code. Das Repository ist
zugleich ein Plugin-Marketplace (`comply4u-mods`).

## Mods

| Mod | Was er tut |
| --- | --- |
| `kontextanzeige` | Zeigt die Füllung des Kontextfensters. Claude beginnt jede Antwort mit einer Zeile wie > 🟢 **Kontext 25 %** `█████░░░░░░░░░░░░░░░` 251k / 1.000k — gelb ab 70 % (bald neuen Chat beginnen), rot ab 85 % (jetzt neuen Chat beginnen). Die Zahl wird der Nachricht dafür unsichtbar beigelegt. Wo die Oberfläche es zeichnet (lokale Sitzungen), steht sie zusätzlich in der Statuszeile und als Band über dem Eingabefeld; die Desktop-App zeichnet bei Cloud-Sitzungen beides nicht. Schwellen: `HINWEIS_AB`, `WARNUNG_AB`. |

## Installation

### Cloud-Sitzungen (Claude-App, claude.ai/code)

Den Inhalt von [`cloud/setup.sh`](cloud/setup.sh) **einmal** in der Cloud-Umgebung unter
**Umgebung bearbeiten → Setup-Skript** einfügen. Das Skript holt bei jedem neuen Chat die
aktuelle Fassung dieses Repositorys und installiert alle Mods des Marketplace — unabhängig
davon, welches Repository im Chat gewählt ist.

Die Cloud-Umgebung speichert das Ergebnis des Setup-Skripts und führt es erst wieder
aus, wenn sich sein Text ändert. Eine neue Fassung der Mods kommt deshalb an, sobald
die Zahl in der Zeile `# ABRUF=1` erhöht und das Skript gespeichert wird.

Ob es geklappt hat, steht in `~/.claude/comply4u-mods-setup.log` (Stand des Repositorys,
installierte Mods, sonst der Grund). Ist GitHub nicht erreichbar, wird nichts installiert,
und der Sitzungsstart läuft trotzdem normal weiter.

### Lokal (Terminal oder Desktop-App)

```
/plugin install kontextanzeige --marketplace COMPLY4U/claude_mods
```

Danach `y` zum Hinzufügen des Marketplace und den Scope **user** wählen. Der Mod
ist dann in jedem Chat aktiv.

## Einen Mod ändern

1. Datei unter `plugins/<mod>/` ändern.
2. `claude plugin validate plugins/<mod>` und `claude plugin test plugins/<mod>`.
3. Nach `main` pushen. Der nächste neue Chat hat die neue Fassung.

Ein neuer Mod wird in `.claude-plugin/marketplace.json` eingetragen; das Setup-Skript
installiert jeden Eintrag dort.
