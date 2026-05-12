# mypet 🐢

A token-eating desktop turtle for Claude Code users.

The turtle floats in the bottom-right of your screen, fast asleep by default —
zero CPU, zero network, zero API spend. Hover over it for one second to feed it
a token: it wakes up, chomps through one `claude -p` call, and a speech bubble
pops with one Claude Code tip or a piece of tech news. Then it goes back to sleep.

> macOS 13+ • SwiftUI + AppKit • MIT

## How feeding works

1. Hover your mouse over the turtle for ~1 second (a ring of dots fills up).
2. The turtle plays a chomp animation.
3. `mypet` runs `claude -p "<prompt>" --output-format text` — it spends *your*
   Claude Code subscription quota, no separate Anthropic API key required.
4. The reply appears in a speech bubble above the turtle.
5. The turtle purrs, then drifts back to idle.

Cooldown: one feed per minute. No feeds for 24h → the turtle gets hungry
(visual only, still zero background work).

## States

`idle` (gentle sway) · `eating` (chomp + ⚡ particles) · `excited` (jump + ✦ sparkles) ·
`purring` (slow breathe) · `sleepy` (head tilt + zZz) · `hungry` (sad sway)

## Requirements

- macOS 13 or later
- Claude Code CLI on your PATH (`claude --version` works)

## Build

```bash
swift build
swift run mypet
```

First launch shows a short onboarding wizard (detects `claude`, asks about
launch-at-login, does a demo feed).

## Tests

```bash
swift test
```

78 tests covering the `claude` subprocess wrapper (binary discovery, timeout,
cancellation, output normalization, error classification, concurrency guard,
FD-leak check), the feed log (corruption recovery, cooldown, hungry detection),
the pet state machine, the feed coordinator, and the window configuration.

## Project layout

```
Sources/MyPet/
  App/        MyPetApp, AppDelegate, MenubarController
  Window/     PetWindow (borderless transparent, click-through)
  Scene/      TurtleView (SF Symbol turtle, hover-to-feed, multi-state motion)
  UI/         OnboardingView, TipBubble, FeedButton
  Domain/     ClaudeSubprocess, FeedCoordinator, PetState, LoginItem
  Storage/    FeedLog (JSON in Application Support)
scripts/      gen-sprite.ts, gen-all-sprites.ts (optional AI sprite pipeline)
```

## Why a turtle?

The original plan was a cat, but the `cat.fill` SF Symbol only exists on
macOS 14+. `tortoise.fill` is available on macOS 13, equally cute, and the
chubby little shell renders crisply at any size. (If you're on macOS 14+ and
want a cat, it's a one-line change in `TurtleView.swift`.)
