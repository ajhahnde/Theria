<div align="center">

<img src="icon.svg" alt="Theria" width="72">

<h1>Changelog</h1>

<p><i>Every notable change, newest first.</i></p>

<p>
  <a href="README.md"><b>README</b></a> ·
  <b>Changelog</b> ·
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

### Changed

- Snapshots are now packed into a compact binary wire format — a short header plus one
  fixed byte record per entity, with floats narrowed to 32 bits — instead of a Variant
  container. A full opening creep wave drops from roughly 3 KB to under 1 KB, so the
  whole world now fits in a single unreliable datagram rather than fragmenting above the
  transport's packet-size limit. Rendering is unchanged; positions round-trip exactly.
  The netcode protocol version advances to 3 (the snapshot wire shape changed).

### Added

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
  can out-trade them — without dulling their judgement: a bot at any level still positions,
  kites, shifts form, and heals exactly as sharply. Sim-side and menu only; the netcode
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

[← Prev: README](README.md)
