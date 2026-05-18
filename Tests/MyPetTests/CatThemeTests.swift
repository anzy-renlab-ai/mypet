import XCTest
@testable import MyPet

final class CatThemeTests: XCTestCase {

    /// Every PetState case must have an asset mapping in the default theme.
    /// Without this, adding a new state without updating CatTheme would
    /// silently render as nothing.
    func test_default_mapsEveryPetStateCase() {
        let theme = CatTheme.default
        let allStates: [PetState] = [
            .idle, .eating, .excited, .purring,
            .hungry, .sleepy, .dozing, .sleeping,
            .clingTop, .peekLeft, .peekRight,
            .petting, .licking, .washing,
        ]
        for s in allStates {
            XCTAssertNotNil(theme.states[s.rawValue],
                            "PetState.\(s.rawValue) missing from CatTheme.default — every case must map to an asset")
        }
    }

    /// Sleep progression transitions reference real states only.
    func test_default_transitions_referenceValidStates() {
        let theme = CatTheme.default
        for tr in theme.transitions ?? [] {
            XCTAssertNotNil(PetState(rawValue: tr.from),
                            "Transition.from=\(tr.from) is not a valid PetState")
            XCTAssertNotNil(PetState(rawValue: tr.to),
                            "Transition.to=\(tr.to) is not a valid PetState")
        }
    }

    /// peekLeft and peekRight intentionally share the same APNG resource;
    /// peekLeft is rendered with a horizontal mirror at runtime.
    func test_default_peekLeftAndPeekRightShareResource() {
        let theme = CatTheme.default
        XCTAssertEqual(theme.states["peekLeft"], theme.states["peekRight"],
                       "peekLeft must alias peekRight — see TurtleView scaleEffect(x:-1) for peekLeft")
    }

    /// resourceName falls back to "cat-<state>" when the manifest omits one.
    func test_resourceName_fallsBack_whenNotMapped() {
        let theme = CatTheme(states: [:])
        XCTAssertEqual(theme.resourceName(for: "idle"), "cat-idle")
    }
}
