<div align="center">

<img src="icon.svg" alt="Ashmere" width="72">

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

### Added

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
