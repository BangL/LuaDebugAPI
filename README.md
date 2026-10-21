# LuaDebugAPI

Live-Debug-API fuer RAID: WW2. Fuehrt Lua-Code in der laufenden Spielsession aus
und liefert das Ergebnis zurueck. Transport ist Datei-IPC (kein Socket: das Spiel
hat kein LuaSocket, die Hook-DLL ist unter Linux nicht baubar).

**Achtung:** fuehrt ungefiltert beliebigen Code aus, ohne Authentifizierung. Jeder
Prozess mit Schreibzugriff auf `io/` kann das Spiel steuern. Nur fuer Entwicklung.

## Benutzung

```
mods/LuaDebugAPI/ldb '<lua code>'
mods/LuaDebugAPI/ldb -f script.lua
LDB_TIMEOUT=30 mods/LuaDebugAPI/ldb '...'   # Timeout in s, Default 10
```

Beispiele:

```
ldb 'game_state_machine:current_state_name()'   # -> OK "menu_main"
ldb 'managers.player:player_unit():position()'
ldb 'out("hi"); log("x"); return {a=1}, "s"'
ldb 'DevTools:reset_menu()'                      # Relua (siehe unten)
```

## Protokoll

1. Client schreibt `io/cmd.lua` (atomar: erst `cmd.tmp`, dann `mv`).
2. Der Mod pollt alle 0,05 s (Post-Hook auf `Setup:update`, laeuft in Menue und
   Spiel), liest und loescht `cmd.lua`, fuehrt den Chunk aus.
3. Er schreibt `io/res.txt` (atomar via `res.txt.tmp`). Der Client liest und loescht sie.

Ein Befehl nach dem anderen: `ldb` loescht vor dem Senden eine alte `res.txt`.

## Ausfuehrung

- Code wird zuerst als `return <code>` geladen (Ausdruck), sonst als normaler Chunk.
- Umgebung: `_G` (Lese- und Schreibzugriffe gehen auf `_G`), plus `out(...)`.
- `out(...)` und `log(...)` waehrend des Befehls werden ins Ergebnis uebernommen
  (`log` zusaetzlich normal ins BLT-Log).
- Ausfuehrung ueber `blt.xpcall` (Traceback via `debug.traceback`, falls vorhanden),
  der aeussere Schutz ueber `blt.pcall`. Globales `xpcall` ist `nil` im Spiel,
  ungefangene Fehler im `update` crashen die Engine.

## Ergebnisformat

Zeilen mit `out`/`[log]` zuerst, dann die letzte Zeile:

- `OK <wert>, <wert>, ...` - Rueckgabewerte (`nil` wird als `nil` ausgegeben)
- `ERR <meldung>` (+ Traceback) - Fehler im Befehl
- `ERR syntax: ...` - Chunk nicht ladbar
- `ERR internal: ...` - Fehler im Mod selbst

Serialisierung: Tabellen bis Tiefe 3, max. 200 Eintraege je Tabelle, Zyklen als
`<cycle>`, Userdata (Vector3, Unit, Idstring, ...) per `tostring`. Gesamtausgabe
max. 200000 Zeichen (`<truncated>`). Limits in `LuaDebugAPI.lua` (`L.max_*`).

## Lua-Reload

Beim Reload (`DevTools:reset_menu()`, `reset_server()`, F10) entsteht ein neuer
Lua-State. Der Befehl kann ohne Antwort bleiben (Timeout) oder bekommt sie noch vor dem
State-Wechsel (beim Test: `OK `). Der Mod laedt sich neu und ist nach wenigen Sekunden wieder erreichbar:

```
ldb 'DevTools:reset_menu()'; until ldb '1' 2>/dev/null; do :; done
```

## PD2

Derselbe Mod-Ordner laeuft (ungetestet) auch unter PAYDAY 2: `mod.txt` liegt neben
`supermod.xml`, `blt.xpcall`/`blt.pcall` fallen auf `xpcall`/`pcall` zurueck. Die
Relua-Beispiele (`DevTools:reset_menu()`) sind RAID-spezifisch.

## Dateien

| Datei | Rolle |
| --- | --- |
| `supermod.xml` / `mod.txt` | Post-Hook auf `lib/setups/setup` (RAID / PD2) |
| `LuaDebugAPI.lua` | Polling, Ausfuehrung, Serialisierung |
| `ldb` | Shell-Client |
| `io/` | `cmd.lua`, `res.txt` (Laufzeit, nicht versionieren) |
