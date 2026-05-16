# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
swift build                          # build
swift run mypet                      # run app
swift test                           # full suite (~78 tests)
swift test --filter FeedCoordinatorTests
swift test --filter FeedCoordinatorTests/testCooldownSurfacesTip   # single test
MYPET_AUTO_FEED=1 swift run mypet    # auto-fires one feed ~1.5s after launch (debug)
```

macOS 13+. No external SwiftPM dependencies. The `claude` CLI must be on `PATH` at runtime (the app does not bundle it).

## Architecture

Three layers, all `@MainActor` for UI state:

**Window/Scene** — `PetWindow` is borderless, transparent, `.statusBar` level, lives bottom-right, draggable by background. It resizes between `compactSize` (100×100, just the pet) and `expandedSize` (340×220, room for a tip bubble) via `setExpanded(_:)`; the resize is driven by `AppDelegate.tipCancellable` subscribing to `coordinator.$tip`. After every resize, `placeBottomRight()` re-anchors so the pet doesn't jump. `TurtleView` (in `Scene/`) is the pet — it owns hover-to-feed and per-state motion only; it never talks to the subprocess or log directly.

**Domain** — `FeedCoordinator` is the single orchestrator. `feed()` walks: cooldown check → `.eating` → `ClaudeSubprocess.shared.feed(prompt:)` → on success `.excited` (overlay, 3s) → `.purring` (tip shown, 8s auto-dismiss) → `.idle`; on failure it routes through `friendlyMessage(for:)` which maps every `ClaudeSubprocessError` case to user copy. `PetStateMachine` is the pure-Swift state transition table (no UI, no I/O) with the 6 states from `PetState`. **Hungry is event-driven (decision D11)**: it is only checked when `evaluateIdle()` is invoked (app activate, mouse near, post-feed) — there is no background timer.

**Subprocess** — `ClaudeSubprocess` discovers `claude` on `PATH` (`discoverBinary`), runs `claude -p <prompt> --output-format text` with a 20s timeout, and normalizes the LLM output (`normalizeTip`: strips ANSI, code fences, list markers, takes first line, truncates to 140 chars). Concurrency is enforced by an `AsyncSemaphore(value: 1)`: a second `feed()` while one is in-flight returns `.busy` instead of queueing. `classifyStderr` maps `claude` CLI failures to typed errors (`notAuthenticated`, `rateLimited`, `systemError`). Pure helpers (`discoverBinary`, `runRaw`, `normalizeTip`, `classifyStderr`) are static so tests can exercise them without the singleton.

**Storage** — `FeedLog` is a JSON file in Application Support; `lastFeedTimestamp()` powers the cooldown check. Corruption-recovery is covered by tests; never assume the file is well-formed.

## Invariants — do not break

1. **Zero CPU when idle.** `TurtleView.body` only wraps content in `TimelineView(.animation)` when `needsAnimation` is true (`hoverToken != nil || state != .idle`). Otherwise it renders one static frame. Adding a `TimelineView` unconditionally regresses ISSUE-001 (60fps idle burn).
2. **Hover-to-feed uses `.task(id: hoverToken)`, not `Timer`.** A `Timer` captured in a SwiftUI struct closure caused the 76s segfault during autorelease cleanup. Pattern is: cursor enter sets a fresh `UUID` token, the `.task(id:)` sleeps `petDuration` then calls `onFeed`, cursor exit / drag clears the token which auto-cancels the task.
3. **Single in-flight feed.** Never bypass `AsyncSemaphore.tryAcquire()` in `ClaudeSubprocess.feed`. Concurrent `claude` subprocesses spawned from hover spam will exhaust FDs.
4. **Cooldown surfaces a tip.** `FeedCoordinator.feed()` must emit a "还在消化呢..." tip when rejected; silent reject (the pre-ISSUE-006 behavior) makes the user think the app is broken.
5. **Window resize is driven by `coordinator.$tip`.** Don't compute window size from view layout; SwiftUI inside a fixed-frame `NSHostingView` will silently clip (the pre-ISSUE-002/003 bug). After `setExpanded`, always call `placeBottomRight()`.
6. **Onboarding copy must match the actual interaction.** Hover-to-feed, not click — keep `OnboardingView` strings aligned with `TurtleView` (ISSUE-004/005).

## Tests

`Tests/MyPetTests/` mirrors the domain layout: `ClaudeSubprocessTests` (binary discovery, timeout, cancellation, normalization, FD-leak check, concurrency guard), `FeedCoordinatorTests` (orchestration via a stubbed `Feeder`), `PetStateTests` (pure state machine), `FeedLogTests` (corruption recovery, cooldown), `PetWindowTests` (resize + draggability). The stubbed `Feeder` protocol in `FeedCoordinator.swift` is the seam — write coordinator tests against it, never against a real subprocess.

## Sprite pipeline (optional)

`scripts/gen-sprite.ts` and `gen-all-sprites.ts` are an AI sprite-generation pipeline writing into `Sources/MyPet/Resources/sprites/`. The runtime currently uses SF Symbols (`tortoise.fill`) and does not depend on the generated PNGs, but the pipeline is wired so a future state can swap to sprite assets.
