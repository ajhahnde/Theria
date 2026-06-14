<div align="center">

<img src="icon.svg" alt="Ashmere" width="96">

<h1>Ashmere</h1>

<h3>Fabled creatures clash over the ruins of Ashmere — a city lost to ash and water</h3>

<p>
  <a href="https://github.com/ajhahnde/Ashmere/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/ajhahnde/Ashmere/ci.yml?branch=main&style=flat-square&label=ci" alt="CI"></a>
  <img src="https://img.shields.io/badge/version-v0.1.0-f97316?style=flat-square" alt="Version">
  <img src="https://img.shields.io/badge/status-pre--alpha-f97316?style=flat-square" alt="Status">
  <img src="https://img.shields.io/badge/engine-Godot%204.6-lightgrey?style=flat-square" alt="Godot 4.6">
  <img src="https://img.shields.io/badge/license-Apache--2.0-lightgrey?style=flat-square" alt="License">
</p>

<p>
  <b>README</b> ·
  <a href="CHANGELOG.md"><b>Changelog</b></a> ·
  <a href="LICENSE"><b>License</b></a>
</p>

</div>

---

## About

Ashmere is a 2.5D top-down, pixel-art multiplayer online battle arena built in
Godot 4. Fabled creatures — *Fabelwesen* — fight over the drowned ruins of
Ashmere, a fabled city lost to ash and water. Two teams of three contest lanes
and a jungle to break each other's nexus.

The first milestone is a **walking skeleton**: one player-controlled hero and
one bot moving on the 3v3 arena under a server-authoritative, fixed-timestep
simulation. Online play, items, and the meta layer come later — the skeleton
exists to prove the authority model first.

## Architecture

The simulation is the single source of truth. `SimCore` is a deterministic,
side-effect-free step function that advances the world by a fixed 1/60 s tick
from input alone — no rendering, no engine input, no global state. The same
core is driven by:

- the local client (`src/client`), which samples the keyboard and draws the
  resulting state;
- the bot (`src/bot`), which derives its command from the world state;
- the headless tests (`test/`), which replay scripted input and assert the
  outcome.

Because authority lives entirely in the simulation, networked play can be added
later as another driver without rewriting gameplay.

## Layout

| Path | Contents |
| :--- | :--- |
| `src/sim` | The authoritative simulation core and its data types. |
| `src/bot` | Bot input derived from the world state. |
| `src/client` | Local input sampling and rendering. |
| `test/unit` | Headless tests of the simulation. |
| `scenes` | Godot scenes. |

## Running

Open the project in Godot 4.6 and press Play, or from the command line:

```sh
godot --path .
```

Move the hero with **WASD** or the **arrow keys**; the bot walks toward it.

## Testing

Tests run headless with [GUT](https://github.com/bitwes/Gut):

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit
```

Linting uses the [GDScript toolkit](https://github.com/Scony/godot-gdscript-toolkit):

```sh
gdlint src test
```

Both run in continuous integration on every push and pull request.

## License

Apache License 2.0 — see [`LICENSE`](LICENSE).

---

[Next: Changelog →](CHANGELOG.md)
