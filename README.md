<div align="center">

<img src="icon.svg" alt="Theria" width="96">

<h1>Theria</h1>

<h3>Shapeshifter tribes clash over the savanna and the jungle — fight as both human and beast</h3>

<p>
  <a href="https://github.com/ajhahnde/Theria/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/ajhahnde/Theria/ci.yml?branch=main&style=flat-square&label=ci" alt="CI"></a>
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

Theria is a top-down multiplayer online battle arena built in Godot 4, set in a
world of shapeshifters — tribes whose members fight in both a human and an animal
form. Two teams of three, each drawn from a shapeshifter people, contest savanna
lanes and an equatorial jungle to break each other's nexus.

The first milestone is a **walking skeleton**: one player-controlled hero and
one bot moving on the 3v3 arena under a server-authoritative, fixed-timestep
simulation. With that authority model proven, networked play over a
listen-server now runs on top of it; heroes, abilities, and the art direction
come next.

## Architecture

The simulation is the single source of truth. `SimCore` is a deterministic,
side-effect-free step function that advances the world by a fixed 1/60 s tick
from input alone — no rendering, no engine input, no global state. The same
core is driven by:

- the local client (`src/client`), which samples the keyboard and draws the
  resulting state;
- the bot (`src/bot`), which derives its command from the world state;
- the headless tests (`test/`), which replay scripted input and assert the
  outcome;
- the networked drivers (`src/net`), where a host simulates and broadcasts the
  world and a client sends its input up and renders the snapshots it receives.

Because authority lives entirely in the simulation, networked play is just
another driver — a listen-server — added without rewriting gameplay. The host is
the sole authority. A client never owns authority, but it predicts its own hero
locally so input feels instant, reconciling against every snapshot: it rolls back
to the server's state and replays the inputs the server has not yet applied, using
the same movement code the server runs. Remote units — the enemy hero, creeps, and
structures — are rendered a short delay in the past, interpolated between buffered
snapshots, so they move smoothly through network jitter and dropped packets; that
delay adapts to the connection's measured jitter rather than being fixed.

## Layout

| Path           | Contents                                              |
| :------------- | :---------------------------------------------------- |
| `src/sim`    | The authoritative simulation core and its data types. |
| `src/bot`    | Bot input derived from the world state.               |
| `src/net`    | Listen-server transport, the client/server wire protocol, remote-entity interpolation, and the playtest link-condition simulator. |
| `src/client` | The connect menu, local input sampling, and rendering. |
| `test/unit`  | Headless tests of the simulation and the wire protocol. |
| `scenes`     | Godot scenes.                                         |

## Running

Open the project in Godot 4.6 and press Play, or from the command line:

```sh
godot --path .
```

A connect screen opens: choose **Practice** for a single-machine match, **Host** to
start a listen-server, or type an address and **Join** one. Move the hero with
**WASD** or the **arrow keys**; the bot walks toward it.

### Multiplayer

The connect screen's **Host** and **Join** cover multiplayer. The same roles can be
selected on the command line, which skips the menu — this is how a headless run picks
a role, since a menu cannot be driven without a display:

```sh
godot --path . -- --host             # host the match (you are team 0)
godot --path . -- --join 127.0.0.1   # join a host at an address (you are team 1)
godot --path . -- --local            # a single-machine match, no menu
```

The host is authoritative and fills any empty player slot with a bot. The joining
player's hero is predicted locally, so it responds without waiting on the host.

A local machine and a clean LAN deliver snapshots almost perfectly, so the smoothing
that exists to ride out a bad connection is never really exercised. To see it work, a
joining player can simulate a worse link on their incoming snapshot stream:

```sh
# join with 150 ms latency, 50 ms of jitter, and 10% packet loss
godot --path . -- --join 127.0.0.1 --netsim 150,50,0.1
```

This shapes only what the client receives — it changes nothing the host sends and no
wire bytes — and makes the remote units visibly buffer further behind and the
interpolation cover the dropped snapshots. It is a debug aid, not a gameplay option.

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
