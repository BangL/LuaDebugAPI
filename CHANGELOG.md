0.3.1:
- separate io folder per game (io-raid/, io-pd2/ via blt.blt_info().game), so one checkout can be linked into both games
- ldb: the PD2 process is PAYDAY2.exe
- auto updates via raid-mods-meta (PD2)

0.3.0:
- heartbeat only while ldb requests it (hb_want, 60 s)
- setup-tmpfs.sh moves io/ to /dev/shm, io/ is created by the mod instead of shipped

0.2.2:
- ldb -f: abort if the file cannot be copied

0.2.1:
- ldb: process name and crash.txt path per game (PD2 support)

0.2:
- heartbeat, error log, command journal, ldb --status/--errors/--watch, crash/hang diagnosis
- polls while the game is paused
- English timeout message and README, MIT license
- PD2 fallbacks
- update meta

0.1:
- initial version: live Lua debug API via file IPC
