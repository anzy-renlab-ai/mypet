# Reddit r/macapps — launch post

## Title
```
[App] mypet — a fluffy desktop cat that eats your Claude Code tokens (free, MIT)
```

## Body

```
Hey r/macapps! I made a tiny desktop pet for Claude Code users.

**Demo:** ![demo](https://github.com/anzy-renlab-ai/mypet/raw/master/docs/screenshots/feed-demo.gif)

**What it does**
The cat lives in your bottom-right corner. Hover over it for ~1 second, it
chomps one `claude -p` call, and a speech bubble pops with a Claude Code tip,
a prompt to try, a TIL, a programmer joke, or a programmer haiku — six themes
rotate by weight so it never feels samey. Click the bubble to copy the tip
to your clipboard.

**What it doesn't do**
- No background work — 0% CPU when you're not hovering. No network polling.
- No separate Anthropic API key. It shells out to your local `claude` CLI,
  so it uses the Claude Code quota you already pay for.
- No telemetry / login / cloud sync. Single binary.

**Tech**
SwiftUI + AppKit, macOS 13+, 1k LOC, 87 tests, MIT.

`git clone https://github.com/anzy-renlab-ai/mypet && cd mypet && swift run mypet`

If you find a state where the cat looks dumb or get a tip that feels off,
issues welcome 🐾
```

## Notes
- r/macapps mods like clear "what / what not / tech" framing — this template
  hits all three.
- Don't post on a Sunday — engagement dies. Tuesday morning is best.
- If a thread takes off, mention it on r/SwiftUI as a cross-post for the
  tech-curious subset.
