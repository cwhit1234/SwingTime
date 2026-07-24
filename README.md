# SwingTime

Clean, customizable weapon swing timer bars for World of Warcraft **Classic Era**.

SwingTime shows crisp, modern bars for your main-hand, off-hand, ranged, and your target's swing. Style and place them however you like.

## Features

- **Four bars** — main-hand, off-hand, ranged (hunter Auto Shot + wands), and your target.
- **Fully customizable** — any bar texture and font from LibSharedMedia, custom colors, and
  per-bar sizing.
- **Place it your way** — drag bars anywhere and lock them down.
- **Profiles** — save layouts and reuse them across characters.
- **Accurate** — handles haste, parry-haste, Windfury/extra attacks, weapon swaps, and the
  hunter Auto Shot cast window.
- **Lightweight & standalone** — no other addons required.

## Install

Copy the `SwingTime` folder into `World of Warcraft\_classic_era_\Interface\AddOns\`, then
`/reload` or restart the game. (Or install from CurseForge.)

## Usage

| Command | Action |
|---|---|
| `/st` | Open the config window |
| `/st unlock` *(or `/st move`)* | Unlock bars for dragging |
| `/st lock` | Lock bars in place |
| `/st toggle` | Toggle the lock |

## License

MIT — see [`LICENSE`](LICENSE). © 2026 Raizen.

---

### Development

Releases are packaged by the [BigWigs packager](https://github.com/BigWigsMods/packager)
via GitHub Actions on each git tag; embedded libraries (LibStub, CallbackHandler-1.0,
LibSharedMedia-3.0) are pulled in as `.pkgmeta` externals rather than committed. To run
from source, either build with the packager or drop those libraries into `libs/`.
