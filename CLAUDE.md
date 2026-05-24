# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Distopia: Bug Bash: Capture the Code** — A 2D top-down 4-player (2v2) capture-the-flag arena shooter built in Godot 4.6. Designed as an educational game for A.S.A. STEAM students (ages 12-15) across a 6–8 session after-school curriculum. The project intentionally contains 6 bugs for students to find and fix, introduced progressively across sessions.

**Core CTF loop:** 5-second safe spawn → Scout/Fight → Capture enemy flag → Return to Home Base for point → Repeat until time limit or score cap.

## Running the Game

The game requires separate server and client instances. Launch from the Godot editor or exported binary:

```bash
# Start server (headless or with server dashboard)
./Distopia --server

# Start client (connects to localhost by default)
./Distopia --client

# Connect to a specific address
./Distopia --client --address 192.168.1.100
```

The server listens on port 7777 (ENetMultiplayerPeer). Clients connect and select a team via the team selection UI. The game starts automatically once all players have joined.

```bash
# 1v1 mode (1 player per team, starts with 2 total)
./Distopia --server --1v1
```

## Architecture

### Multiplayer Authority Model

The server owns all authoritative game state: physics, collision resolution, damage calculation, flag ownership, team assignment, and the 180-second game timer. Clients handle local input and visual feedback only.

RPC patterns:
- `@rpc("authority")` — server-to-all-clients broadcast
- `@rpc("any_peer")` — client-to-server requests (e.g., `rpc_claim_team`, `rpc_request_flag`)
- Position sync uses unreliable mode (high frequency); game state changes use reliable

### Game Flow

1. `Main.gd` starts and parses `--server`/`--client` args → shows appropriate UI
2. `NetworkManager.gd` creates the ENet peer, builds the level via `LevelBuilder_claude.gd`, and manages the `TeamManager`
3. Clients select teams via `team_select.gd` → `rpc_claim_team()` → server assigns
4. Once 4 players are confirmed, server calls `_begin_game_server()` → spawns all players
5. `Player.gd` handles movement, weapon aiming, shooting, flag pickup, and home zone scoring
6. `Weapon.gd` (bullet) moves at 800px/sec; only the server resolves hit detection

### Level Generation

`LevelBuilder_claude.gd` reads `JSON/level.json` at runtime to build the tilemap:
- 13 rooms connected by 18 corridors (128px wide)
- Blue HQ at tile position (128,128); Red HQ at (2928,4928)
- Exposes `blue_spawns: Array[Vector2]` and `red_spawns: Array[Vector2]`
- Tileset loaded from `Assets/tilesets/GlitchHouse.png` (32×32 tiles)

### Key Scripts

| Script | Responsibility |
|--------|---------------|
| `Scripts/Main.gd` | Entry point; routes to server or client mode |
| `Scripts/NetworkManager.gd` | Peer creation, player spawning, flag/timer/score sync |
| `Scripts/Player.gd` | Movement (WASD), weapon rotation, shooting, health, flag logic |
| `Scripts/Weapon.gd` | Bullet movement, server-side hit detection, team friendly-fire check |
| `Scripts/LevelBuilder_claude.gd` | Procedural level from JSON |
| `Scripts/team_manager.gd` | peer_id → team_id mapping |
| `Scripts/team_select.gd` | Team selection UI controller |
| `Scripts/server_view.gd` | Server-side monitoring dashboard |

### Input Actions (defined in project.godot)

- Movement: `p1_left/right/up/down` (WASD), `p2_left/right/up/down` (Arrow keys)
- Shoot: `shoot` (Left mouse button)
- All actions have 0.2 deadzone

## Intentional Educational Bugs

The project is designed with 6 bugs introduced progressively across sessions. **Do not accidentally fix these when working on other issues.**

| Bug ID | Session | Area | Symptom | Fix |
|--------|---------|------|---------|-----|
| BUG-01 | Phase 1 | Movement | Player moves at half speed or slides uncontrollably | `move_and_slide()` velocity calculation / vector normalization |
| BUG-02 | Phase 2 | Logic | Ammo pickup gives 2 ammo instead of 6 | `ammo += 2` should be `ammo = 6` or `ammo += 6` |
| BUG-03 | Phase 2 | Node Config | Ammo pickups don't trigger; player passes through | `Area2D` has no child `CollisionShape2D` or shape resource is null |
| BUG-04 | —       | Physics | Player clips through walls | `CollisionLayer`/`Mask` mismatch between Player and Walls |
| BUG-05 | Phase 3 | Timer | Spawn timer shows 0 or doesn't count down | `Timer` wrong process mode, `wait_time = 0`, or `start()` not called |
| BUG-06 | Phase 4 | Multiplayer | Players see ghosts or ammo doesn't sync | Missing `is_multiplayer_authority()` checks or incorrect `rpc()` on ammo |

Before touching collision, timer, or ammo logic, verify you're fixing a real bug and not an intentional one. Check the `GDD` file for the authoritative bug spec.

### Ammo Pickup Pattern (GDD reference)
```gdscript
# AmmoPickup.gd — Area2D body_entered signal
func _on_area_entered(area):
    if area.is_in_group("player"):
        area.heal_ammo(6)  # BUG-02: intentionally set to 2 in broken version
        queue_free()
```

### Common Student Debugging Checklist (from GDD)
- **Player not moving?** Confirm `move_and_slide()` is in `_physics_process`, not `_process`
- **Area2D not detecting?** Check `Is Monitor` is ON and `CollisionShape2D` has a valid shape assigned
- **Ammo wrong value?** Check for `+= 2` vs `+= 6` or `= 6`
- **Multiplayer desyncs?** Confirm spawns only happen on server; check `MultiplayerSpawner` setup

## Implementation Divergence from GDD

The GDD recommends `MultiplayerSpawner` + `MultiplayerSynchronizer` for syncing nodes and variables. The actual implementation uses **manual RPCs** instead. When adding new synced state, follow the existing manual RPC pattern rather than introducing `MultiplayerSynchronizer`, unless refactoring is explicitly requested.

## Key Constants

- Player speed: 300 px/sec
- Bullet speed: 800 px/sec
- Bullet max range: 15,000 px
- Player health: 100 HP; bullet damage: 25
- Ammo per clip: 6
- Game duration: 180 seconds
- Server port: 7777; max peers: 4
