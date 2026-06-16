<div align="center">

<img src="icon.svg" alt="Theria" width="72">

<h1>Changelog</h1>

<p><i>Every notable change, newest first.</i></p>

<p>
  <a href="README.md"><b>README</b></a> ·
  <b>Changelog</b> ·
  <a href="CREDITS.md"><b>Credits</b></a> ·
  <a href="LICENSE"><b>License</b></a>
</p>

</div>

---

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The
load-bearing compatibility axes are the save/profile schema and the netcode
protocol version.

## [Unreleased]

## [v0.3.3] — 2026-06-16

### Changed

- The client now launches in **fullscreen** instead of a maximized window.

## [v0.3.2] — 2026-06-16

### Fixed

- Packaged builds shipped without their 3D models, so the client crashed when a match
  started (and the auto-updated build was missing all hero, creep, and structure art). The
  release pipeline was not fetching the model and texture assets when building, so they were
  silently left out; it now pulls them, and the launcher and the auto-update payload contain
  the full art again.

## [v0.3.1] — 2026-06-16

### Fixed

- Exported launchers could not self-update: every launch reported **"a new Theria is out —
  please re-download the client"** and refused the update, because the build could not read
  its own version number and so judged itself too old for any build. The version is now read
  from a source that is always present in an exported build, so the client recognises its own
  version and updates normally.

## [v0.3.0] — 2026-06-16

### Added

- A **Stable / Beta update channel** toggle in Settings. Beta (the default) keeps every new
  build arriving automatically, as before; Stable follows only cut releases, for testers who
  want a steadier client between releases. The choice is saved and applies on the next launch,
  and a tagged release now ships the same auto-update payload the rolling channel does, so the
  Stable channel has a build to follow.

## [v0.2.0] — 2026-06-16

### Added

- An **in-client auto-updater**, so playtesters install Theria once and get new builds
  automatically. The client now opens on a short update screen that checks for the latest
  build and, when a newer one is published, downloads it and loads it over the bundled copy
  before the match starts — no one re-downloads by hand to stay current. It is offline-safe:
  with no connection, a failed download, or an unreachable server it simply starts the build
  you already have, and it never touches your settings or saved data. Launches from the command
  line (and headless runs) skip the check and go straight into the match.
- A **title screen** in place of the bare connect menu: the Theria wordmark heads a consistent,
  themed look shared with the update screen, and a footer shows your build id and update status
  — so a bug report can name exactly which build you were on — alongside a Settings button
  (video and audio options to come).

### Changed

- Builds are now published automatically. Every accepted change to `main` republishes the
  downloadable game package the in-client updater pulls; a tagged release additionally produces
  the downloadable Windows and macOS launchers. (macOS builds are unsigned for now — see the
  README for the one-time Gatekeeper step.)

## [v0.1.0] — 2026-06-16

### Changed

- The arena is now a hand-designed map laid out on a single diagonal axis of symmetry rather
  than the placeholder square diamond. The two lanes each bow out to one side of the map, a
  river meanders across the middle, and the jungle holds two shared neutral camps on the axis
  plus mirrored side camps. Each team defends four towers — two ringing its nexus and two
  forward down the lanes — and the nexus itself. The whole map mirrors across the team-base
  diagonal — one team's geometry is the other's reflected — so neither side has a positional
  edge. The arena is sized to about 65% of a standard 5v5 map's side length — a tighter 3v3
  footprint — and the movement speeds are tuned to match, so heroes and creeps move at a
  comparable pace and a lane takes a standard-MOBA walk to cross rather than a sprint. The
  simulation, the bots, and the netcode read the same geometry data, so the change is layout
  and tuning only; the protocol is unchanged.
- The lane creeps and the structures now wear placeholder 3D models — a slime for a creep,
  a watchtower for a tower, a crystal for the nexus — in place of the debug capsules and
  boxes, handled like the hero animals: each is auto-scaled to its on-field size, stood on
  the ground, and washed in its team colour, with its floating bars tucked just above its
  own measured top. So the whole field reads as models rather than the heroes standing among
  debug primitives. Bundled asset licenses are credited in [`CREDITS.md`](CREDITS.md).
  Presentation only — the simulation and the netcode protocol are unchanged.
- Every field unit — heroes, creeps, and structures — now renders under a stylized cel shader
  in place of the raw imported lighting: the key light is banded into flat tones for a low-poly
  toon look, the shadow side reads as a deliberate matte tone rather than going black, and the
  team colour is blended into the model's own albedo so blue and red read at a glance while each
  model keeps its texture and species detail. Presentation only — the simulation and the netcode
  protocol are unchanged.
- The ground is now a jungle short-grass surface in place of the flat dark plane: a procedural
  shader breaks it into toon-quantised patches of two greens, cel-banded to match the units, so
  the field reads as clumped grass under the models rather than a dead slab. The lane dirt paths,
  the river, and the camp markers still lay over it. Presentation only — the simulation and the
  netcode protocol are unchanged.
- Field units now read cleanly against the ground with a rim light and a drop shadow: a
  hard-edged fresnel rim lights each model's silhouette so it pops off the grass, and a soft blob
  shadow sized to the unit's own footprint sits under every hero, creep, and structure so it
  stands on the ground rather than floating. Presentation only — the simulation and the netcode
  protocol are unchanged.
- The map decor is reworked into the jungle look: the lanes are trampled dirt paths (dappled
  worn earth with edges frayed into the grass), and the river is a stylized toon water — a
  smoothed, gently meandering watercourse with drifting current bands and shallow banks. Both are
  now built as one continuous mitred ribbon mesh per shape rather than a row of separate boxes, so
  a winding lane or river turns its bends without angular gaps. A flat wooden plank bridge is laid
  wherever a lane crosses the river (the top lane crosses twice), found by intersecting the lane
  and river geometry. Presentation only — the simulation and the netcode protocol are unchanged.
- The follow-camera now eases to the hero instead of locking to it 1:1, so a sharp turn or a
  respawn glides the view rather than snapping it; and while the hero is gone (dead, or not yet
  spawned) the camera rests where the hero last stood instead of jumping to the arena centre.
  Presentation only.
- Controls now follow the MOBA standard: move the hero by **right-clicking** the ground
  (click-to-move, hold and drag to keep steering) and cast abilities with **Q · W · E · R**,
  in place of driving with WASD and casting on the number row. The click destination is
  resolved to a movement direction on the client before it reaches the simulation, so the
  authoritative per-tick movement model and the netcode protocol are unchanged — this is an
  input change only.
- The hero models now turn to face where they move instead of sliding sideways, and the
  rigged one (the spider) loops a walk cycle while it moves and an idle one while it stands
  — the others, which ship no animation, just turn. Presentation only.
- The hero models read cleaner: their team-colour wash is lighter, so a dark animal (the
  spider) keeps its own colour instead of drowning to near-black, and each hero's floating
  bars now hang just above its own model — the short animals and the tall ones both read
  tucked to the body rather than under one shared height that detached over the small ones.
- The heroes now wear placeholder 3D models — a distinct low-poly animal per kit (lion,
  cheetah, hyena, snake, spider, chameleon) standing in for the species each shapeshifter
  takes — in place of the capsule bodies. The models come from mixed sources at different
  authored scales, so each is auto-scaled to a common on-field size, stood on the ground,
  and washed in a translucent team colour, so squadmates read apart by species while teams
  stay legible at a glance. Creeps and structures keep their primitives for now. Bundled
  asset licenses are credited in [`CREDITS.md`](CREDITS.md). Presentation only — the
  simulation and the netcode protocol are unchanged.
- The match now renders in 2.5D: a pitched, close camera follows your hero across the
  field — heroes and creeps stand as shaded capsules and structures as boxes on a lit
  ground, replacing the flat top-down dots. HP and resource bars and the human/animal
  form ring float above each unit, and a unit's active statuses now show as a floating
  label over it (`STUNNED` / `POISONED` / `SLOWED`) so crowd control is legible at a
  glance. Casting aims by ray-casting the mouse onto the ground. The simulation stays a
  flat 2D world and the netcode is untouched — this is a presentation change only, so the
  protocol version is unchanged. Placeholder primitives stand in until art lands.
- Snapshots are now packed into a compact binary wire format — a short header plus one
  fixed byte record per entity, with floats narrowed to 32 bits — instead of a Variant
  container. A full opening creep wave drops from roughly 3 KB to under 1 KB, so the
  whole world now fits in a single unreliable datagram rather than fragmenting above the
  transport's packet-size limit. Rendering is unchanged; positions round-trip exactly.
  The netcode protocol version advances to 3 (the snapshot wire shape changed).

### Added

- Heroes now respawn instead of dying for good. A slain hero is no longer erased — it falls,
  goes inert (it cannot move, fight, cast, or be targeted), and a respawn clock counts it back,
  returning it at full health at its spawn point a few seconds later; only creeps and structures
  stay dead. While the player's own hero is down a death screen dims the match and shows the
  respawn countdown, and any standing move order is dropped so the hero comes back idle at base
  rather than walking off toward a pre-death click. The respawn timer rides the snapshot, so a
  networked client raises its own death screen straight from the wire — the netcode protocol
  version moves to **4** for the added field.
- Press **S** to stop the hero where it stands, clearing the current move or attack order (the
  MOBA-standard hold-position): tap it to cancel a path, hold it to stay planted while a fresh
  right-click is held. Client-side input only; the simulation and the netcode protocol are
  unchanged.
- Right-clicking an enemy now attacks it: the hero closes to its attack range and the combat
  step strikes it (LoL-style attack-on-click), while right-clicking open ground still just
  walks there — one button both moves and engages. Client-side input only; the simulation and
  the netcode protocol are unchanged.
- Combat now reads on screen. Every hit — an auto-attack, an ability, or a venom tick — pops
  a floating damage number over the struck unit, so damage is legible instead of only a bar
  ticking down. Auto-attacks themselves now show: a ranged attacker (a tower, a skirmisher
  hero) flies a bolt at its target, while a melee one (a creep, a brawler hero) flashes a
  close-in impact. The sim records each hit and strike on a per-tick presentation log it
  already keeps for casts; like that log it never crosses the wire, so this is a LOCAL/HOST
  render change only — the simulation and the netcode protocol are unchanged.
- A click-to-move destination marker: right-clicking lays a pulsing ring on the ground where
  the hero is headed, so the move target reads at a glance. Presentation only.
- Abilities now show on screen instead of resolving invisibly. Each cast flashes for a
  beat: a skillshot or a unit-targeted ability draws a beam from the caster to where it
  landed, a ground area draws a disc at its **true radius** — so a zone like the Spider's
  stun nest reads its real footprint — and a self-cast (a heal, a shapeshift) pulses a ring
  on the caster. The flash is coloured by what the cast does (warm for damage, green for a
  heal, or the status's own colour for a stun, slow, or poison) and fades out and frees
  itself, so the field stays clean. The simulation records each cast on a transient log the
  renderer drains every tick; it never crosses the wire, so the netcode protocol is
  unchanged (a snapshot-fed client draws no cast FX, as it shows no statuses).
- Stun joins the lingering-status roster as a hard crowd-control effect: a stunned unit
  cannot move, cast, or auto-attack until it wears off. The Verdani Spider's **Web Nest**
  now lays this brief lock over its zone instead of a slow — its instant hit is trimmed in
  trade — so the trapper opens a window rather than just chipping. The Spider keeps its
  ranged **Web Snare** slow, so it now controls with both a snare and a lock. Like the
  existing venom and web statuses, the effect is resolved entirely in the simulation; the
  netcode protocol is unchanged.
- Practice bots now have a difficulty: **Easy**, **Normal**, or **Hard**, chosen from the
  connect screen's new picker or with `--bot-difficulty`. Easy is the default, so a practice
  match is winnable out of the box, while Hard is the previous full-strength bot. A lower
  difficulty slows the bots' reaction — they open their pokes on a slower beat, so a player
  can out-trade them — and meters a kiter's retreat so it no longer backs away flawlessly
  and can be run down; otherwise their judgement is undulled: a bot at any level still
  positions, shifts form, and heals exactly as sharply. Sim-side and menu only; the netcode
  protocol is unchanged.
- A practice match can now be set up entirely from the connect screen: a hero picker lists
  every hero of both tribes, and the choice drives the same tribe-versus-tribe seating as the
  command line's `--hero`, so picking a side no longer needs a flag. The screen now renders as
  a framed card over an opaque backdrop, so its controls read clearly instead of floating over
  the arena. On the field, each hero now wears a distinct shade of its team colour, so three
  squadmates read apart at a glance instead of sharing one flat colour. Presentation and menu
  only; the simulation and the netcode protocol are unchanged.
- Bots now position to their hero's stance instead of all closing in the same way: the
  skirmishers (Cheetah, Chameleon) kite — they hold their ranged form and keep an enemy
  inside their skillshot band, backing off a point-blank attacker and closing on a distant
  one, so they poke hit-and-run rather than committing to melee. Brawlers keep closing and
  shifting toward whichever form can land a hit. Stance is authored per kit and read by the
  bot; sim-side only, the netcode protocol is unchanged.
- The Verdani's venom and web are now mechanics, not just names: a venom strike leaves a
  damage-over-time that keeps biting for two seconds after it lands, and a web leaves a
  movement slow on what it catches. Each venom ability trades part of its instant hit for
  that lingering damage, so the Verdani lean on attrition where the Solane stay burst. A
  struck unit carries one instance of each effect — a re-cast refreshes rather than stacks.
  Sim-side only; the netcode protocol is unchanged.
- A practice match is now a tribe-versus-tribe choice: `--hero` accepts any hero of either
  tribe, and the chosen hero's tribe fields the player's team while the opposing tribe fills
  the bots — so the Verdani are now playable, not just an opponent. The default still
  seats the Solane against the Verdani. Which heroes form which tribe is recorded once in
  the ability catalog and read by the client, so the rosters cannot drift apart.
- A second hero roster, the **Verdani** — jungle venom-and-shadow shifters (snake,
  spider, chameleon) — joins the Solane as the opposing tribe, authored on the same
  ability primitives as a deliberate foil: the snake is a venom striker with the
  longest single-target lock, the spider a trapper laying the widest, lowest-power
  ground webs, and the chameleon an ambusher carrying the single heaviest hit of either
  roster. A practice match now fields the player's Solane squad against a bot Verdani
  squad rather than a Solane mirror, so both rosters are exercised at once. Sim-side
  content only; the netcode protocol is unchanged.
- Bots now shapeshift mid-fight instead of fighting from one form: a bot transforms
  toward the form that can land a hit when its current one cannot — closing into its
  harder-hitting animal kit as an enemy slips inside the human poke's range, and back
  to the human form to poke at range — and a hurt bot in animal form shifts back to
  the human form for its heal when one is ready. The transform's own cooldown keeps
  the stance from flip-flopping. This unlocks the animal kits in a practice match.
- Bots now cast their hero kit, not just walk: a bot heals itself when its health
  drops and otherwise fires the first damaging ability of its active form that can
  actually reach its target, picking the aim the way a player would. The reach test
  mirrors each ability's landing geometry, so a bot never wastes a cast on empty air.
  This makes a practice squad fight with abilities instead of only auto-attacking.
- A practice match now fields the full **Solane** squad on each team — one hero per
  kit (Lion, Cheetah, Hyena) — so all three are on the field at once. The player drives
  one (the Lion by default, or `--hero cheetah`/`--hero hyena`) and bots drive the rest.
  A hosted or joined match stays a one-hero-per-team duel until multi-hero play reaches
  the wire.
- The first roster of distinct heroes — the **Solane**, a tribe of savanna big-cat
  shifters: a **Lion** frontline bruiser (short-range pokes, a heavy melee strike, and
  the deepest self-sustain), a **Cheetah** burst skirmisher (long-range pokes and a
  fast, repeatable single-target shred), and a **Hyena** zone controller (the widest
  ground areas for attrition). Each carries its own human and animal kit, drawn from the
  shared ability primitives but set apart by its targeting mix, tuning, and resource
  economy. A practice match fields all three (see the squad entry above); a hosted or
  joined match equips the Lion for both sides until multi-hero play reaches the wire.
- Ability controls: the player now casts the hero's abilities with the **1–4** keys,
  aimed at the mouse cursor, and shifts the hero between its human and animal form to
  wield each form's distinct set. The hero shows its current form (a ring around it)
  and its resource pool (a bar under the health bar) as it casts and transforms.
  Abilities are cast in a single-machine or hosted match; a joined client moves but
  does not yet cast (networked casting follows with the protocol that carries it).
- A data-driven hero ability layer for Theria's shapeshifters. Every hero carries
  two kits — a human form and an animal form — and transforms between them, each
  form metering its own resource pool with separate cooldowns that keep running
  across the swap. Abilities are defined as catalog data, not code: each is
  skillshot-aimed, ground-targeted, unit-locked, or self-cast, and resolves inside
  the authoritative simulation alongside the existing combat, so it stays
  deterministic and replayable. This release includes one proving kit that
  exercises the whole schema; the distinct heroes and the controls that cast them
  are built against it next.
- An in-game connect screen: a windowed launch now opens a menu to start a
  single-machine practice match, host a listen-server, or join one by address,
  instead of requiring command-line flags. The flags still work and skip the menu
  (`-- --host`, `-- --join <address>`, `-- --local`); a headless launch with no flag
  still defaults to a single-machine match, so the automated tooling is unchanged.
- Networked multiplayer over a listen-server: one player hosts the authoritative
  match and a second joins over the network, each driving their own hero while the
  host simulates and broadcasts the world every tick. Peers exchange a protocol
  version on connect and a mismatch is refused; an empty player slot is filled by
  a bot. Launch with `-- --host` or `-- --join <address>`; the default remains a
  single-machine game. This activates the netcode protocol version as a
  compatibility axis.
- Client-side prediction and reconciliation: a joined player's hero now responds
  to their input immediately rather than after a network round trip. The client
  predicts its own hero locally and, on every authoritative snapshot, rolls back
  to the server's truth and replays the inputs the server has not yet applied — so
  the prediction stays exactly on the authoritative path and self-corrects. Remote
  units are still drawn straight from the snapshot. The netcode protocol version
  advances to 2 (inputs now carry a sequence number and snapshots an acknowledgement).
- Remote-entity interpolation: enemy heroes, creeps, and structures are now
  rendered a short delay in the past, interpolated between buffered snapshots, so
  they move smoothly instead of stuttering or snapping when packets arrive with
  jitter or are dropped. The delay applies only to remote units; the joined
  player's own hero is still predicted to the present and feels no added latency.
- Adaptive interpolation delay: the delay remote units are rendered behind now
  tracks the connection's measured jitter instead of a fixed value — a clean
  connection pays little added latency, while a jittery one automatically buffers
  enough to ride out its worst gap, within a bounded range.
- Simulated link conditions for playtesting: a joining player can add `--netsim
  <latency>,<jitter>,<loss>` to shape their incoming snapshot stream as if it had
  crossed a worse network — delaying, jittering, and dropping snapshots — so the
  remote-unit smoothing and its adaptive delay can be seen working on a local
  machine or LAN, which otherwise deliver almost perfectly. A client-side debug aid
  only: it changes nothing the host sends and no wire bytes, so the protocol version
  is unaffected.
- Combat heroes: the player's hero and the bot now auto-attack the nearest enemy
  in range, so a hero can clear creep waves, pressure towers, duel the enemy hero,
  and push a lane toward the nexus. Heroes spawn at their base fountain.
- Lane creeps: each team spawns periodic creep waves that march their lane
  toward the enemy base, stop to fight whatever they meet, siege towers, and can
  drive an undefended nexus to destruction — making the win condition reachable
  in live play.
- Towers and a destructible nexus: structures auto-attack the nearest enemy in
  range, units and structures carry health and can be destroyed, and a match
  ends when a team's nexus falls.
- Client rendering of the full arena — playing field, bounds, the two lane
  corridors, the neutral jungle camps, each team's base, and the live units with
  health bars.
- Lane and jungle geometry on the arena map: two mirrored lane corridors linking
  the bases and a set of neutral jungle camps in the central band.
- Server-authoritative, deterministic, fixed-60 Hz simulation core driving one
  player hero and one bot on the 3v3 arena (the walking skeleton).
- Headless test suite covering the simulation's determinism and movement.
- Continuous integration running the linter and the test suite on every push
  and pull request.

---

[← Prev: README](README.md) · [Next: Credits →](CREDITS.md)
