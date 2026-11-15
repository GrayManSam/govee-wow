# govee-wow

A live light show for **World of Warcraft: Forever** on Govee lights, driven over your local
network (no cloud, no account, no Bluetooth). The room turns into one canvas — floor lamp,
ceiling light, floor lamp — choreographed like an esports arena or a 4DX theater, reacting to
what happens in the game about 0.1 s after it happens.

- **Programs follow the game:** exploring (light "drones" glide through the room), resting in
  a city, riding (streaks race up the lamps), combat at 128 BPM (the lamps become VU meters of
  your action), boss fights (lighthouse sweeps), death (blackout + a slow flatline pulse), and a
  heartbeat that speeds up as your health drops.
- **Cues fire on events:** each cast is a shockwave falling from the ceiling, a big cooldown is a
  riser that bursts, a kill is a firework, damage taken surges up from the floor, heals shimmer,
  level-ups get a 5-second finale.
- **Styles by time of day** (all configurable):

  | hours | style | look |
  |---|---|---|
  | 07:00–19:00 | `daylight` | vivid greens matched to the game's terrain (see below), max 60% |
  | 20:00–23:00 | `standard` | reds, hot pinks, purples, deep blues, flashes allowed, max 50% |
  | 19:00–20:00 | `party` | the full club show, max 55% |
  | 23:00–07:00 | `afterdark` | 2% brightness, warm ember colors only, zero blue, no flashes |

  Each style has a hard brightness cap (`max_level` in the config, `govee-wow max STYLE N`):
  nothing the show sends - flashes and cues included - can go above it, and cap changes
  (including the hourly style switch) glide over a few seconds instead of jumping.

  Also available: `comfort` (no strobing at all; brightness change speed is hard-limited, max 45%).

### Daylight: the room becomes the game world

Like a Govee TV backlight (or Hyperion/Ambilight), the picture is split into **edge zones**,
and each zone drives the light in the same position in your room:

```
        top band of the screen  ->  ceiling light (sky / canopy overhead)
left edge (bottom -> top)       ->  left floor lamp  (ground rising into foliage)
right edge (bottom -> top)      ->  right floor lamp
```

Zones skip black bars, black screens and the bottom of the screen where the action bars live,
and are smoothed over ~0.35 s. Every color is pulled into the green family (brown earth turns
yellow-green, grass stays green, water and sky become teal), and dark terrain is still
shown at full LED strength. On top of that: wind waves crossing the room left to right, sun
dapples drifting over the ceiling, fireflies, and a sun arc over the day (dewy teal morning ->
bright lime noon -> golden 6 pm).

### Safety

Every style is checked against **WCAG 2.3.1** (no more than 3 flashes in any second, red
flashes counted separately). `govee-wow check` prints the analysis for every style.

## How it gets game data

1. **CouchLights addon (real time, recommended).** It draws a tiny 8-pixel color strip in the
   top-left corner of the screen. govee-wow reads it from a screen capture (GNOME
   Mutter ScreenCast + PipeWire), so it knows combat / boss / dead / mounted / resting / health
   and the last event within ~0.1 s. The same capture provides the picture for the colors.
   The strip also carries one non-light event: CouchUI's guild **Recruit** (cast, detail 7),
   on which govee-wow types `/ginvite` into the game (WoW Forever only accepts typed guild
   invites; see [wow-couch](https://github.com/GrayManSam/wow-couch)).
2. **Combat log (fallback).** Without the strip, it tails `Logs/WoWCombatLog*.txt` (run
   `/combatlog` in game). The log is written in bursts 1–3 s late, so cues are replayed through
   a jitter buffer, and cues that arrive too late become "energy" instead of flashes.

## Hardware

Tested with **2 × Govee H6076** floor lamps (per-segment color via `ptReal`) and a **Govee
H1370** ceiling light (Razer/DreamView stream). Other Govee LAN-API models that speak one of
those two protocols can be tried by adding their SKU to `STREAM_SKUS` or `SEGMENT_SKUS` in
`bin/govee-wow` (PRs with tested models welcome). With no `room` set, lights are laid out
lamp – ceiling – lamp.

## Requirements

- Linux with GNOME (Wayland or X11) and PipeWire; Python 3.11+ (standard library only), plus
  PyGObject and GStreamer for the screen capture: on Fedora
  `sudo dnf install python3-gobject gstreamer1-plugins-base gstreamer1-plugins-good pipewire-gstreamer`
- In the Govee Home app, turn on **LAN Control** for each light.
- WoW: Forever (tested via Battle.net under GE-Proton / umu). The game folder defaults to
  `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_`; set `WOW_DIR` if
  yours differs.

## Install

```sh
git clone https://github.com/GrayManSam/govee-wow
cd govee-wow
WOW_DIR="/path/to/World of Warcraft/_forever_" ./install.sh    # WOW_DIR optional
govee-wow when always        # or "couch" if you also use wow-couch (TV-only)
govee-wow demo 30 daylight   # 30 s demo on your real lights
```

Screen capture uses GNOME's own `org.gnome.Mutter.ScreenCast` API on the TV (the monitor
whose EDID is at least 100 cm wide or whose name contains "TV", else the primary; set
`capture_monitor` to a connector such as `DP-3` to force one), so there is no "share your
screen" dialog. It starts once the WoW window has been up `capture_delay` seconds (5), runs
at `capture_fps` (15: GNOME copies every captured 4K frame out of the GPU, so keep it low)
and ends with the game. If that API is unavailable it falls back to the desktop portal: one
dialog, then a restore token in `~/.config/govee-wow/screencast-token` (the service) or
`screencast-token-manual` (runs from a terminal, which the portal sees as another app).
Local only, never commit them. `"capture": "portal"` or `"mutter"` forces a backend.

The systemd unit runs the service at nice 10, idle I/O priority and a low CPU weight.

## Commands

```
govee-wow                     status
govee-wow demo [secs] [style] the whole show on the real lights, then restore
govee-wow preview [s] [style] draws the show in the terminal (lights untouched)
govee-wow watch               live mirror of what the lights are doing
govee-wow check               flash / photosensitivity analysis of every style
govee-wow style NAME          comfort | standard | party | afterdark | daylight
govee-wow level N             master brightness 10-100 (on top of the style caps)
govee-wow max [STYLE N]       show / set a style's brightness cap in %
govee-wow afterdark level N   after-dark brightness 1-10 %
govee-wow when couch|always|never
govee-wow-test [--live]       self-test (schedule, safety, strip decoding, log replay, addons)
```

Tuning lives in `~/.config/govee-wow/config.json` — see `config.example.json` for every key
(schedule, per-program brightness and BPM, `terrain_tint`, `room` order, flash limits...). If
your lamps come out swapped, set `"room": ["<left lamp IP>", "<ceiling IP>", "<right lamp IP>"]`.

## Related

[wow-couch](https://github.com/GrayManSam/wow-couch): TV + Xbox controller couch mode for WoW
on Linux. govee-wow's `when couch` setting uses it to only light up when you play on the TV.

## License

MIT. World of Warcraft is a trademark of Blizzard Entertainment; Govee is a trademark of
Shenzhen Intellirocks Tech. This project is not affiliated with or endorsed by either.
