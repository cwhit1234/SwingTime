# SwingTime

Clean, highly-customizable **weapon swing timer bars** for World of Warcraft **Classic Era**.

SwingTime shows how long until your next main-hand, off-hand, ranged (auto-shot / wand), and
target swing, driven by faithful swing-timer math and wrapped in a modern, standalone
configuration window with a live, true-to-size preview. Pick any bar texture and font from
**LibSharedMedia**, recolor every element, size and place each bar independently, and share
setups across characters with profiles.

---

## Features

### Swing timers
- **Four bars:** main-hand, off-hand, ranged (hunter auto-shot + wand `Shoot`), and your current **target**.
- An independent swing-timing engine (`SwingCore.lua`) written from the documented Blizzard APIs
  (`UnitAttackSpeed`, `UnitRangedDamage`, `COMBAT_LOG_EVENT_UNFILTERED`). It uses an absolute-expiry
  model and reacts to the `UNIT_ATTACK_SPEED` / `UNIT_RANGEDDAMAGE` events, so there's no per-frame
  timing loop. It handles:
  - Mid-swing **haste rescaling** (buffs/procs adjust the in-progress swing proportionally).
  - **Windfury / extra-attack** suppression (an extra attack doesn't falsely reset the main-hand).
  - **Parry-haste** — both when you parry an incoming swing (your next swing speeds up) and when your swing is parried (the target's speeds up).
  - **Weapon swaps** reset the affected bar.
  - Class **on-next-swing** resets: Slam, Heroic Strike, Cleave (Warrior), Maul (Druid), Raptor Strike (Hunter), matched by spell ID.
  - Ranged: auto-shot cast window, movement/casting resets, Feign Death handling, and haste applied at the next shot.
- Ranged weapon base speed resolved via tooltip scan (no giant static item table to maintain).

### Appearance & customization
- **LibSharedMedia** bar textures and fonts — anything other addons register shows up automatically.
- **Per-bar** independent width, height, and fill color.
- **Global** styling shared by all bars: bar texture, font, font size & outline, background / border / text colors.
- Optional label text and timer countdown text; separate **in-combat / out-of-combat opacity**.
- Independent, **draggable** bars with a highlighted lock/unlock mover overlay.
- **Live, true-to-size preview** in the config window that mirrors the selected bar exactly — every change applies instantly, no reload.

### Config UI
- A **standalone, draggable window** (not crammed into the Blizzard settings pane) — like Platynator / Cell / EllesmereUI.
- Two tabs (**Bars**, **Profiles**) with labeled, divided sections so global vs per-bar settings are unambiguous.
- Custom flat widgets: checkboxes, sliders with **−/+ steppers** for exact values, **searchable** dropdowns for long texture/font lists, and color swatches.
- **Unlock/Lock** button in the window's title bar.

### Profiles & storage
- **Profiles** — account-wide storage with per-character selection; create / copy / delete / reset. Each character remembers which profile it uses.
- Platynator-style hand-rolled storage — **no Ace3 / AceDB**; the only embedded library is LibSharedMedia (plus its LibStub / CallbackHandler dependencies).

---

## Install

Copy the `SwingTime` folder into:

```
World of Warcraft\_classic_era_\Interface\AddOns\SwingTime
```

Then `/reload` or restart the game.

---

## Usage

Slash commands (`/st` or `/swingtime`):

| Command | Action |
|---|---|
| `/st` | Toggle the SwingTime config window |
| `/st config` | Open the config window |
| `/st unlock` (or `/st move`) | Unlock bars so you can drag them |
| `/st lock` | Lock bars back in place |
| `/st toggle` | Flip the bar lock state |

The config is a **standalone window** — drag it by its title bar, press **Esc** to close.
The game's **Settings → AddOns → SwingTime** page also has an **Open configuration** button
that brings the window up.

---

## Configuration

### Bars tab

Organized into three labeled sections:

- **Enabled Bars** — turn each bar (Main Hand, Off Hand, Ranged, Target) on or off.
  Off-hand shows only when dual-wielding; Ranged shows only with a ranged weapon; Target shows only with an attackable target.
- **Selected Bar** — pick a bar in the **Configure bar** dropdown, then set that bar's **Width**, **Height**, and **fill Color** independently. Use the **−/+** buttons on the sliders for exact values.
- **Global** (applies to every bar):
  - **Bar texture** and **Font** (both searchable — type to filter long LibSharedMedia lists), **Font size**, **Font outline**.
  - **Background**, **Border**, and **Text** colors.
  - **Show label text** / **Show timer text** toggles.
  - **In-combat** and **Out-of-combat** opacity.

**Unlock/Lock** is in the window title bar. While unlocked, each bar shows a labeled mover box you can drag; positions are saved per bar, per profile.

The **live preview** at the bottom of the window renders the currently selected bar at its real size, with the chosen texture, font, and colors.

### Profiles tab

- **Active profile** dropdown — switch profiles.
- **New profile name** box with **New** (blank) and **Copy** (clone current) buttons.
- **Delete** and **Reset** the active profile.

---

## Notes

- The `## Interface:` version in `SwingTime.toc` is set to `11509` (Classic Era 1.15.9). If a game
  patch bumps this and the addon shows as "out of date", either enable **Load out of date AddOns**
  on the character-select AddOns screen, or update the number to match `/dump select(4, GetBuildInfo())`.
- **No binary assets are shipped** — a flat bar uses a built-in game texture (`WHITE8X8`) and the
  default font is the built-in "Friz Quadrata TT". Additional textures/fonts come from other
  LibSharedMedia addons you have installed.

---

## Architecture

| File | Responsibility |
|------|----------------|
| `Config.lua` | Account-wide storage + profiles (Platynator-style, no AceDB); defaults, dotted-path get/set, change listeners |
| `Media.lua` | LibSharedMedia registration & fetch helpers; live refresh when new media registers |
| `RangedDB.lua` | Resolves the ranged weapon's base (unhasted) speed via tooltip scan |
| `SwingCore.lua` | Independent swing-timing engine (expiry model; player main/off/ranged + target) |
| `Bars.lua` | StatusBar bar widgets, styling, and lock/unlock mover overlay |
| `Core.lua` | Bootstrap: init, combat state (bar opacity), bar animation, slash commands |
| `Options/Widgets.lua` | Hand-built config widgets: checkbox, slider (with −/+ steppers), searchable dropdown, color swatch |
| `Options/Panel.lua` | The standalone config window: title bar, tabs, two-column sectioned layout, live preview |
| `Locales/enUS.lua` | UI strings |

Load order and libraries are declared in `SwingTime.toc`; libraries are embedded via `embeds.xml`.

Embedded libraries (in `libs/`): **LibStub**, **CallbackHandler-1.0**, **LibSharedMedia-3.0**.

The swing-timing engine is an independent implementation derived from the public WoW API
(`UnitAttackSpeed`, `UnitRangedDamage`, and the combat log) — the timing math follows the game's
documented mechanics, not any other addon's source.

---

## License

SwingTime is released under the **MIT License** — see [`LICENSE`](LICENSE). © 2026 Raizen.

---

## Verifying changes

There's no in-repo test harness (the addon only runs inside WoW). Lua files can be syntax-checked
outside the game with any Lua 5.1 parser. For real verification, load it in Classic Era and, on a
target dummy: attack to confirm main/off-hand resets, check haste rescaling, dual-wield, hunter
auto-shot and wand, a target's swing, then exercise the config — live texture/color/font changes,
per-bar sizing, drag-and-lock, searchable dropdowns, the −/+ steppers, and profile switching.
