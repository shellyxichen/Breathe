import Foundation

public struct BreathingSessionEngine: Sendable {
  public let spec: BreathingModeSpec

  public init(spec: BreathingModeSpec) {
    self.spec = spec
  }

  public func cycleDurationSec() -> Double {
    spec.phases.reduce(0) { $0 + $1.durationSec }
  }

  /// Port of `computeState()` in `assets/js/breathing.js`.
  public func frame(elapsedSec: Double) -> BreathingFrame {
    let cycle = cycleDurationSec()
    guard cycle > 0, !spec.phases.isEmpty else {
      return BreathingFrame(
        phaseIndex: 0,
        phaseType: .inhale,
        phaseElapsed: 0,
        phaseProgress: 0,
        timeRemaining: 0,
        cycleProgress: 0
      )
    }

    let timeInCycle = ((elapsedSec.truncatingRemainder(dividingBy: cycle)) + cycle)
      .truncatingRemainder(dividingBy: cycle)

    var acc = 0.0
    for (index, phase) in spec.phases.enumerated() {
      let start = acc
      let end = acc + phase.durationSec
      if timeInCycle >= start, timeInCycle < end, phase.durationSec > 0 {
        let phaseElapsed = timeInCycle - start
        let phaseProgress = phaseElapsed / phase.durationSec
        return BreathingFrame(
          phaseIndex: index,
          phaseType: phase.type,
          phaseElapsed: phaseElapsed,
          phaseProgress: phaseProgress,
          timeRemaining: phase.durationSec - phaseElapsed,
          cycleProgress: timeInCycle / cycle
        )
      }
      acc = end
    }

    let lastIndex = max(0, spec.phases.count - 1)
    let last = spec.phases[lastIndex]
    return BreathingFrame(
      phaseIndex: lastIndex,
      phaseType: last.type,
      phaseElapsed: max(0, last.durationSec),
      phaseProgress: 1,
      timeRemaining: 0,
      cycleProgress: 1
    )
  }

  /// Port of `getContiguousPhaseProgress()` in `assets/js/breathing.js`.
  public func contiguousPhaseProgress(frame: BreathingFrame) -> Double {
    guard spec.phases.indices.contains(frame.phaseIndex) else { return frame.phaseProgress }
    let phaseType = frame.phaseType
    guard phaseType == .inhale || phaseType == .exhale else { return frame.phaseProgress }

    var start = frame.phaseIndex
    var end = frame.phaseIndex

    while start > 0, spec.phases[start - 1].type == phaseType {
      start -= 1
    }

    while end < spec.phases.count - 1, spec.phases[end + 1].type == phaseType {
      end += 1
    }

    guard start != end else { return frame.phaseProgress }

    var segmentDuration = 0.0
    var elapsedInSegment = frame.phaseElapsed

    for i in start...end {
      let duration = spec.phases[i].durationSec
      segmentDuration += duration
      if i < frame.phaseIndex {
        elapsedInSegment += duration
      }
    }

    guard segmentDuration > 0 else { return frame.phaseProgress }
    return clamp(elapsedInSegment / segmentDuration, min: 0, max: 1)
  }

  /// Port of `getInhaleFlowProgress()` in `assets/js/breathing.js`.
  public func inhaleFlowProgress(frame: BreathingFrame) -> Double {
    guard spec.phases.indices.contains(frame.phaseIndex) else { return frame.phaseProgress }
    let current = spec.phases[frame.phaseIndex]
    guard current.type == .inhale || current.type == .hold else { return frame.phaseProgress }

    let phases = spec.phases
    let count = phases.count
    guard count > 0 else { return frame.phaseProgress }

    var previousExhaleIndex: Int?
    for step in 1...count {
      let idx = (frame.phaseIndex - step + count) % count
      if phases[idx].type == .exhale {
        previousExhaleIndex = idx
        break
      }
    }

    var nextExhaleIndex: Int?
    for step in 1...count {
      let idx = (frame.phaseIndex + step) % count
      if phases[idx].type == .exhale {
        nextExhaleIndex = idx
        break
      }
    }

    guard let prevExhale = previousExhaleIndex, let nextExhale = nextExhaleIndex else {
      return frame.phaseProgress
    }

    var totalInhaleDuration = 0.0
    var elapsedInhaleDuration = 0.0
    var currentPassed = false
    var idx = (prevExhale + 1) % count

    while idx != nextExhale {
      let phase = phases[idx]
      if phase.type == .inhale {
        totalInhaleDuration += phase.durationSec
        if !currentPassed {
          if idx == frame.phaseIndex, current.type == .inhale {
            elapsedInhaleDuration += frame.phaseElapsed
          } else {
            elapsedInhaleDuration += phase.durationSec
          }
        }
      }
      if idx == frame.phaseIndex {
        currentPassed = true
      }
      idx = (idx + 1) % count
    }

    guard totalInhaleDuration > 0 else { return frame.phaseProgress }
    return clamp(elapsedInhaleDuration / totalInhaleDuration, min: 0, max: 1)
  }

  /// Port of `getPhaseRole()` in `assets/js/breathing.js`.
  public func phaseRole(phaseIndex: Int) -> PhaseRole {
    guard spec.phases.indices.contains(phaseIndex) else { return .inhale }
    let phase = spec.phases[phaseIndex]
    switch phase.type {
    case .inhale:
      return .inhale
    case .exhale:
      return .exhale
    case .hold:
      let count = spec.phases.count
      if count == 0 { return .holdIn }
      let prevIndex = (phaseIndex - 1 + count) % count
      let prev = spec.phases[prevIndex]
      if prev.type == .inhale { return .holdIn }
      if prev.type == .exhale { return .holdOut }
      return phaseIndex < count / 2 ? .holdIn : .holdOut
    }
  }

  private func clamp(_ value: Double, min: Double, max: Double) -> Double {
    Swift.max(min, Swift.min(max, value))
  }
}

