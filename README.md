# LuaDebugAPI

Live debug API for **RAID: World War II** and **PAYDAY 2** (both DIESEL, SuperBLT).
Executes Lua code in the running game session and returns the result via file IPC.

**Warning:** executes arbitrary code without any authentication. Any process with write
access to `io/` can control the game. For development only.

## Usage

```
mods/LuaDebugAPI/ldb '<lua code>'
mods/LuaDebugAPI/ldb -f script.lua
LDB_TIMEOUT=30 mods/LuaDebugAPI/ldb '...'   # timeout in s, default 10
```

Examples:

```
ldb 'game_state_machine:current_state_name()'   # -> OK "menu_main"
ldb 'managers.player:player_unit():position()'
ldb 'out("hi"); log("x"); return {a=1}, "s"'
```

`ldb` is a POSIX shell script. On Windows, write `io/cmd.lua` and read `io/res.txt`
yourself (see Protocol).

## Protocol

1. The client writes `io/cmd.lua` (atomically: write `cmd.tmp`, then `mv`).
2. The mod polls every 0.05 s (post-hook on `Setup:update`, runs in menu and in game),
   reads and deletes `cmd.lua` and executes the chunk.
3. It writes `io/res.txt` (atomically via `res.txt.tmp`). The client reads and deletes it.

One command at a time: `ldb` deletes a stale `res.txt` before sending.

## Execution

- The code is first loaded as `return <code>` (expression), otherwise as a plain chunk.
- Environment: `_G` (reads and writes go to `_G`), plus `out(...)`.
- `out(...)` and `log(...)` calls during the command are included in the result
  (`log` still goes to the BLT log as usual).
- Runs through `blt.xpcall` (traceback via `debug.traceback` if available), outer guard
  through `blt.pcall`; both fall back to `xpcall`/`pcall` if `blt.*` is missing.
  Note: the global `xpcall` is `nil` in RAID, and an uncaught error in `update` crashes
  the engine.

## Result format

`out`/`[log]` lines first, then the final line:

- `OK <value>, <value>, ...` - return values (`nil` is printed as `nil`)
- `ERR <message>` (+ traceback) - error in the command
- `ERR syntax: ...` - chunk could not be loaded
- `ERR internal: ...` - error in the mod itself

Serialization: tables up to depth 3, at most 200 entries per table, cycles as
`<cycle>`, userdata (Vector3, Unit, Idstring, ...) via `tostring`. Total output is
capped at 200000 characters (`<truncated>`). Limits: `L.max_*` in `LuaDebugAPI.lua`.

## Games

| Game | Definition | Status |
| --- | --- | --- |
| RAID: WW2 | `supermod.xml` | tested: expressions, `out`/`log`, tables, `nil`, errors |
| PAYDAY 2 | `mod.txt` (`supermod.xml` is shipped too) | tested: expressions, `out`/`log`, tables, `nil`, errors |

## Files

| File | Role |
| --- | --- |
| `supermod.xml` / `mod.txt` | post-hook on `lib/setups/setup` (RAID / PD2) |
| `LuaDebugAPI.lua` | polling, execution, serialization |
| `ldb` | shell client |
| `io/` | `cmd.lua`, `res.txt` (runtime, not versioned) |
