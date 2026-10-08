# claude_mods

Eigene Mods (Plugins aus Function Hooks) für Claude Code. Das Repository ist
zugleich ein Plugin-Marketplace (`comply4u-mods`).

## Mods

| Mod | Was er tut |
| --- | --- |
| `kontextanzeige` | Zeigt die Füllung des Kontextfensters. Claude beginnt jede Antwort mit einer Zeile wie > 🟢 **Kontext 25 %** `█████░░░░░░░░░░░░░░░` 251k / 1.000k — gelb ab 70 % (bald neuen Chat beginnen), rot ab 85 % (jetzt neuen Chat beginnen). Die Zahl wird der Nachricht dafür unsichtbar beigelegt. Wo die Oberfläche es zeichnet (lokale Sitzungen), steht sie zusätzlich in der Statuszeile und als Band über dem Eingabefeld; die Desktop-App zeichnet bei Cloud-Sitzungen beides nicht. Schwellen: `HINWEIS_AB`, `WARNUNG_AB`. |

## Installation

### Cloud-Sitzungen (Claude-App, claude.ai/code)

Den Inhalt von [`cloud/setup.sh`](cloud/setup.sh) in der Cloud-Umgebung unter
**Edit → Setup script** einfügen (bzw. anhängen). Er läuft bei jedem neuen Chat
dieser Umgebung, unabhängig vom gewählten Repository. Das Skript bringt die
Mods selbst mit und braucht deshalb keinen Zugriff auf dieses (private)
Repository.

### Lokal (Terminal oder Desktop-App)

```
/plugin install kontextanzeige --marketplace COMPLY4U/claude_mods
```

Danach `y` zum Hinzufügen des Marketplace und den Scope **user** wählen. Der Mod
ist dann in jedem Chat aktiv.

## Einen Mod ändern

1. Datei unter `plugins/<mod>/` ändern.
2. `claude plugin validate plugins/<mod>` und `claude plugin test plugins/<mod>`.
3. `tools/cloud_setup_erzeugen.sh` ausführen und `cloud/setup.sh` mit committen.
4. In der Cloud-Umgebung das Setup-Skript durch die neue Fassung ersetzen.
