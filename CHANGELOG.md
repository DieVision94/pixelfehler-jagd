# CHANGELOG – Pixelfehler-Jagd (GeoWorks 1.x)

Alle Zeiten Europe/Berlin (MEZ).

## 2026-11-15 09:42 – Build d7f6c6cd (Release-Stand)
* `build/PIXJAGD.GEO` 8692 Bytes, SHA256 `d7f6c6cdbca7a356cff91b38746563a61139b7b2a57b6f52fd3ca6c7ee6c1eba`
 (Kopie: `build/PIXJAGD_d7f6c6cd.GEO`)
* Testvariante `build/PIXJAGD_test.GEO` SHA256 `2902902a5c7e9e4f8306d641ff5d3e46d329d621c3adf23c884ae73842f77410`
* Neu gegenüber r1: Zufallsgenerator xorshift16 (vorher LCG mit schlechter Typverteilung), Beinphase je Bug versetzt,
 Endpunktzahl zentriert, Spruch „Weiter geht's!“ nach Pause, Combo-Anzeige enger, eigene Icons (6 Monikers).
* Getestet in lokaler BaseBox (VGA 640x480, frische GEOS-Kopie `env2`): Icon im GeoManager, Start, Titel, Spiel, Treffer,
 Combo, Fehlklick, Goldkäfer-Treffer, Goldkäfer entkommen, Bluescreen-Bug mit Fake-Bluescreen, Pause/Weiter, Zeitablauf,
 Endbildschirm, neue Runde, Schließen über das Systemmenü, erneuter Start und erneutes Schließen. Kein Absturz, Rückkehr
 zum GeoManager funktioniert. Uhr gegen Echtzeit geprüft (11–12 Spielsekunden auf ca. 11,6 s).

## 2026-11-15 09:28 – r1 (erster lauffähiger Build, b558bc71)
* Machbarkeit geklärt: Vorlage BOUNCE.GEO, eigene Methodentabelle und eigener Code, Kernel-Nummern aus 1.x-Apps abgeleitet.
* Läuft beim ersten Start: Titelbild, Bugs, HUD, Endbildschirm, sauberes Schließen.
* Backups: `src/pixjagd.asm.bak_r1`, `tools/build_game.py.bak_r1`, `build/PIXJAGD_r1.GEO`.

## 2026-11-15 09:15 – Projektstart
* Eigene Testumgebung: Kopie der GEOS-Installation (`env/`), eigene BaseBox-Binärkopie (`gbox/gamebox`), eigenes Display :77.
 Die SVGA16-Arbeit (`geos-mouse/src`, `build/SVGA16*`, `testenv/runbb_*`, Display :98) wurde nicht angefasst.
* nasm fehlte auf der Box und wurde lokal aus den vorhandenen Quellen nach `.nasm/src` kompiliert.
