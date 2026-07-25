# SwingTime — Changelog

## 1.0.1

- Added a **timing marker** (a vertical line) on the bars:
  - **Hunter** — a Multi-Shot clip marker on the ranged bar.
  - **Paladin** — a seal-twist window marker on the main-hand bar.
- The marker position is fixed by the mechanic; you can customize its **width, texture, and
  color** (and toggle it on/off). Only shows for the relevant class. Configure it in the
  config window's Bars tab.

## 1.0.0

Initial release.

- Weapon swing timer bars for **main-hand, off-hand, ranged, and target**.
- Independent swing-timing engine (`SwingCore.lua`): absolute-expiry model, event-driven
  haste via `UNIT_ATTACK_SPEED` / `UNIT_RANGEDDAMAGE`, no per-frame timing loop.
- Edge cases handled: parry-haste (−40% floored at 20%), extra attacks (Windfury, exact count),
  weapon swaps, class on-swing resets (Heroic Strike / Cleave / Maul / Raptor Strike),
  Slam pause/resume, druid form-shift, and the ranged Auto Shot cast window (hunter only).
- Standalone, draggable config window: per-bar size and color, LibSharedMedia textures & fonts,
  background/border/text colors, opacity, movable/lockable bars, searchable dropdowns,
  ±1 slider steppers, a true-to-size live preview, and profiles.
