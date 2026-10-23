<#
  Repos aktualisieren
  -------------------
  Holt den aktuellen Stand aller GitHub-Repositories der Organisation auf
  diesen Rechner: fehlende werden heruntergeladen, vorhandene aktualisiert.
  Gestartet wird über Repos_aktualisieren.cmd (Doppelklick).

  Grundsätze – nicht verhandelbar:
  * Es wird nie etwas überschrieben oder gelöscht. Aktualisiert wird nur, wenn
    Git den neuen Stand ohne Zusammenführen übernehmen kann (--ff-only). Alles
    andere wird gemeldet, nicht „repariert“.
  * Es wird nie ein Skript aus einem Repository ausgeführt. Was in irgendein
    Repository geschoben wird, liefe sonst auf jedem Rechner der Firma.
    Einrichtungsskripte werden nur genannt.
  * Geschrieben wird nur in den Zielordner und in die eigenen Einstellungen
    (%LOCALAPPDATA%\Comply4u). Kein Zugangsschlüssel wird gespeichert oder
    protokolliert: Die Anmeldung bei GitHub verwaltet Git selbst (Git Credential
    Manager), dieses Skript leiht sie sich nur für die Liste der Repositories.

  PowerShell 5.1 (Windows-Standard): Datei als UTF-8 mit BOM speichern, sonst
  werden die Umlaute falsch gelesen. Keine Sprachmittel aus PowerShell 7.
#>
param(
    # Pfad der Einstellungsdatei (für Tests, sonst %LOCALAPPDATA%\Comply4u\repos_abgleich.json)
    [string]$Einstellungen = '',
    # Ohne Menü und ohne Rückfragen, z. B. für die Aufgabenplanung
    [switch]$OhneRueckfrage
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$IstWindows = ($env:OS -eq 'Windows_NT')
$Vorgaben = [ordered]@{
    zielordner         = $(if ($IstWindows) { 'C:\GitHub' } else { Join-Path $HOME 'GitHub' })
    organisationen     = @('COMPLY4U')
    auslassen          = @()
    zusaetzliche_repos = @()
    github_abfragen    = $true
}
# Wie lange ein neuer Claude-Zweig als „neu“ gemeldet wird
$TageNeueZweige = 3

if (-not $Einstellungen) {
    $Einstellungen = Join-Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Comply4u') 'repos_abgleich.json'
}
$Protokolldatei = Join-Path (Split-Path $Einstellungen -Parent) 'repos_abgleich.log'

# ---------------------------------------------------------------------------
#  Hilfsfunktionen
# ---------------------------------------------------------------------------
function Schreibe([string]$Text = '', [string]$Farbe = 'Gray') {
    Write-Host $Text -ForegroundColor $Farbe
}

function Frage([string]$Text) {
    if ($OhneRueckfrage) { return '' }
    return (Read-Host $Text)
}

# Git ausführen und die Ausgabe auswerten. Fehlermeldungen von Git gehen in
# die Ausgabe und lösen keinen Abbruch aus (PowerShell 5.1 wertet sonst jede
# Zeile auf stderr als Fehler).
function GitLesen([string]$Ordner, [string[]]$Argumente) {
    $alt = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $zeilen = @(& git -C $Ordner -c core.quotepath=off @Argumente 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $alt
    }
    [pscustomobject]@{ Code = $code; Zeilen = $zeilen; Text = (($zeilen -join "`n").Trim()) }
}

# Git sichtbar ausführen: Fortschritt und Rückfragen von Git (etwa „Unlink of
# file failed. Should I try again? (y/n)“ bei einer geöffneten Datei) müssen
# auf dem Bildschirm ankommen, sonst wartet Git auf eine Antwort, die niemand
# sieht.
function GitZeigen([string]$Ordner, [string[]]$Argumente) {
    $alt = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git -C $Ordner @Argumente | Out-Host
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $alt
    }
    return $code
}

function Feld($Objekt, [string]$Name, $Vorgabe) {
    if ($null -ne $Objekt -and ($Objekt.PSObject.Properties.Name -contains $Name) -and $null -ne $Objekt.$Name) {
        return $Objekt.$Name
    }
    return $Vorgabe
}

function VorWann([long]$Unix) {
    $s = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $Unix
    if ($s -lt 3600) { return "vor $([math]::Max(1, [math]::Floor($s / 60))) Min." }
    if ($s -lt 86400) { return "vor $([math]::Floor($s / 3600)) Std." }
    $t = [math]::Floor($s / 86400)
    if ($t -eq 1) { return 'vor 1 Tag' }
    return "vor $t Tagen"
}

function Plural([int]$Zahl, [string]$Einzahl, [string]$Mehrzahl) {
    if ($Zahl -eq 1) { return "1 $Einzahl" }
    return "$Zahl $Mehrzahl"
}

function Protokolliere([string]$Text) {
    try {
        Add-Content -LiteralPath $Protokolldatei -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $Text) -Encoding UTF8
    } catch { }
}

# ---------------------------------------------------------------------------
#  Zielordner und Einstellungen
# ---------------------------------------------------------------------------

# Liefert einen Grund, warum der Ordner nicht taugt, oder einen leeren Text.
function PruefeZielordner([string]$Pfad) {
    if (-not $Pfad) { return 'Kein Ordner angegeben.' }
    if (-not [IO.Path]::IsPathRooted($Pfad)) { return 'Bitte einen vollständigen Pfad angeben, z. B. C:\GitHub.' }
    $voll = [IO.Path]::GetFullPath($Pfad).TrimEnd('\', '/')
    if ([IO.Path]::GetPathRoot($Pfad).TrimEnd('\', '/') -eq $voll) {
        return 'Bitte nicht direkt das Laufwerk wählen, sondern einen Ordner darin (z. B. C:\GitHub).'
    }
    # Git und Dateisynchronisation vertragen sich nicht: Der Sync-Client sieht
    # hunderte kleine Git-Dateien gleichzeitig wechseln, erzeugt Konfliktkopien
    # und beschädigt das Repository.
    foreach ($sync in @($env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer)) {
        if ($sync -and $voll.StartsWith($sync.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
            return "Der Ordner liegt in OneDrive ($sync). Git-Repositories dürfen nicht synchronisiert werden – bitte einen Ordner außerhalb wählen, z. B. C:\GitHub."
        }
    }
    if ($voll -match '[\\/]OneDrive( - [^\\/]*)?([\\/]|$)') {
        return 'Der Ordner liegt in OneDrive. Git-Repositories dürfen nicht synchronisiert werden – bitte einen Ordner außerhalb wählen, z. B. C:\GitHub.'
    }
    return ''
}

function LadeEinstellungen {
    if (-not (Test-Path -LiteralPath $Einstellungen)) { return $null }
    try {
        return (Get-Content -LiteralPath $Einstellungen -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        throw "Die Einstellungsdatei ist nicht lesbar: $Einstellungen`n$($_.Exception.Message)"
    }
}

function SpeichereEinstellungen($Werte) {
    $ordner = Split-Path $Einstellungen -Parent
    if (-not (Test-Path -LiteralPath $ordner)) { New-Item -ItemType Directory -Path $ordner -Force | Out-Null }
    ($Werte | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $Einstellungen -Encoding UTF8
}

function ErsteEinrichtung {
    if ($OhneRueckfrage) {
        throw "Noch nicht eingerichtet. Bitte einmal Repos_aktualisieren.cmd per Doppelklick starten."
    }
    Schreibe 'Erste Einrichtung auf diesem Rechner' Cyan
    Schreibe ''
    Schreibe 'Alle Repositories kommen in einen gemeinsamen Ordner. Er darf nicht in'
    Schreibe 'OneDrive oder einer SharePoint-Bibliothek liegen. Ein kurzer Pfad direkt'
    Schreibe 'unter C:\ vermeidet Probleme mit langen Dateinamen.'
    Schreibe ''
    while ($true) {
        $antwort = Read-Host "Ordner für die Repositories (Enter = $($Vorgaben.zielordner))"
        if (-not $antwort) { $antwort = $Vorgaben.zielordner }
        $antwort = $antwort.Trim().Trim('"')
        $grund = PruefeZielordner $antwort
        if (-not $grund) { break }
        Schreibe $grund Yellow
    }
    $werte = [ordered]@{}
    foreach ($k in $Vorgaben.Keys) { $werte[$k] = $Vorgaben[$k] }
    $werte.zielordner = [IO.Path]::GetFullPath($antwort).TrimEnd('\', '/')
    SpeichereEinstellungen $werte
    Schreibe "Gespeichert in $Einstellungen" DarkGray
    Schreibe ''
    return (LadeEinstellungen)
}

# ---------------------------------------------------------------------------
#  Liste der Repositories
# ---------------------------------------------------------------------------

# Leiht sich die GitHub-Anmeldung, die Git ohnehin gespeichert hat. Gibt es
# noch keine, öffnet der Git Credential Manager das Anmeldefenster.
function HoleAnmeldung {
    $alt = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $zeilen = @(@('protocol=https', 'host=github.com', '') | & git credential fill 2>$null)
    } finally {
        $ErrorActionPreference = $alt
    }
    foreach ($z in $zeilen) {
        if ("$z" -like 'password=*') { return "$z".Substring(9) }
    }
    return ''
}

function HoleRepoListe([string]$Organisation, [string]$Token) {
    $kopf = @{ 'User-Agent' = 'comply4u-repos-aktualisieren'; 'Accept' = 'application/vnd.github+json' }
    if ($Token) { $kopf['Authorization'] = "Bearer $Token" }
    $alle = @()
    $seite = 1
    do {
        $uri = "https://api.github.com/orgs/$Organisation/repos?type=all&per_page=100&page=$seite"
        $antwort = @(Invoke-RestMethod -Uri $uri -Headers $kopf -UseBasicParsing -TimeoutSec 30)
        $alle += $antwort
        $seite++
    } while ($antwort.Count -eq 100)
    return , $alle
}

function NameAusAdresse([string]$Adresse) {
    return ((($Adresse.TrimEnd('/', '\')) -split '[/\\]')[-1] -replace '\.git$', '')
}

function SammleRepos($E, [string]$Ziel) {
    $repos = [ordered]@{}
    $auslassen = @(Feld $E 'auslassen' @()) | ForEach-Object { "$_".ToLower() }
    $hinweise = New-Object System.Collections.Generic.List[string]

    if (Feld $E 'github_abfragen' $true) {
        Schreibe 'Frage GitHub nach der Liste der Repositories ...' DarkGray
        Schreibe '(Falls sich ein Anmeldefenster öffnet: mit dem GitHub-Konto anmelden.)' DarkGray
        $token = HoleAnmeldung
        foreach ($org in @(Feld $E 'organisationen' @())) {
            try {
                $liste = HoleRepoListe $org $token
                foreach ($r in $liste) {
                    if ($auslassen -contains $r.name.ToLower()) { continue }
                    $repos[$r.name.ToLower()] = [pscustomobject]@{
                        Name = $r.name; Url = $r.clone_url; Hauptzweig = $r.default_branch
                        Archiviert = [bool]$r.archived; AufGitHub = $true
                    }
                }
            } catch {
                $grund = $_.Exception.Message
                if ($grund -match '401') { $grund = 'Anmeldung bei GitHub fehlgeschlagen.' }
                $hinweise.Add("Liste von $org nicht abrufbar ($grund) Es werden nur vorhandene Ordner aktualisiert.")
            }
        }
        $token = $null
    }

    foreach ($adresse in @(Feld $E 'zusaetzliche_repos' @())) {
        $name = NameAusAdresse "$adresse"
        if (-not $repos.Contains($name.ToLower()) -and -not ($auslassen -contains $name.ToLower())) {
            $repos[$name.ToLower()] = [pscustomobject]@{
                Name = $name; Url = "$adresse"; Hauptzweig = ''; Archiviert = $false; AufGitHub = $false
            }
        }
    }

    # Vorhandene Ordner gehören immer dazu – auch wenn GitHub gerade nicht
    # antwortet oder das Repository nicht zur Organisation gehört.
    if (Test-Path -LiteralPath $Ziel) {
        foreach ($d in @(Get-ChildItem -LiteralPath $Ziel -Directory)) {
            $k = $d.Name.ToLower()
            if ($repos.Contains($k) -or ($auslassen -contains $k)) { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $d.FullName '.git'))) { continue }
            $repos[$k] = [pscustomobject]@{
                Name = $d.Name; Url = ''; Hauptzweig = ''; Archiviert = $false; AufGitHub = $false
            }
        }
    }

    $sortiert = @($repos.Values | Sort-Object Name)
    return [pscustomobject]@{ Repos = $sortiert; Hinweise = $hinweise }
}

# ---------------------------------------------------------------------------
#  Ein Repository bearbeiten
# ---------------------------------------------------------------------------

# Dateien, die sich mit dem Wechsel ändern würden und gerade in Office
# geöffnet sind (Office legt daneben eine Datei „~$Name“ an). Unter Windows
# lässt sich eine geöffnete Datei nicht ersetzen.
function GeoeffneteDateien([string]$Pfad, [string]$Ziel) {
    $offen = New-Object System.Collections.Generic.List[string]
    foreach ($n in (GitLesen $Pfad @('diff', '--name-only', 'HEAD', $Ziel)).Zeilen) {
        if (-not $n) { continue }
        $voll = Join-Path $Pfad $n
        $ordner = Split-Path $voll -Parent
        $datei = Split-Path $voll -Leaf
        $kandidaten = @('~$' + $datei)
        if ($datei.Length -gt 2) { $kandidaten += ('~$' + $datei.Substring(2)) }
        foreach ($k in $kandidaten) {
            if (Test-Path -LiteralPath (Join-Path $ordner $k)) { $offen.Add($n); break }
        }
    }
    return ($offen -join ', ')
}

function LokaleAenderungen([string]$Pfad) {
    $geaendert = 0; $neu = 0
    foreach ($z in (GitLesen $Pfad @('status', '--porcelain')).Zeilen) {
        if (-not $z) { continue }
        if ($z.StartsWith('??')) { $neu++ } else { $geaendert++ }
    }
    return [pscustomobject]@{ Geaendert = $geaendert; Neu = $neu }
}

function Hauptzweig($Repo, [string]$Pfad) {
    if ($Repo.Hauptzweig) { return $Repo.Hauptzweig }
    $r = GitLesen $Pfad @('symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD')
    if ($r.Code -eq 0 -and $r.Text) { return ($r.Text -replace '^origin/', '') }
    foreach ($kandidat in @('main', 'master')) {
        if ((GitLesen $Pfad @('show-ref', '--verify', '--quiet', "refs/remotes/origin/$kandidat")).Code -eq 0) { return $kandidat }
    }
    return ''
}

# Hinweis auf Einrichtungs- und Startskripte eines neu heruntergeladenen
# Repositories. Ausgeführt wird bewusst nichts (siehe Grundsätze oben).
function Einrichtungshinweis([string]$Pfad) {
    $treffer = @(Get-ChildItem -LiteralPath $Pfad -Filter '*.cmd' -File -Recurse -Depth 1 -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(einricht|setup|install|start)' } |
        ForEach-Object { $_.FullName.Substring($Pfad.Length).TrimStart('\', '/') })
    if ($treffer.Count -eq 0) { return '' }
    return ('Zum Einrichten oder Starten (bei Bedarf selbst öffnen): ' + ($treffer -join ', '))
}

function NeueClaudeZweige([string]$Pfad, [string]$Aktuell) {
    $grenze = [DateTimeOffset]::UtcNow.AddDays(-$TageNeueZweige).ToUnixTimeSeconds()
    $gefunden = New-Object System.Collections.Generic.List[string]
    $refs = (GitLesen $Pfad @('for-each-ref', '--sort=-committerdate', '--format=%(refname:short)|%(committerdate:unix)', 'refs/remotes/origin/claude/')).Zeilen
    foreach ($z in $refs) {
        $teile = "$z".Split('|')
        if ($teile.Count -lt 2) { continue }
        $name = $teile[0] -replace '^origin/', ''
        $zeit = [long]$teile[1]
        if ($zeit -lt $grenze) { break }
        if ($name -eq $Aktuell) { continue }
        # Schon im eigenen Stand enthalten? Dann ist er nicht neu.
        if ((GitLesen $Pfad @('merge-base', '--is-ancestor', $teile[0], 'HEAD')).Code -eq 0) { continue }
        $gefunden.Add("$name ($(VorWann $zeit))")
        if ($gefunden.Count -ge 3) { break }
    }
    return $gefunden
}

function NeuesErgebnis($Repo, [string]$Pfad) {
    return [pscustomobject]@{
        Nr = 0; Name = $Repo.Name; Pfad = $Pfad; Repo = $Repo; Zweig = ''
        Art = 'ok'; Status = 'aktuell'; Hinweise = (New-Object System.Collections.Generic.List[string])
    }
}

function Bearbeite($Repo, [string]$Ziel) {
    $pfad = Join-Path $Ziel $Repo.Name
    $e = NeuesErgebnis $Repo $pfad

    # --- fehlt: herunterladen -------------------------------------------
    if (-not (Test-Path -LiteralPath $pfad)) {
        Schreibe ''
        Schreibe "Neu: $($Repo.Name) wird heruntergeladen ..." Cyan
        $code = GitZeigen $Ziel @('clone', $Repo.Url, $Repo.Name)
        if ($code -ne 0) {
            $e.Art = 'fehler'; $e.Status = 'Herunterladen fehlgeschlagen (Meldung oben)'
            return $e
        }
        $e.Art = 'neu'; $e.Status = 'neu heruntergeladen'
        $e.Zweig = (GitLesen $pfad @('symbolic-ref', '--quiet', '--short', 'HEAD')).Text
        $h = Einrichtungshinweis $pfad
        if ($h) { $e.Hinweise.Add($h) }
        return $e
    }
    if (-not (Test-Path -LiteralPath (Join-Path $pfad '.git'))) {
        $e.Art = 'hinweis'; $e.Status = 'Ordner ist kein Git-Repository – nicht angefasst'
        return $e
    }

    # --- vorhanden: abgleichen ------------------------------------------
    Schreibe "Prüfe $($Repo.Name) ..." DarkGray
    $abruf = GitLesen $pfad @('fetch', '--prune', '--quiet', 'origin')
    if ($abruf.Code -ne 0) {
        $e.Art = 'fehler'; $e.Status = 'GitHub nicht erreichbar oder kein Zugriff'
        if ($abruf.Zeilen.Count -gt 0) { $e.Hinweise.Add('Git meldet: ' + $abruf.Zeilen[-1]) }
        return $e
    }
    $zweig = GitLesen $pfad @('symbolic-ref', '--quiet', '--short', 'HEAD')
    if ($zweig.Code -ne 0) {
        $e.Art = 'hinweis'; $e.Status = 'kein Zweig ausgewählt – nicht angefasst (über das Menü einen Zweig wählen)'
        return $e
    }
    $e.Zweig = $zweig.Text

    $info = (GitLesen $pfad @('for-each-ref', '--format=%(upstream:short)|%(upstream:track)', "refs/heads/$($e.Zweig)")).Text
    $teile = $info.Split('|')
    $gegenstueck = $teile[0]
    $spur = ''
    if ($teile.Count -gt 1) { $spur = $teile[1] }

    if (-not $gegenstueck) {
        $e.Art = 'hinweis'; $e.Status = 'Zweig gibt es nur auf diesem Rechner – nicht angefasst'
    } elseif ($spur -like '*gone*') {
        $e.Art = 'hinweis'
        $e.Status = 'Zweig auf GitHub gelöscht (meist: bereits übernommen) – über das Menü zum Hauptzweig wechseln'
    } else {
        $zahlen = (GitLesen $pfad @('rev-list', '--left-right', '--count', "HEAD...$gegenstueck")).Text -split '\s+'
        $vorne = [int]$zahlen[0]; $hinten = [int]$zahlen[1]
        if ($hinten -gt 0 -and $vorne -eq 0) {
            $offen = GeoeffneteDateien $pfad $gegenstueck
            if ($offen) {
                $e.Art = 'hinweis'
                $e.Status = "nicht aktualisiert – geöffnet: $offen (schließen und erneut starten)"
            } else {
                $code = GitZeigen $pfad @('merge', '--ff-only', '--quiet', $gegenstueck)
                if ($code -eq 0) {
                    $e.Art = 'aktualisiert'
                    $e.Status = 'aktualisiert: ' + (Plural $hinten 'neue Änderung' 'neue Änderungen')
                } else {
                    $e.Art = 'fehler'
                    $e.Status = 'Aktualisieren fehlgeschlagen – lokal geänderte oder geöffnete Dateien stehen im Weg (Meldung oben)'
                }
            }
        } elseif ($vorne -gt 0 -and $hinten -eq 0) {
            $e.Art = 'hinweis'
            $e.Status = (Plural $vorne 'eigene Änderung' 'eigene Änderungen') + ' noch nicht auf GitHub'
        } elseif ($vorne -gt 0 -and $hinten -gt 0) {
            $e.Art = 'fehler'
            $e.Status = "auseinandergelaufen ($vorne hier, $hinten auf GitHub) – nicht angefasst, bitte klären"
        }
    }

    $lokal = LokaleAenderungen $pfad
    if ($lokal.Geaendert -gt 0 -or $lokal.Neu -gt 0) {
        $teil = @()
        if ($lokal.Geaendert -gt 0) { $teil += (Plural $lokal.Geaendert 'geänderte Datei' 'geänderte Dateien') }
        if ($lokal.Neu -gt 0) { $teil += (Plural $lokal.Neu 'neue Datei' 'neue Dateien') }
        $e.Hinweise.Add('Auf diesem Rechner: ' + ($teil -join ', ') + ' – nicht auf GitHub, bleiben unangetastet')
    }
    $haupt = Hauptzweig $Repo $pfad
    if ($haupt -and $e.Zweig -ne $haupt -and $e.Art -ne 'hinweis') {
        $e.Hinweise.Add("Arbeitet auf Zweig $($e.Zweig), nicht auf $haupt")
    }
    foreach ($z in (NeueClaudeZweige $pfad $e.Zweig)) {
        $e.Hinweise.Add("Neuer Claude-Zweig: $z – über das Menü wechseln")
    }
    if ($Repo.Archiviert) { $e.Hinweise.Add('Auf GitHub archiviert – wird nicht mehr weiterentwickelt') }
    return $e
}

# ---------------------------------------------------------------------------
#  Zweig wechseln (Menü)
# ---------------------------------------------------------------------------
function WechsleZweig($E) {
    $p = $E.Pfad
    if (-not (Test-Path -LiteralPath (Join-Path $p '.git'))) {
        Schreibe 'Hier gibt es keinen Zweig zu wechseln.' Yellow
        return
    }
    $haupt = Hauptzweig $E.Repo $p
    $liste = New-Object System.Collections.Generic.List[object]
    $refs = (GitLesen $p @('for-each-ref', '--sort=-committerdate', '--format=%(refname:short)|%(committerdate:unix)|%(subject)', 'refs/remotes/origin/')).Zeilen
    $eintraege = @()
    foreach ($z in $refs) {
        $t = "$z".Split('|', 3)
        if ($t.Count -lt 3) { continue }
        $name = $t[0] -replace '^origin/', ''
        if ($name -eq 'HEAD' -or $t[0] -eq 'origin') { continue }
        $eintraege += [pscustomobject]@{ Name = $name; Zeit = [long]$t[1]; Betreff = $t[2] }
    }
    $hauptEintrag = @($eintraege | Where-Object { $_.Name -eq $haupt })
    foreach ($x in $hauptEintrag) { $liste.Add($x) }
    foreach ($x in @($eintraege | Where-Object { $_.Name -ne $haupt } | Select-Object -First 10)) { $liste.Add($x) }
    if ($liste.Count -eq 0) { Schreibe 'Auf GitHub sind keine Zweige zu finden.' Yellow; return }

    Schreibe ''
    Schreibe "Zweige von $($E.Name) (neueste zuerst):" Cyan
    for ($i = 0; $i -lt $liste.Count; $i++) {
        $x = $liste[$i]
        $marke = '  '
        if ($x.Name -eq $E.Zweig) { $marke = '* ' }
        $zusatz = ''
        if ($x.Name -eq $haupt) { $zusatz = '  [Hauptzweig]' }
        $betreff = $x.Betreff
        if ($betreff.Length -gt 50) { $betreff = $betreff.Substring(0, 47) + '...' }
        Schreibe ("{0}{1,2}  {2}{3}" -f $marke, ($i + 1), $x.Name, $zusatz)
        Schreibe ("        {0} · {1}" -f (VorWann $x.Zeit), $betreff) DarkGray
    }
    Schreibe '  (* = derzeit ausgewählt)' DarkGray
    $wahl = Read-Host 'Nummer des Zweigs (Enter = abbrechen)'
    $nr = 0
    if (-not $wahl -or -not [int]::TryParse($wahl, [ref]$nr) -or $nr -lt 1 -or $nr -gt $liste.Count) { return }
    $ziel = $liste[$nr - 1].Name
    if ($ziel -eq $E.Zweig) { Schreibe 'Dieser Zweig ist bereits ausgewählt.' DarkGray; return }

    if ((LokaleAenderungen $p).Geaendert -gt 0) {
        Schreibe 'Nicht gewechselt: Es gibt geänderte Dateien, die nicht auf GitHub sind.' Yellow
        Schreibe 'Bitte erst klären (z. B. in Claude Code hochladen lassen oder bewusst verwerfen).' Yellow
        return
    }
    $offen = GeoeffneteDateien $p "origin/$ziel"
    if ($offen) { Schreibe "Nicht gewechselt – bitte erst schließen: $offen" Yellow; return }

    if ((GitLesen $p @('show-ref', '--verify', '--quiet', "refs/heads/$ziel")).Code -eq 0) {
        $code = GitZeigen $p @('switch', '--quiet', $ziel)
        if ($code -eq 0) {
            $zahlen = (GitLesen $p @('rev-list', '--left-right', '--count', "HEAD...origin/$ziel")).Text -split '\s+'
            if ([int]$zahlen[0] -eq 0 -and [int]$zahlen[1] -gt 0) {
                $code = GitZeigen $p @('merge', '--ff-only', '--quiet', "origin/$ziel")
            } elseif ([int]$zahlen[0] -gt 0) {
                Schreibe 'Achtung: Dieser Zweig hat hier Änderungen, die nicht auf GitHub sind. Nicht aktualisiert.' Yellow
            }
        }
    } else {
        $code = GitZeigen $p @('switch', '--quiet', '--track', "origin/$ziel")
    }
    if ($code -eq 0) {
        $E.Zweig = $ziel
        Schreibe "$($E.Name) steht jetzt auf $ziel (Stand von GitHub)." Green
        Protokolliere "$($E.Name): Zweig gewechselt auf $ziel"
    } else {
        Schreibe 'Wechsel fehlgeschlagen (Meldung oben). Es wurde nichts verändert.' Red
    }
}

# ---------------------------------------------------------------------------
#  Verknüpfung auf dem Desktop
# ---------------------------------------------------------------------------
function BieteVerknuepfungAn([string]$Ziel) {
    if (-not $IstWindows -or $OhneRueckfrage) { return }
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnk = Join-Path $desktop 'Repos aktualisieren.lnk'
    if (Test-Path -LiteralPath $lnk) { return }
    # Bevorzugt die Fassung im Zielordner: Die wird bei jedem Lauf mit
    # aktualisiert. Eine Kopie im Download-Ordner veraltet.
    $cmd = Join-Path $Ziel 'claude_mods\arbeitsplatz\Repos_aktualisieren.cmd'
    if (-not (Test-Path -LiteralPath $cmd)) { $cmd = Join-Path (Split-Path $PSScriptRoot -Parent) 'Repos_aktualisieren.cmd' }
    $antwort = Read-Host 'Verknüpfung „Repos aktualisieren“ auf dem Desktop anlegen? (J/n)'
    if ($antwort -and $antwort -notmatch '^[jJyY]') { return }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $v = $shell.CreateShortcut($lnk)
        $v.TargetPath = $cmd
        $v.WorkingDirectory = Split-Path $cmd -Parent
        $v.Description = 'Holt den aktuellen Stand aller GitHub-Repositories'
        $v.Save()
    } catch { }
    # Nachprüfen statt dem Rückgabewert glauben (Lehre aus
    # Revcomp_webapp\start\Verknuepfung_erstellen.cmd)
    if (Test-Path -LiteralPath $lnk) {
        Schreibe "Verknüpfung angelegt: $lnk" Green
    } else {
        Schreibe 'Die Verknüpfung konnte nicht angelegt werden. Starten Sie künftig direkt:' Yellow
        Schreibe "  $cmd" Yellow
    }
}

# ---------------------------------------------------------------------------
#  Ablauf
# ---------------------------------------------------------------------------
function Hauptablauf {
    Schreibe ''
    Schreibe '  Repos aktualisieren' Cyan
    Schreibe '  ===================' Cyan
    Schreibe ''

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Schreibe 'Git ist auf diesem Rechner nicht installiert.' Red
        Schreibe 'Bitte installieren (Eingabeaufforderung oder PowerShell):' Red
        Schreibe '  winget install --id Git.Git -e' White
        Schreibe 'oder von https://git-scm.com/download/win – alle Vorgaben übernehmen.' Red
        Schreibe 'Danach dieses Fenster schließen und neu starten.' Red
        return 1
    }

    $neuEingerichtet = $false
    $e = LadeEinstellungen
    if ($null -eq $e) { $e = ErsteEinrichtung; $neuEingerichtet = $true }
    $ziel = "$(Feld $e 'zielordner' $Vorgaben.zielordner)"
    $grund = PruefeZielordner $ziel
    if ($grund) {
        Schreibe $grund Red
        Schreibe "Einstellung ändern in: $Einstellungen (oder die Datei löschen und neu starten)" Red
        return 1
    }
    if (-not (Test-Path -LiteralPath $ziel)) { New-Item -ItemType Directory -Path $ziel -Force | Out-Null }

    # Einmalige, unschädliche Git-Einstellungen
    if ($IstWindows) {
        if ((GitLesen $ziel @('config', '--global', 'core.longpaths')).Text -ne 'true') {
            GitLesen $ziel @('config', '--global', 'core.longpaths', 'true') | Out-Null
        }
    }
    $lfs = (GitLesen $ziel @('lfs', 'version')).Code -eq 0
    if ($lfs) { GitLesen $ziel @('lfs', 'install', '--skip-repo') | Out-Null }

    $sammlung = SammleRepos $e $ziel
    foreach ($h in $sammlung.Hinweise) { Schreibe $h Yellow }
    $repos = @($sammlung.Repos)
    if ($repos.Count -eq 0) {
        Schreibe 'Keine Repositories gefunden.' Yellow
        return 1
    }

    $ergebnisse = New-Object System.Collections.Generic.List[object]
    $archiviertAusgelassen = 0
    foreach ($r in $repos) {
        if ($r.Archiviert -and -not (Test-Path -LiteralPath (Join-Path $ziel $r.Name))) { $archiviertAusgelassen++; continue }
        if (-not $r.Url -and -not (Test-Path -LiteralPath (Join-Path $ziel $r.Name))) { continue }
        try {
            $ergebnisse.Add((Bearbeite $r $ziel))
        } catch {
            $x = NeuesErgebnis $r (Join-Path $ziel $r.Name)
            $x.Art = 'fehler'; $x.Status = 'Unerwarteter Fehler: ' + $_.Exception.Message
            $ergebnisse.Add($x)
        }
    }

    # --- Übersicht --------------------------------------------------------
    Schreibe ''
    Schreibe "Übersicht ($ziel)" Cyan
    Schreibe ('-' * 72) DarkGray
    $farben = @{ ok = 'Gray'; neu = 'Green'; aktualisiert = 'Green'; hinweis = 'Yellow'; fehler = 'Red' }
    for ($i = 0; $i -lt $ergebnisse.Count; $i++) {
        $x = $ergebnisse[$i]
        $x.Nr = $i + 1
        $zweig = ''
        if ($x.Zweig) { $zweig = "  [$($x.Zweig)]" }
        Schreibe ("{0,3}  {1,-28} {2}{3}" -f $x.Nr, $x.Name, $x.Status, $zweig) $farben[$x.Art]
        foreach ($h in $x.Hinweise) { Schreibe ("       > {0}" -f $h) Yellow }
        Protokolliere ("{0}: {1}{2}{3}" -f $x.Name, $x.Status, $zweig, $(if ($x.Hinweise.Count) { ' | ' + ($x.Hinweise -join ' | ') } else { '' }))
    }
    Schreibe ('-' * 72) DarkGray
    if ($archiviertAusgelassen -gt 0) {
        Schreibe ((Plural $archiviertAusgelassen 'archiviertes Repository' 'archivierte Repositories') + ' nicht heruntergeladen.') DarkGray
    }
    if (-not $lfs) {
        Schreibe 'Git LFS fehlt: Große Dateien (z. B. .pptx) kommen nur als kurze Verweisdatei an.' Yellow
        Schreibe 'Abhilfe: Git für Windows neu installieren (enthält LFS) oder: winget install --id GitHub.GitLFS -e' Yellow
    }
    $fehler = @($ergebnisse | Where-Object { $_.Art -eq 'fehler' }).Count

    if ($neuEingerichtet) { BieteVerknuepfungAn $ziel }

    # --- Menü -------------------------------------------------------------
    if (-not $OhneRueckfrage) {
        while ($true) {
            Schreibe ''
            $eingabe = Read-Host 'Zweig wechseln? Nummer des Repositorys eingeben (Enter = beenden)'
            if (-not $eingabe) { break }
            $nr = 0
            if (-not [int]::TryParse($eingabe, [ref]$nr) -or $nr -lt 1 -or $nr -gt $ergebnisse.Count) {
                Schreibe 'Keine gültige Nummer.' Yellow
                continue
            }
            WechsleZweig $ergebnisse[$nr - 1]
        }
    }
    if ($fehler -gt 0) { return 1 }
    return 0
}

try {
    $rueckgabe = Hauptablauf
} catch {
    Schreibe ''
    Schreibe ('Abgebrochen: ' + $_.Exception.Message) Red
    Protokolliere ('Abgebrochen: ' + $_.Exception.Message)
    $rueckgabe = 1
}
exit $rueckgabe
