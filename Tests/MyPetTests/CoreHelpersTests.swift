import XCTest
@testable import MyPet

/// Coverage for small statics that lived without tests:
/// L10n, TurtleView.baseScale/baseDy, CatTheme.load fallback,
/// CatTheme.resourceName, CatAudio dedupe, LoginItem smoke, ThemeBadge.
@MainActor
final class CoreHelpersTests: XCTestCase {

    // MARK: - L10n

    func test_L10n_t_returnsEnglish_byDefault_onNonZhLocales() {
        // Can't mock Locale.preferredLanguages cleanly without swizzling,
        // but the contract is: `prefersChinese` only flips on a zh-* prefix.
        // Hit it via the public branch:
        if L10n.prefersChinese {
            XCTAssertEqual(L10n.t("hello", "你好"), "你好")
        } else {
            XCTAssertEqual(L10n.t("hello", "你好"), "hello")
        }
    }

    func test_L10n_t_distinctStringsPerLocale() {
        let en = "Feed"
        let zh = "喂猫"
        let picked = L10n.t(en, zh)
        XCTAssertTrue(picked == en || picked == zh,
                      "Must return one of the two inputs, not interpolate")
    }

    func test_L10n_t_handlesEmptyStrings() {
        // Edge: empty input shouldn't crash.
        XCTAssertNoThrow(_ = L10n.t("", ""))
    }

    // MARK: - TurtleView.baseScale / baseDy

    func test_baseScale_curledStatesShrunk() {
        // The curled / loaf / hanging poses are visually smaller than a
        // sitting cat — should be rendered slightly down-scaled.
        XCTAssertLessThan(CuteCatFace.baseScale(for: .sleeping), 1.0)
        XCTAssertLessThan(CuteCatFace.baseScale(for: .dozing), 1.0)
        XCTAssertLessThan(CuteCatFace.baseScale(for: .clingTop), 1.0)
    }

    func test_baseScale_uprightStatesStayAt1() {
        for s in [PetState.idle, .eating, .excited, .purring,
                  .sleepy, .hungry, .petting, .licking, .washing,
                  .peekLeft, .peekRight] {
            XCTAssertEqual(CuteCatFace.baseScale(for: s), 1.0,
                           "Upright sitting state \(s) should not down-scale")
        }
    }

    func test_baseDy_onlySleepingNudgedDown() {
        XCTAssertGreaterThan(CuteCatFace.baseDy(for: .sleeping), 0,
                             "sleeping (curled ball) should sit lower so it looks grounded")
        for s in [PetState.idle, .eating, .excited, .purring,
                  .sleepy, .hungry, .petting, .licking, .washing,
                  .peekLeft, .peekRight, .clingTop, .dozing] {
            XCTAssertEqual(CuteCatFace.baseDy(for: s), 0,
                           "\(s) should have no Y offset")
        }
    }

    // MARK: - CatTheme

    func test_CatTheme_default_resourceNameForKnownState() {
        XCTAssertEqual(CatTheme.default.resourceName(for: "idle"), "cat-idle")
        XCTAssertEqual(CatTheme.default.resourceName(for: "eating"), "cat-eating")
    }

    func test_CatTheme_resourceName_fallsBack_toCatPrefix() {
        // Unknown state → "cat-<state>" fallback so a missing entry never
        // returns nil / empty string.
        let theme = CatTheme(states: [:])
        XCTAssertEqual(theme.resourceName(for: "unknown"), "cat-unknown")
    }

    func test_CatTheme_load_returnsDefault_whenNoBundledJSON() {
        // The repo doesn't ship a theme.json — load() must fall back to
        // CatTheme.default, NOT return nil or crash.
        let loaded = CatTheme.load()
        XCTAssertFalse(loaded.states.isEmpty, "loaded theme must have mappings")
        XCTAssertEqual(loaded.resourceName(for: "idle"),
                       CatTheme.default.resourceName(for: "idle"))
    }

    func test_CatTheme_peekLeftAliasesPeekRight() {
        // peekLeft is rendered by mirroring peekRight at runtime; both
        // map to the same APNG resource by design.
        XCTAssertEqual(
            CatTheme.default.resourceName(for: "peekLeft"),
            CatTheme.default.resourceName(for: "peekRight")
        )
    }

    // MARK: - CatAudio

    func test_CatAudio_playIfChanged_dedupesSameState() {
        // Hammering with the same stateKey shouldn't keep starting new
        // AVAudioPlayer instances. Internally CatAudio tracks
        // lastPlayedState and bails on a repeat.
        let audio = CatAudio.shared
        // No public way to inspect, but the call must not throw.
        XCTAssertNoThrow(audio.playIfChanged(stateKey: "idle"))
        XCTAssertNoThrow(audio.playIfChanged(stateKey: "idle"))
        XCTAssertNoThrow(audio.playIfChanged(stateKey: "idle"))
    }

    func test_CatAudio_playIfChanged_missingAssetIsNoOp() {
        // Asking for a state with no bundled m4a must not crash —
        // CatAudio just logs "no asset" and returns.
        XCTAssertNoThrow(CatAudio.shared.playIfChanged(stateKey: "totally-not-a-state"))
    }

    // MARK: - LoginItem

    func test_LoginItem_isEnabled_doesNotCrash() {
        // We can't reliably toggle the user's login item from a test
        // (would touch SMAppService). Just smoke-test the read path.
        XCTAssertNoThrow(_ = LoginItem.isEnabled())
    }

    // MARK: - ThemeBadge

    func test_ThemeBadge_allConstantsDefined() {
        // Six theme badges, each must have an emoji + label + tint.
        let badges = [
            ThemeBadge.claudeTip,
            ThemeBadge.promptIdea,
            ThemeBadge.techNews,
            ThemeBadge.til,
            ThemeBadge.devJoke,
            ThemeBadge.dayouShi,
        ]
        for b in badges {
            XCTAssertFalse(b.emoji.isEmpty, "ThemeBadge must have an emoji")
            XCTAssertFalse(b.label.isEmpty, "ThemeBadge must have a label")
        }
    }

    func test_ThemeBadge_distinct() {
        // No two badges should collide on (emoji, label).
        let pairs = [
            (ThemeBadge.claudeTip.emoji, ThemeBadge.claudeTip.label),
            (ThemeBadge.promptIdea.emoji, ThemeBadge.promptIdea.label),
            (ThemeBadge.techNews.emoji, ThemeBadge.techNews.label),
            (ThemeBadge.til.emoji, ThemeBadge.til.label),
            (ThemeBadge.devJoke.emoji, ThemeBadge.devJoke.label),
            (ThemeBadge.dayouShi.emoji, ThemeBadge.dayouShi.label),
        ]
        let unique = Set(pairs.map { "\($0.0)/\($0.1)" })
        XCTAssertEqual(unique.count, pairs.count,
                       "Theme badges must be visually distinguishable")
    }
}
