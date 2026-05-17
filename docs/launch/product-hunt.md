# Product Hunt — launch checklist

## Name
```
mypet
```

## Tagline (≤60 chars)
```
A desktop cat that eats your Claude Code tokens
```

## Description (≤260 chars)
```
mypet is a fluffy macOS desktop cat. Hover for 1 second, it chomps one
`claude -p` call and a speech bubble pops with a Claude Code tip, a prompt
to try, a TIL, or a haiku. Zero CPU at rest. Uses your existing Claude
Code quota — no separate API key.
```

## Topics
```
Developer Tools, macOS, AI, Productivity, Open Source
```

## First-comment (maker)

```
Hey PH! 👋

I built mypet because my Claude Code subscription was sitting idle outside
of work hours. Instead of forcing myself to come up with prompts, I let the
cat surprise me — six themes (tip / prompt-to-try / news / TIL / joke /
haiku) rotate by weight so it never feels samey.

A few things I'm proud of:

🟢 Zero CPU when idle — SwiftUI TimelineView only runs while you're
   interacting. Truly free until you hover.

🟢 No new API key — it shells out to the local `claude` CLI, so you use
   the quota you already pay for.

🟢 Hover-to-feed via Task, not Timer — caught a 76-second autorelease
   crash early on; a SwiftUI `Timer` inside a struct closure was leaking.
   Documented the fix in CLAUDE.md if anyone hits the same trap.

🟢 87 tests, MIT, single binary: `swift build && swift run mypet`.

Currently I'm hand-rendering Apple cat emojis on a soft fluff halo. I've
wired a `Bundle.module` sprite loader so dropping `cat-<state>.png` files
upgrades the cat with zero code change — if anyone here makes art and
wants to contribute a skin, the slots are ready.

Would love feedback on:
- Theme weighting (do you want fewer haikus, more prompts?)
- macOS UX nits (snap-to-edge feels right? hover duration?)
```

## Image / video assets needed
1. Hero image — 1270×760 — clean screenshot of cat with a tip bubble showing
2. Demo GIF — `docs/screenshots/feed-demo.gif` (already exists)
3. Gallery 2–3: menubar with Recent tips submenu open / onboarding done card / snap-to-edge animation

## Maker reply templates

**"Why a pet?"**
> The unit of interaction is "look at the screen and act now" — a pet caught
> in your peripheral vision is a much weaker, friendlier nudge than a
> notification. You can ignore it; that's the point.

**"Why not bundle in the Claude Code CLI?"**
> mypet doesn't need to be part of CC to work — it just needs CC on your
> PATH. Keeping it separate means no lock-in either way. If Anthropic ever
> ships an official pet (please), mypet stays as the goofy MIT alternative.

**"Windows/Linux?"**
> Right now no — it's tightly tied to NSWindow / SwiftUI hover semantics.
> A web-based pet would be a different project. PR welcome.
