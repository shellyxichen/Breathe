import Foundation

public enum PhaseType: String, Codable, Sendable {
  case inhale
  case exhale
  case hold
}

public struct BreathingPhase: Codable, Equatable, Sendable {
  public let type: PhaseType
  public let durationSec: Double

  public init(type: PhaseType, durationSec: Double) {
    self.type = type
    self.durationSec = durationSec
  }
}

public struct BreathingModeSpec: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let displayName: String
  public let loop: Bool
  public let phases: [BreathingPhase]

  public init(id: String, displayName: String, loop: Bool, phases: [BreathingPhase]) {
    self.id = id
    self.displayName = displayName
    self.loop = loop
    self.phases = phases
  }
}

