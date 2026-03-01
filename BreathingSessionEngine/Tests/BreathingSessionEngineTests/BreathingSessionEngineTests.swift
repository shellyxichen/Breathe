import XCTest
@testable import BreathingSessionEngine

final class BreathingSessionEngineTests: XCTestCase {
  func testBoxBoundaries() throws {
    let spec = try BreathingModeCatalog.load(id: "box")
    let engine = BreathingSessionEngine(spec: spec)

    let f0 = engine.frame(elapsedSec: 0)
    XCTAssertEqual(f0.phaseIndex, 0)
    XCTAssertEqual(f0.phaseType, .inhale)
    XCTAssertEqual(f0.phaseElapsed, 0, accuracy: 0.0001)
    XCTAssertEqual(f0.phaseProgress, 0, accuracy: 0.0001)

    let f3999 = engine.frame(elapsedSec: 3.999)
    XCTAssertEqual(f3999.phaseIndex, 0)
    XCTAssertEqual(f3999.phaseType, .inhale)

    let f4 = engine.frame(elapsedSec: 4.0)
    XCTAssertEqual(f4.phaseIndex, 1)
    XCTAssertEqual(f4.phaseType, .hold)
    XCTAssertEqual(f4.phaseElapsed, 0, accuracy: 0.0001)

    let f7999 = engine.frame(elapsedSec: 7.999)
    XCTAssertEqual(f7999.phaseIndex, 1)
    XCTAssertEqual(f7999.phaseType, .hold)

    let f8 = engine.frame(elapsedSec: 8.0)
    XCTAssertEqual(f8.phaseIndex, 2)
    XCTAssertEqual(f8.phaseType, .exhale)
    XCTAssertEqual(f8.phaseElapsed, 0, accuracy: 0.0001)

    let f16 = engine.frame(elapsedSec: 16.0)
    XCTAssertEqual(f16.phaseIndex, 0)
    XCTAssertEqual(f16.phaseType, .inhale)
  }

  func testPhaseRoleForHolds() throws {
    let spec = try BreathingModeCatalog.load(id: "box")
    let engine = BreathingSessionEngine(spec: spec)
    XCTAssertEqual(engine.phaseRole(phaseIndex: 1), .holdIn)
    XCTAssertEqual(engine.phaseRole(phaseIndex: 3), .holdOut)
  }

  func testSighInhaleFlowProgressDuringHold() throws {
    let spec = try BreathingModeCatalog.load(id: "physiological_sigh_326")
    let engine = BreathingSessionEngine(spec: spec)

    // Spec: inhale 3, hold 1, inhale 2, exhale 6
    // During the hold (between the two inhales), inhale flow should be 3 / (3 + 2) = 0.6.
    let holdFrame = engine.frame(elapsedSec: 3.5)
    XCTAssertEqual(holdFrame.phaseType, .hold)
    XCTAssertEqual(engine.inhaleFlowProgress(frame: holdFrame), 0.6, accuracy: 0.0001)

    let secondInhaleStart = engine.frame(elapsedSec: 4.0)
    XCTAssertEqual(secondInhaleStart.phaseType, .inhale)
    XCTAssertEqual(engine.inhaleFlowProgress(frame: secondInhaleStart), 0.6, accuracy: 0.0001)

    let secondInhaleMid = engine.frame(elapsedSec: 5.0) // 1s into 2s inhale
    XCTAssertEqual(secondInhaleMid.phaseType, .inhale)
    XCTAssertEqual(engine.inhaleFlowProgress(frame: secondInhaleMid), 0.8, accuracy: 0.0001)
  }
}

