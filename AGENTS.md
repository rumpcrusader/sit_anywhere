# sit_anywhere — mod-specific agent guide

Read `res://mods/AGENTS.md` first and follow its general Home: Equestria mod rules. This file
adds only what is specific to `sit_anywhere`; keep it short and current.

## Scope

- Mod id `sit_anywhere`; version `1.0.0`; target game `0.3.0-maredev`.
- Desktop human Anon only. Z toggles a ground sit where he stands; moving or Q stands him up.
- AnonPony keeps her own Z sit. VR, real furniture seats and the game's save format are untouched.
- Player-facing summary and controls: `README.md`.

## Commands

- Source run: `./dev.sh`
  (or `godot --xr-mode off --path <project> -- --mod-src sit_anywhere`)
- Build: `./build.sh` -> `dist/sit_anywhere-1.0.0.pck`
- Release: bump `mod.json`, commit, tag `v1.0.0`, push the tag.
- Do not leave a built `sit_anywhere` pack in the game's mods folder while using `--mod-src`.
- The toggle key is `KEY_SIT` at the top of `main.gd`; rebuild after changing it.

## Commit and docs

- One behavior, fix, refactor or docs change per commit.
- Imperative scoped subject: `<scope>: <summary>`, 72 characters max, no trailing period.
- Run `./build.sh` before committing code or build changes.
- Commit locally. Do not push or tag unless the user asks.
- Docs describe current behavior only: no design diary, changelog or speculation.
- Keep `README.md` player-facing and `AGENTS.md` a short map. Update the layout when files move.
- Code comments explain non-obvious decisions; do not narrate obvious code.

## Layout

```text
sit_anywhere/
  mod.json       id, version, game_version, entry
  main.gd        Mods entry, Z toggle, temporary ground seat and floor-sit foot IK
  README.md      player-facing install and usage
  AGENTS.md      this guide
  build.sh       standalone pack builder
  dev.sh         run from source
  tools/pack.gd  packer used by build.sh
```

Keep this a map; update it when files change.

## Rules specific to this mod

- Keep game files untouched. The mod uses the game's `desktop_player` seat plumbing through
  `Mods` hooks and public methods.
- Never add a second sit state: `desktop_player.seat` staying a real `Node3D` is what drives the
  game's camera, collision, seated animation and stand-up rules.
- The temporary seat/holder must be removed and the player stood up when the mod is switched off,
  the world closes, or the game stands him up by itself.
- The negative seat `depth` is deliberate: it cancels the forward stand-up offset for a seat at
  his feet. Do not replace it with a positive depth without retesting the exit spot.
- The foot IK override (targets and knee hints) applies only while the mod's own seat is active
  and scales with `AnonBody.model_scale`.
- Desktop only: ignore AnonPony (`form_driver`) and headset rigs.
