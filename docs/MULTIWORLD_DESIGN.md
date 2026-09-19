# Multiworld implementation plan

## Goal

Support independent physical world directories in one Luanti server process, with player-specific world membership and no coordinate-offset emulation.

## Constraints

- Each world has its own `world.mt`, map database, player database, mod storage, and environment state.
- A player may change worlds without moving other players.
- Network peers must be routed to the environment that owns the player.
- Lua callbacks, authentication, inventories, formspecs, and media state must not leak between worlds.

## Implementation phases

1. Introduce a `WorldInstance` owner that groups the environment, map, Lua state, mod manager, and world-specific settings.
2. Keep the existing single-world server path unchanged while adding a world registry.
3. Add explicit player-to-world membership and a controlled transfer operation.
4. Route incoming packets by peer/player membership instead of broadcasting them to every world.
5. Route outgoing packets and object updates through the owning world.
6. Add lifecycle handling for world creation, shutdown, and transfer failure.
7. Add unit tests for world isolation and a dedicated-server smoke test before enabling the feature by default.

## Important non-goals

The implementation must not use coordinate offsets inside one map database. It must not construct multiple `Server` objects sharing global Lua/settings/network state as a shortcut.
