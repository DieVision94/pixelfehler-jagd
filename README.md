# Pixelfehler-Jagd

Kleines Spiel für **GeoWorks Ensemble 1.x** (`PIXJAGD.GEO`).

## Download / Installation

1. [`dist/PIXJAGD.GEO`](dist/PIXJAGD.GEO) nach `GEOWORKS\WORLD` kopieren.
2. Im GeoManager **Pixelfehler-Jagd** starten, dann ins Spielfeld klicken.
3. Keine INI-Änderung nötig.

## Spielidee

In 60 Sekunden Pixelfehler-Bugs wegklicken. Rot = 10, violett = 20, gelb = 50 Punkte. **Blaue** Bugs nicht klicken (−25). Combos bis ×5. Pause über „Spiel: Läuft / Pause“.

## SHA-256

```
d7f6c6cdbca7a356cff91b38746563a61139b7b2a57b6f52fd3ca6c7ee6c1eba  dist/PIXJAGD.GEO
```

## Inhalt

- `dist/PIXJAGD.GEO` – fertiges Spiel
- `pixjagd.asm` / `sprites.inc` / `strings.inc` – Quellen
- `build_game.py` – Build (python3 + nasm)
- `shots/` – Screenshots
- `CHANGELOG.md` – Versionen

Voraussetzung: eigene GeoWorks-Ensemble-Installation. Dieses Repo enthält **kein** GeoWorks-Betriebssystem.

---

## Hinweis: mit KI erstellt

**Dieses Spiel und diese Dokumentation wurden mit KI erstellt** (u. a. Grok Bot / Cursor-Agenten), begleitet und getestet von Valentin Möller und Johannes Möller. Community-/Hobby-Projekt, kein offizielles GeoWorks-Produkt.
