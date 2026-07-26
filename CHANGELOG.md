# SwingTime — Changelog

## 1.1.0

- Added centered **on-screen text warnings**: **OUT OF RANGE** and **NOT ATTACKING**, shown
  while you have a live attackable target in combat. Both stack vertically when they apply at
  once, with OUT OF RANGE on top.
- Each message is configured **independently** on the new **Warnings** tab — enable/disable,
  custom message text, LibSharedMedia font, font size, outline, and color.
- The warning block is **draggable**: `/st unlock` reveals it alongside the bars (and doubles as
  a live style preview, since both lines are forced visible while unlocked).
- A **Range check** option (Automatic / Melee / Ranged) overrides the melee-vs-ranged detection
  if the automatic choice guesses wrong for your class or weapon setup.
- New `CombatState.lua` derives attack and range state at 10 Hz using the action-bar range APIs,
  with layered fallbacks and debouncing so the text can't flicker at the range boundary. The
  swing-timing engine is untouched.

## 1.0.1

- Added mechanic-accurate **timing markers**, shown only for the relevant class:
  - **Hunter** — a Multi-Shot clip line on the ranged bar (at the auto-shot + multi-shot
    cast point; cast Multi-Shot to its left to avoid clipping your auto shot).
  - **Paladin** — a seal-twist guide on the main-hand bar: a red **danger zone** band with a
    red tick at its start, plus a **twist tick** at the 0.4s twisting window.
- Marker positions are fixed by the mechanic; you can customize the tick **width, texture, and
  color** and toggle it on/off in the config window's Bars tab. The seal-twist tick defaults to green.
- Added the SwingTime logo to the config window header.

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
