# mypet 🐱

> A fluffy desktop cat that eats your Claude Code tokens.
>
> Hover for one second. The cat chomps one `claude -p` call and bubbles back
> a Claude Code tip or tech-news headline. Then goes back to sleep.
>
> macOS 13+ · SwiftUI · zero deps · MIT

<p align="center">
  <img src="docs/screenshots/hero.png" width="420" alt="fluffy orange tabby mypet, idle, in the bottom-right of the screen">
</p>

## Why

You pay for Claude Code anyway. The little cat spends *your* subscription
quota — no separate Anthropic API key, no server, no telemetry. When you're
not feeding it, it costs **zero CPU** and **zero network**. When you do feed
it, you get one cute interruption and one tiny morsel of useful information.

It's a screensaver that pays rent.

## How it works

```
 hover 1s   ─►  chomp animation  ─►  claude -p "<prompt>"  ─►  💬 tip bubble
                                                                    │
   ◄─ purr ──────────── 8s ──────── click to dismiss / auto-fade ◄──┘
```

1. Mouse over the cat for ~1 second (a small dot ring fills up).
2. Cat plays a chomp animation, ears twitch, sparkles fly.
3. `mypet` shells out to your local `claude` CLI — same login, same quota.
4. The reply appears in a tiny speech bubble above the cat.
5. Cat purrs, then drifts back to idle.

Cooldown: one feed per minute (the cat tells you when it's still digesting).
No interaction for 24h → the cat gets hungry (a sad face + a tear). All
visual — still zero background work.

## States

| State | When | Looks like |
|---|---|---|
| `idle` | resting | gentle sway, slow blink |
| `eating` | feeding now | happy `^ ^` eyes, mouth open, sparkles |
| `excited` | feed succeeded | jump, stars overhead |
| `purring` | tip showing | heart eyes, ♡ overhead |
| `sleepy` | 2h idle | closed eyes, head tilt, `zZz` |
| `hungry` | 24h no feed / error | frown, single tear, ear droop |

## Requirements

- macOS 13 or later
- [Claude Code CLI](https://docs.anthropic.com/claude-code) on your `PATH`
  (`claude --version` works)

## Install + run

```bash
git clone https://github.com/<you>/mypet
cd mypet
swift run mypet
```

First launch shows a tiny onboarding wizard (detects `claude`, asks about
launch-at-login, then plays a demo feed).

The cat lives in the bottom-right of your primary display. Click-drag it
anywhere. The 🐾 menu-bar icon gives you `Feed now`, `开机自启`, and quit.

## Tests

```bash
swift test
```

81 tests cover the `claude` subprocess wrapper (binary discovery, timeout,
cancellation, output normalization, error classification, concurrency guard,
FD-leak check), the feed log (corruption recovery, cooldown, hungry detection),
the pet state machine, the feed coordinator, and the window configuration.

## Layout

```
Sources/MyPet/
  App/        MyPetApp, AppDelegate, MenubarController
  Window/     PetWindow (borderless, transparent, status-bar level, draggable)
  Scene/      TurtleView + CuteCatFace (all-vector cat, no SF Symbol)
  UI/         OnboardingView, TipBubble, FeedButton
  Domain/     ClaudeSubprocess, FeedCoordinator, PetState, LoginItem
  Storage/    FeedLog (JSON in Application Support)
```

See [CLAUDE.md](CLAUDE.md) for the architecture cheat-sheet and invariants
that exist to keep mypet stable + cheap (zero-CPU-when-idle, hover-via-Task,
single-in-flight feed, etc.).

## License

MIT. Built for Claude Code users who wanted something cute on their desktop.
PRs welcome — especially new tip prompts and seasonal cat skins.
