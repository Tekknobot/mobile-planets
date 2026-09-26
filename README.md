# War Planets

Godot 4.6.2 procedural pixel planet war sandbox.

## Core controls
- Click any surviving cyan faction node to begin a strike. The game automatically uses your best operational Missile Base as the launch site, then click an enemy node to attack it.
- Drag the planet to rotate it; the combat camera automatically turns to hidden enemy launches and impact sites.
- Enemy factions retaliate after player strikes while they still have an operational Missile Base or Capital.
- Missile type escalates with planetary tension. Nuclear weapons require a surviving Missile Base; a Capital fallback can only launch conventional missiles.
- Mouse wheel zooms on desktop.

## Strategic node classes
Every newly generated faction receives five specialized nodes:

- **Capital** — command center. Improves friendly interception coordination and provides an emergency conventional launch site if the Missile Base is lost.
- **Missile Base** — primary launch infrastructure and the only node capable of launching nuclear strikes.
- **Defense Array** — can intercept incoming missiles within its planetary coverage. A Defense Array cannot intercept a missile aimed directly at itself.
- **Industry** — hardens the rest of the faction network, reducing conventional damage to other friendly nodes while it survives.
- **Radar** — greatly expands Defense Array coverage and improves interception probability.

Each class has a distinct small pixel glyph around its faction marker so roles can be identified directly on the globe.

## Strategic enemy AI
Enemy retaliation is role-aware rather than population-only:
- Active Defense Arrays are usually attacked first so later missiles can get through.
- Missile Bases are high-priority targets because destroying them removes nuclear launch capability.
- Radar becomes especially valuable while a Defense Array is online.
- Capitals and Industry are prioritized for their command and network-support effects.
- Already damaged nodes gain a finishing priority, so the AI will often try to eliminate weakened infrastructure instead of spreading damage randomly.

## Defense interception
- A surviving Defense Array may destroy an incoming missile before impact if the target is within coverage.
- Radar expands coverage from roughly regional/hemispheric defense to broad planetary coverage and increases interception odds.
- A surviving Capital provides a smaller coordination bonus.
- Nuclear missiles are harder to intercept than conventional missiles.
- Successful interception is shown in flight with a defensive beam and mid-air impact burst. The target takes no damage and no crater is created.
- Intercepted player attacks still provoke enemy retaliation.

## War resolution
- The player wins when every hostile civilization node has been destroyed.
- The enemy wins when every player civilization node has been destroyed.
- A completed war is locked so it cannot accidentally restart on that planet.
- The info/hint UI records the result and total strike count.

## Planet damage
- Conventional strikes normally deal 55% damage. With hostile Industry still active, non-Industry targets receive reduced conventional damage and may require a third hit.
- Nuclear impacts destroy their targeted node immediately.
- Every successful conventional and nuclear strike leaves a persistent impact scar attached to the rotating planet surface.
- Nuclear impacts create larger, hotter craters.
- Up to 32 recent war impacts are retained per planet to keep the effect readable and inexpensive.
- The most recent impact also feeds the terrain shader crater effect on compatible solid worlds.

## World generation
Every generated planet contains native alien life and a technological civilization, including desert, ice, gas giant, and lava worlds. Each world receives a player faction and one or two hostile factions, with one of each strategic node class per faction.
