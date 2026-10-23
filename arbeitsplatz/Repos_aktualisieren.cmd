@echo off
REM ==========================================================================
REM  Repos aktualisieren
REM  Holt den aktuellen Stand aller GitHub-Repositories der Organisation auf
REM  diesen Rechner. Die Logik steht in Technik\repos_aktualisieren.ps1.
REM
REM  Warum alles in einer Klammer steht: Dieses Werkzeug aktualisiert auch das
REM  Repository, in dem es selbst liegt. cmd liest eine laufende Datei nicht
REM  auf einmal, sondern Zeile fuer Zeile weiter. Ersetzt der Abgleich diese
REM  Datei, laese cmd danach mitten in der neuen Fassung weiter. Eine Klammer
REM  liest cmd vollstaendig ein, bevor es sie ausfuehrt - danach wird nichts
REM  mehr von der Platte nachgelesen. (Gleiche Lehre wie in
REM  Revcomp_webapp\setup\Version_verteilen.cmd.)
REM ==========================================================================
(
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Technik\repos_aktualisieren.ps1" %*
    echo.
    pause
    exit /b
)
