# Notices

This project ships under two distinct licenses by file type:

## Source code — MIT

All `.swift`, `.json` (build / config), `.md`, `.yml`, `.sh`, `.py`, and
other source files outside `Sources/MyPet/Resources/sprites/` are released
under the MIT License. See [`LICENSE`](LICENSE).

You may fork, modify, and redistribute the source code, including for
commercial purposes, as long as the copyright notice and MIT license
text are preserved.

## Artwork & audio — All Rights Reserved

Files in `Sources/MyPet/Resources/sprites/` (cat sprites in `.apng` /
`.png` / `.svg`, the Kling-derived audio in `.m4a`, and any future skin
packs) are **copyrighted artwork**, not open-source.

See [`Sources/MyPet/Resources/sprites/LICENSE`](Sources/MyPet/Resources/sprites/LICENSE)
for the full terms.

Short version: personal use of mypet ✅. Re-using the cat character in
another product, training AI on it, or commercial redistribution ❌.

## Third-party

This project includes no third-party assets at this time. Architectural
ideas (APNG playback layer, state machine progression, eye-tracking
concept) were borrowed in concept from `clawd-on-desk`
(<https://github.com/rullerzhou-afk/clawd-on-desk>, AGPL-3.0); no code
or artwork was copied — implementations are clean-room Swift.
