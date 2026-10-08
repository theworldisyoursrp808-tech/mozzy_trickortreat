[README.md](https://github.com/user-attachments/files/33191662/README.md)
# 🎃 Mozzy Trick or Treat

Immersive, server-authoritative trick-or-treating for **Qbox**. Every door is a gamble: candy, a jackpot, nobody home, a prank, suspicious "homemade" candy... or a setup by 2–4 armed robbers.

## Requirements
qbx_core · ox_lib · ox_target · ox_inventory · OneSync · Lua 5.4

## Install
1. Drop `mozzy_trickortreat` into your resources and add `ensure mozzy_trickortreat` **after** qbx_core / ox_lib / ox_target / ox_inventory.
2. Paste `install/ox_inventory_items.lua` into `ox_inventory/data/items.lua` (one item per line).
3. Copy everything in `images/` into `ox_inventory/web/images/`.
4. Restart. No SQL needed — reputation is stored in Qbox player metadata (`mozzy_tot_rep`).

## Items
| Item | Image |
|---|---|
| mozzy_chocolate | mozzy_chocolate.png |
| mozzy_gummy_worms | mozzy_gummy_worms.png |
| mozzy_candy_corn | mozzy_candy_corn.png |
| mozzy_lollipop (ghost pops) | mozzy_lollipop.png |
| mozzy_gummy_bears | mozzy_gummy_bears.png |
| mozzy_candy_pumpkins | mozzy_candy_pumpkins.png |
| mozzy_sour_candy | mozzy_sour_candy.png |
| mozzy_caramel_apple | mozzy_caramel_apple.png |
| mozzy_candy_bag (usable — opens into random candy) | mozzy_candy_bag.png |
| mozzy_mystery_candy (hidden 15% laced chance) | mozzy_mystery_candy.png |
| mozzy_laced_candy (labelled "Halloween Candy") | mozzy_laced_candy.png |

All candy is edible (restores hunger, lowers stress — configurable per item in `Config.Consumables`).

## How a knock works
1. ox_target "Trick or Treat" on a door → server validates house id, distance, cooldowns, busy state, dead state.
2. Server **decides the outcome immediately** and returns only a token + presentation hints (delay, door NPC model).
3. Client knocks / rings, waits, NPC opens the door.
4. Client returns the token → server checks token, minimum elapsed time and distance again → grants rewards.

The client never names an item, amount, outcome or inventory content.

## Outcomes (`Config.Outcomes`, weighted)
normal · jackpot · laced · nobody · trick · cash · candybag.
**Robbery** is a separate `%` roll (`Config.Robbery.chance`) made before the outcome roll, so "5" really means ~5% of knocks.

## Robbery setup
* 2–4 NPCs (configurable) are **created server-side** (OneSync), placed 12–20 m away, armed with weighted weapons, and put in the player's routing bucket.
* They surround the player, aim/brandish, and an ox_lib menu appears: **Give money / Give candy / Refuse / Run** with a countdown.
* Money: % of cash (clamped). Candy: server reads the player's real ox_inventory and removes random owned Halloween items.
* Refuse → combat. Run → chance they chase; escape distance is verified server-side before the event ends.
* Optional loot-on-down, rep for cooperating / escaping / winning.
* Cleanup: on completion, timeout, player leaving the area, death of all robbers (after a body delay), disconnect and resource stop. The monitor thread only runs while a robbery exists.

## Laced candy
Symptoms start after a delay: timecycle distortion, post-FX, camera shake, motion blur, drunk walk, no sprint, move-speed drift, random stumbles/animations. With `passOutChance` the player stumbles → collapses → fades to black → stays unconscious → fades back in → gets up, and remaining effects fade. Never kills. Eating more while high stacks the duration.

## Police alerts
`Config.PoliceAlert.system = 'auto'` picks the first running of ps-dispatch, cd_dispatch, qs-dispatch, core_dispatch, rcore_dispatch, else the built-in **qbx** fallback (notifies on-duty `leo` players + temporary blip). Add your own in `shared/bridge.lua → Dispatch.systems`.
> Dispatch exports change between versions — double-check the payload for the one you run.

## Commands
* `/totrep` — your Halloween rank & rep.
* Debug mode only (`group.admin`): `/tot_force <outcome>`, `/tot_resetcd`, `/tot_laced`.

## Security summary
Server validates: house id, coordinates, interaction + finish distance, global / house / player-house / per-period cooldowns, one interaction at a time, token + minimum timing on finish, item ownership by slot before removal, inventory weight **before** a candy bag is removed, money via qbx_core, rate limiting per player. Fallback police alerts are only accepted when the server requested one. Set `Config.Security.dropOnExploit = true` to kick offenders.

## Performance
Door zones are created lazily with `lib.points` (grid based) only within `Config.Target.loadDistance`; nothing loops over the 311 houses. Effect loops only exist while an effect / robbery is active.

## Notes
* Cooldowns live in memory and reset on resource restart.
* 311 default doors were imported from gl-halloween and de-duplicated. Add more as `vector3(...)` or `{ coords = vector3(...), label = '...' }`.
* `Config.Season` / `Config.NightOnly` can lock trick-or-treating to October nights.
