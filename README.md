# War Planets

Godot 4.6.2 procedural pixel planet war sandbox.

## Core controls
- Click one of your cyan faction nodes to begin a strike, then click an enemy node.
- Drag the planet to rotate it; the combat camera automatically turns to hidden enemy launches and impact sites.
- Enemy factions retaliate after player strikes while they still have an operational launch node.
- Missile type escalates with planetary tension.
- Mouse wheel zooms on desktop.

## War resolution
- The player wins when every hostile civilization node has been destroyed.
- The enemy wins when every player civilization node has been destroyed.
- A completed war is locked so it cannot accidentally restart on that planet.
- The info/hint UI records the result and total strike count.

## Planet damage
- Every conventional and nuclear strike leaves a persistent impact scar attached to the rotating planet surface.
- Nuclear impacts create larger, hotter craters.
- Up to 32 recent war impacts are retained per planet to keep the effect readable and inexpensive.
- The most recent impact also feeds the terrain shader crater effect on compatible solid worlds.

## World generation
Every generated planet contains native alien life and a technological civilization, including desert, ice, gas giant, and lava worlds. Each world receives a player faction and one or two hostile factions.
