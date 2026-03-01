import Foundation

public struct BreathingFrame: Equatable, Sendable {
  public let phaseIndex: Int
  public let phaseType: PhaseType
  public let phaseElapsed: Double
  public let phaseProgress: Double
  public let timeRemaining: Double
  public let cycleProgress: Double

  public init(
    phaseIndex: Int,
    phaseType: PhaseType,
    phaseElapsed: Double,
    phaseProgress: Double,
    timeRemaining: Double,
    cycleProgress: Double
  ) {
    self.phaseIndex = phaseIndex
    self.phaseType = phaseType
    self.phaseElapsed = phaseElapsed
    self.phaseProgress = phaseProgress
    self.timeRemaining = timeRemaining
    self.cycleProgress = cycleProgress
  }
}

public enum PhaseRole: Sendable {
  case inhale
  case exhale
  case holdIn
  case holdOut
}

