# Installation

Requirements: AMX Mod X 1.10, Grip, ReChecker 2.7, ReAPI and FreshBans.

1. Ensure ReChecker is listed before AMX Mod X in `addons/metamod/plugins.ini`.
2. Copy `oldfrag_anticheat.amxx` to `addons/amxmodx/plugins/`.
3. Copy `oldfrag_anticheat.cfg` to `addons/amxmodx/configs/`.
4. Add `oldfrag_anticheat.amxx` after FreshBans in AMXX `plugins.ini`.
5. Add `exec addons/amxmodx/configs/oldfrag_anticheat.cfg` to `server.cfg`.
6. Remove/disable the old `rc_basechanger.amxx` to prevent concurrent writes.
7. Restart and run `ofac_status`, then `ofac_update` from server console.

The current `resources.ini` is retained as `resources.ini.backup`. A downloaded
group is activated only after its SHA-256 matches the GitHub manifest.
