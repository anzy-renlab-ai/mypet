# Changelog

All notable changes to mypet. Format: [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Added
- **Six rotating tip themes** (`claudeTip` 30% / `promptIdea` 20% / `techNews` 18% / `til` 14% / `devJoke` 10% / `dayouShi` 8%) — every feed surprises you with a different vibe.
- **Theme badge on the tip bubble** (☕ tip / 💡 prompt / 📰 news / 🤓 TIL / 😆 joke / 🥟 打油诗) — see what category the cat just served.
- **Click-to-copy on the tip bubble** — click any bubble to put the tip on your clipboard with a "✓ 已复制" flash.
- **Recent tips submenu** in the menubar dropdown — last 10 successful tips with timestamps; click to copy.
- **PNG sprite loader** in `CuteCatFace` — drop `cat-<state>.png` into `Sources/MyPet/Resources/sprites/` and the cat upgrades from emoji automatically (no code change).
- **MIT LICENSE** file (README had claimed it but the file was missing).
- **GitHub Actions CI** running `swift build` + `swift test` on macOS 13.
- README badges (CI / macOS / SwiftUI / License / Tests).
- Animated feed-cycle demo GIF in README.

### Changed
- **Turtle → cat.** SF Symbol `tortoise.fill` replaced with Apple cat emoji on a soft warm halo. State-aware: 🐱 idle · 😺 eating · 😸 excited · 😻 purring · 😽 sleepy · 😿 hungry.
- **Hover progress** dot row → slim gradient pill (more legible at small sizes).
- Menubar icon: `tortoise.fill` → `pawprint.fill` (since `cat.fill` requires macOS 14+).
- Eating-state particles now drift above the cat instead of across the face (fish 🐟 + sparkle ✨ no longer occlude the expression).
- All UI copy: 乌龟 → 小猫 ; first-feed greeting and friendly error messages updated.

### Fixed
- Cooldown rejection now surfaces a `"还在消化呢..."` tip instead of silently swallowing the feed attempt.

### Internal
- `TurtleView.swift`: 834 LOC → 280 LOC after dropping the hand-drawn shapes.
- `FeedCoordinator.TipTheme` enum + `nextTheme(rng:)` weighted picker — RNG injectable for tests.
- `FeedLog.recentTips(limit:)` — newest-first successful entries.

### Tests
- 84 tests passing.
- New: theme distribution boundaries, theme propagation to feeder, all-cases validity.
