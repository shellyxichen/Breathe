/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionViewModel.swift
//
// Session orchestration for Breathe.
//

import AVFoundation
import BreathingSessionEngine
import CoreHaptics
import QuartzCore
import SwiftUI
import UIKit

@MainActor
final class SessionViewModel: NSObject, ObservableObject {
  @Published var isRunning: Bool = false

  /// True only when the most recent stop was a natural session completion
  /// (timer expired). The view uses this to pace the wind-down animation
  /// against the longer completion-chord envelope. Reset to false on every
  /// manual stop and at session start.
  @Published private(set) var lastStopWasNatural: Bool = false

  @Published var phaseLabel: String = ""
  @Published var phaseCountdown: String = ""
  @Published var sessionProgress: Double?

  @Published var haloScale: Double = 0.45
  @Published var haloGlow: Double = 0.2
  @Published var tempScalar: Double = 0
  @Published var ambientIntensity: Double = 0

  private var displayLink: CADisplayLink?
  private var startTime: CFTimeInterval = 0
  private var endTime: CFTimeInterval?
  private var lastPhaseIndex: Int = -1

  private var engine: BreathingSessionEngine?
  private var spec: BreathingModeSpec?

  private let cuePlayer = AudioCuePlayer()
  private let hapticPlayer = HapticCuePlayer()
  private let activityController = BreathingActivityController()
  private var beatTask: Task<Void, Never>?
  private var lastBeatKey: String = ""
  private var goBurstTask: Task<Void, Never>?
  private var suppressFirstBeat: Bool = false
  private var audioTailStopTask: Task<Void, Never>?
  private var didPlayCompletionTone: Bool = false
  private var stopFromActivityObserver: NSObjectProtocol?
  private var appDidEnterBackgroundObserver: NSObjectProtocol?
  private var appDidBecomeActiveObserver: NSObjectProtocol?
  private var idleAmbientEnabled: Bool = false
  private var shouldResumeIdleAmbientOnForeground: Bool = false
  /// Tracks the last time we pushed a Live Activity update from the beat
  /// task. CADisplayLink (the primary update driver) pauses when the
  /// device is locked, so we also push from the beat task — which keeps
  /// running thanks to background audio — to avoid the countdown
  /// freezing on the Lock Screen / Dynamic Island.
  private var lastActivityPushAt: CFTimeInterval = 0

  override init() {
    super.init()
    stopFromActivityObserver = NotificationCenter.default.addObserver(
      forName: .breatheStopSessionRequested,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.isRunning else { return }
        self.stop(playFinishTone: true)
      }
    }
    appDidEnterBackgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.handleAppDidEnterBackground()
      }
    }
    appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.handleAppDidBecomeActive()
      }
    }
  }

  /// Spin up audio/haptic engines ahead of time so countdown cues fire without
  /// the first-call setup latency.
  func primeCues() {
    cuePlayer.startIfNeeded()
    hapticPlayer.startIfNeeded()
  }

  /// Start a gentle ambient fade-in while the welcome/launcher screen is shown.
  func beginWelcomeAmbient() {
    idleAmbientEnabled = true
    shouldResumeIdleAmbientOnForeground = false
    cuePlayer.beginWelcomeNatureFadeIn()
  }

  /// Cue for one beat of the 3-2-1-Go countdown.
  /// All four beats share the soft in-phase volume; Go lifts the tone to inhale
  /// and fires a drumroll burst.
  func playCountdownCue(step: Int) {
    let isGo = step == 3
    let role: PhaseRole = isGo ? .inhale : .exhale
    // Countdown needs to cut through ambient bed + reverb tail; use a clearly
    // audible accent (Go slightly stronger).
    let accent = isGo ? 1.0 : 0.65
    cuePlayer.playPulse(role: role, accent: accent)
    if isGo {
      playGoBurst()
    } else {
      hapticPlayer.playOtherBeat()
    }
  }

  private func playGoBurst() {
    goBurstTask?.cancel()
    goBurstTask = Task { @MainActor [weak self] in
      guard let self else { return }
      self.hapticPlayer.playDrumrollTap()
      for _ in 0..<4 {
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else { return }
        self.hapticPlayer.playDrumrollTap()
      }
    }
  }

  /// Cancel any pending Go-burst beats (e.g. user cancels mid-countdown).
  func cancelCountdownCues() {
    goBurstTask?.cancel()
    goBurstTask = nil
  }

  func start(spec: BreathingModeSpec, durationSec: TimeInterval?, suppressFirstBeat: Bool = false) {
    if isRunning {
      // Full teardown only when replacing an active session.
      stop()
    } else {
      // Warm start from welcome/idle: preserve ambient bed continuity.
      displayLink?.invalidate()
      displayLink = nil
      beatTask?.cancel()
      beatTask = nil
      goBurstTask?.cancel()
      goBurstTask = nil
      lastBeatKey = ""
      lastPhaseIndex = -1
      sessionProgress = nil
      phaseLabel = ""
      phaseCountdown = ""
      setIdleTimerDisabled(false)
      activityController.end(finalState: nil)
    }
    self.suppressFirstBeat = suppressFirstBeat
    audioTailStopTask?.cancel()
    audioTailStopTask = nil
    didPlayCompletionTone = false
    lastStopWasNatural = false
    shouldResumeIdleAmbientOnForeground = false
    idleAmbientEnabled = false

    self.spec = spec
    self.engine = BreathingSessionEngine(spec: spec)

    let leadInSec = AudioCuePlayer.Config.leadInSec
    startTime = CACurrentMediaTime() + leadInSec
    if let durationSec {
      endTime = startTime + Self.adjustedDuration(for: durationSec, spec: spec)
      sessionProgress = 0
    } else {
      endTime = nil
      sessionProgress = nil
    }

    lastPhaseIndex = -1
    lastBeatKey = ""
    lastActivityPushAt = 0
    if let firstPhase = spec.phases.first {
      phaseLabel = phaseLabelText(for: firstPhase.type)
      phaseCountdown = formattedPhaseCountdown(firstPhase.durationSec)
    } else {
      phaseLabel = ""
      phaseCountdown = ""
    }
    haloScale = 0.45
    haloGlow = 0.2
    tempScalar = 0
    ambientIntensity = 0

    isRunning = true
    cuePlayer.duckNatureForSessionStart()

    // Keep the screen awake for the duration of the session. iOS suspends
    // CHHapticEngine (and UIFeedbackGenerator) the moment the device locks,
    // so without this haptics would stop firing once the auto-lock timer
    // hits even though our background audio continues. Restored in stop().
    setIdleTimerDisabled(true)

    startLiveActivity(spec: spec)

    hapticPlayer.startIfNeeded()
    startDisplayLink()
    startBeatTask()
  }

  private func startLiveActivity(spec: BreathingModeSpec) {
    let initialPhaseLabel = spec.phases.first.map { phaseLabelText(for: $0.type) } ?? ""
    let initialPhaseSec = spec.phases.first?.durationSec ?? 0
    let endsAt: Date? = endTime.map { end in
      let delta = end - CACurrentMediaTime()
      return Date().addingTimeInterval(delta)
    }
    let content = BreathingActivityContent(
      phaseLabel: initialPhaseLabel,
      phaseCountdownSec: initialPhaseSec,
      sessionProgress: 0,
      pulse: 0,
      sessionEndsAt: endsAt,
      isRunning: true
    )
    activityController.start(
      modeName: spec.displayName,
      modeSubtitle: "",
      initial: content
    )
  }

  func stop(playCompletionTone: Bool = false, playFinishTone: Bool = false) {
    // Publish the stop kind BEFORE flipping isRunning so observers reading
    // `lastStopWasNatural` in the same onChange handler see the new value.
    lastStopWasNatural = playCompletionTone
    isRunning = false
    displayLink?.invalidate()
    displayLink = nil

    beatTask?.cancel()
    beatTask = nil
    lastBeatKey = ""

    audioTailStopTask?.cancel()
    audioTailStopTask = nil
    shouldResumeIdleAmbientOnForeground = false
    // Both manual stop and natural completion keep the nature bed continuous
    // and restore it to idle/welcome level. `playCompletionTone` only marks
    // the stop as a natural finish for the slower UI wind-down; `playFinishTone`
    // controls whether we add the modal sus chord (A2/E3/A3 + B3).
    idleAmbientEnabled = true
    if playFinishTone {
      cuePlayer.playModalChord()
    }
    cuePlayer.restoreNatureAfterSessionEnd()
    hapticPlayer.stop()

    activityController.end(finalState: nil)

    setIdleTimerDisabled(false)
    // Visual state (haloScale, haloGlow, tempScalar, ambientIntensity,
    // phaseLabel, phaseCountdown, sessionProgress) is intentionally left as-is so
    // the view layer can animate it back to idle values via withAnimation in its
    // onChange(of: isRunning) handler.
  }

  deinit {
    if let stopFromActivityObserver {
      NotificationCenter.default.removeObserver(stopFromActivityObserver)
    }
    if let appDidEnterBackgroundObserver {
      NotificationCenter.default.removeObserver(appDidEnterBackgroundObserver)
    }
    if let appDidBecomeActiveObserver {
      NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
    }
    // Safety net: never leave the auto-lock disabled if the view model is
    // torn down without a clean stop() call.
    Task { @MainActor in
      UIApplication.shared.isIdleTimerDisabled = false
    }
  }

  private func handleAppDidEnterBackground() {
    guard !isRunning, idleAmbientEnabled else { return }
    shouldResumeIdleAmbientOnForeground = true
    cuePlayer.stop()
  }

  private func handleAppDidBecomeActive() {
    guard !isRunning, shouldResumeIdleAmbientOnForeground else { return }
    shouldResumeIdleAmbientOnForeground = false
    cuePlayer.beginWelcomeNatureFadeIn()
  }

  private func setIdleTimerDisabled(_ disabled: Bool) {
    UIApplication.shared.isIdleTimerDisabled = disabled
  }

  private func startDisplayLink() {
    displayLink?.invalidate()
    let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  @objc private func handleDisplayLink() {
    guard isRunning, let engine else { return }
    let now = CACurrentMediaTime()

    if let endTime, now >= endTime {
      stopAfterNaturalCompletionIfNeeded()
      return
    }

    let elapsedSec = (now - startTime)
    let frame = engine.frame(elapsedSec: elapsedSec)

    phaseLabel = phaseLabelText(for: frame.phaseType)
    phaseCountdown = formattedPhaseCountdown(frame.timeRemaining)

    if let endTime {
      let total = max(0.0001, endTime - startTime)
      let progress = (now - startTime) / total
      sessionProgress = max(0, min(1, progress))
    }

    cuePlayer.updateAmbient(
      role: engine.phaseRole(phaseIndex: frame.phaseIndex),
      phaseProgress: frame.phaseProgress
    )

    updateHalo(engine: engine, frame: frame)

    if frame.phaseIndex != lastPhaseIndex {
      lastPhaseIndex = frame.phaseIndex
    }

    pushLiveActivityUpdate(now: now, frame: frame)
  }

  private func pushLiveActivityUpdate(now: CFTimeInterval, frame: BreathingFrame) {
    // Normalize haloScale (0.45 idle → 1.0 peak) into 0..1 for the Lock
    // Screen pulse. Falls back gracefully if scale ever drifts outside the
    // expected band.
    let pulse = max(0, min(1, (haloScale - 0.45) / 0.55))
    let endsAt: Date? = endTime.map { Date().addingTimeInterval($0 - now) }
    let content = BreathingActivityContent(
      phaseLabel: phaseLabelText(for: frame.phaseType),
      phaseCountdownSec: max(0, frame.timeRemaining),
      sessionProgress: sessionProgress ?? 0,
      pulse: pulse,
      sessionEndsAt: endsAt,
      isRunning: true
    )
    activityController.update(content)
  }

  private func updateHalo(engine: BreathingSessionEngine, frame: BreathingFrame) {
    let baseScale = 0.45
    let peakScale = 1.0

    let isInhale = frame.phaseType == .inhale
    let isExhale = frame.phaseType == .exhale

    let visualPhaseProgress = engine.contiguousPhaseProgress(frame: frame)
    let inhaleFlowProgress = engine.inhaleFlowProgress(frame: frame)

    var scale = baseScale
    var glow = 0.2
    var intensity = 0.25

    if isInhale {
      scale = baseScale + (peakScale - baseScale) * inhaleFlowProgress
      glow = 0.2 + 0.5 * inhaleFlowProgress
      intensity = 0.25 + 0.6 * inhaleFlowProgress
    } else if isExhale {
      scale = peakScale - (peakScale - baseScale) * visualPhaseProgress
      glow = 0.7 - 0.45 * visualPhaseProgress
      intensity = 0.85 - 0.5 * visualPhaseProgress
    } else {
      let previousActive = previousActivePhaseType(engine: engine, phaseIndex: frame.phaseIndex)
      if previousActive == .inhale {
        scale = baseScale + (peakScale - baseScale) * inhaleFlowProgress
        glow = 0.2 + 0.5 * inhaleFlowProgress
        intensity = 0.25 + 0.6 * inhaleFlowProgress
      } else {
        scale = baseScale
        glow = 0.45
        intensity = 0.2
      }
    }

    let targetScalar = isInhale ? 1.0 : isExhale ? -1.0 : 0.0
    tempScalar += (targetScalar - tempScalar) * 0.06

    haloScale = scale
    haloGlow = glow
    ambientIntensity = intensity
  }

  private func stopAfterNaturalCompletionIfNeeded() {
    guard !didPlayCompletionTone else { return }
    didPlayCompletionTone = true
    stop(playCompletionTone: true, playFinishTone: true)
  }

  private func previousActivePhaseType(engine: BreathingSessionEngine, phaseIndex: Int) -> PhaseType? {
    let phases = engine.spec.phases
    let count = phases.count
    guard count > 0 else { return nil }

    for step in 1...count {
      let idx = (phaseIndex - step + count) % count
      let type = phases[idx].type
      if type != .hold { return type }
    }
    return nil
  }

  private static func adjustedDuration(for duration: TimeInterval, spec: BreathingModeSpec) -> TimeInterval {
    let cycle = spec.phases.reduce(0.0) { $0 + $1.durationSec }
    guard cycle > 0, !spec.phases.isEmpty else { return duration }

    let fullCycles = floor(duration / cycle)
    let remainder = duration - (fullCycles * cycle)

    if remainder < 0.01 { return duration }

    var acc = 0.0
    for phase in spec.phases {
      acc += phase.durationSec
      if acc >= remainder - 0.01 {
        return (fullCycles * cycle) + acc
      }
    }

    return (fullCycles + 1) * cycle
  }

  private func phaseLabelText(for type: PhaseType) -> String {
    switch type {
    case .inhale:
      return "Inhale"
    case .exhale:
      return "Exhale"
    case .hold:
      return "Hold"
    }
  }

  private func startBeatTask() {
    beatTask?.cancel()
    beatTask = Task { @MainActor [weak self] in
      guard let self else { return }
      guard let engine else { return }

      cuePlayer.startIfNeeded()

      let leadInSec = AudioCuePlayer.Config.leadInSec
      try? await Task.sleep(nanoseconds: UInt64(leadInSec * 1_000_000_000))
      guard !Task.isCancelled else { return }

      if !suppressFirstBeat {
        cuePlayer.playPulse(role: engine.phaseRole(phaseIndex: 0), accent: 1.0)
        hapticPlayer.playPhaseStart()
      }
      lastBeatKey = "0:0"

      while !Task.isCancelled, isRunning {
        let now = CACurrentMediaTime()
        if let endTime, now >= endTime {
          stopAfterNaturalCompletionIfNeeded()
          return
        }

        let frame = engine.frame(elapsedSec: now - startTime)
        guard engine.spec.phases.indices.contains(frame.phaseIndex) else {
          try? await Task.sleep(nanoseconds: 20_000_000)
          continue
        }

        let phase = engine.spec.phases[frame.phaseIndex]
        let duration = max(0.0001, phase.durationSec)
        let pulses = max(1, Int((duration * AudioCuePlayer.Config.pulsesPerSecond).rounded()))
        let interval = duration / Double(pulses)

        let phaseElapsed = min(duration - 0.0001, max(0, duration * frame.phaseProgress))
        let pulseIndex = min(pulses - 1, Int(floor(phaseElapsed / interval)))
        let beatKey = "\(frame.phaseIndex):\(pulseIndex)"
        if beatKey != lastBeatKey {
          lastBeatKey = beatKey
          let accent = pulseIndex == 0 ? 1.0 : AudioCuePlayer.Config.quietScalar
          cuePlayer.playPulse(role: engine.phaseRole(phaseIndex: frame.phaseIndex), accent: accent)
          if pulseIndex == 0 {
            hapticPlayer.playPhaseStart()
          } else {
            hapticPlayer.playOtherBeat()
          }
        }

        // Push a Live Activity update from this background-safe loop so
        // the countdown keeps ticking when the device is locked (the
        // display link is paused in that state). The controller's
        // internal 0.5 s throttle dedups against any concurrent push
        // from handleDisplayLink while the screen is on.
        if now - lastActivityPushAt >= 0.25 {
          lastActivityPushAt = now
          pushLiveActivityUpdate(now: now, frame: frame)
        }

        try? await Task.sleep(nanoseconds: 20_000_000)
      }
    }
  }
}

@MainActor
final class HapticCuePlayer {
  private let fallbackPhaseGenerator = UIImpactFeedbackGenerator(style: .heavy)
  private let fallbackBeatGenerator = UIImpactFeedbackGenerator(style: .rigid)

  private let supportsCoreHaptics: Bool = CHHapticEngine.capabilitiesForHardware().supportsHaptics
  private var engine: CHHapticEngine?
  private var phasePlayer: CHHapticAdvancedPatternPlayer?

  func startIfNeeded() {
    fallbackPhaseGenerator.prepare()
    fallbackBeatGenerator.prepare()
    // Use the async start API so we don't block the main thread (the sync
    // `engine.start()` can take 200-500 ms on first boot, which stalls
    // SwiftUI animations on the welcome screen).
    startCoreHapticEngineAsync()
  }

  private func startCoreHapticEngineAsync() {
    guard supportsCoreHaptics else { return }
    guard ensureEngineInitialized() else { return }
    engine?.start(completionHandler: { _ in })
  }

  @discardableResult
  private func ensureEngineInitialized() -> Bool {
    if engine != nil { return true }
    do {
      let newEngine = try CHHapticEngine()
      newEngine.stoppedHandler = { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.engine = nil
          self?.phasePlayer = nil
        }
      }
      newEngine.resetHandler = { [weak self] in
        Task { @MainActor [weak self] in
          self?.startCoreHapticEngineAsync()
        }
      }
      engine = newEngine
      return true
    } catch {
      engine = nil
      return false
    }
  }

  func stop() {
    if let phasePlayer {
      try? phasePlayer.stop(atTime: CHHapticTimeImmediate)
    }
    phasePlayer = nil

    if let engine {
      engine.stop(completionHandler: { _ in })
    }
    engine = nil
  }

  func playPhaseStart() {
    if playCorePhaseStart() { return }

    fallbackPhaseGenerator.prepare()
    fallbackPhaseGenerator.impactOccurred(intensity: 1.0)
    fallbackPhaseGenerator.prepare()
  }

  func playOtherBeat() {
    if playCoreOtherBeat() { return }

    fallbackBeatGenerator.prepare()
    fallbackBeatGenerator.impactOccurred(intensity: 0.65)
    fallbackBeatGenerator.prepare()
  }

  /// Punchy transient tap for countdown beats — max intensity, sharp.
  func playStrongTick() {
    if playCoreStrongTick() { return }

    fallbackPhaseGenerator.prepare()
    fallbackPhaseGenerator.impactOccurred(intensity: 1.0)
    fallbackPhaseGenerator.prepare()
  }

  /// Heavier "thud" tap for drumroll bursts — short continuous event with
  /// bassier sharpness so successive taps feel like a real drumroll.
  func playDrumrollTap() {
    if playCoreDrumrollTap() { return }

    fallbackPhaseGenerator.prepare()
    fallbackPhaseGenerator.impactOccurred(intensity: 1.0)
    fallbackPhaseGenerator.prepare()
  }

  private func ensureEngineStarted() -> Bool {
    guard supportsCoreHaptics else { return false }
    guard ensureEngineInitialized() else { return false }
    do {
      try engine?.start()
      return true
    } catch {
      engine = nil
      return false
    }
  }

  private func playCorePhaseStart() -> Bool {
    guard ensureEngineStarted(), let engine else { return false }

    // Stop any in-flight continuous phase haptic immediately.
    if let phasePlayer {
      try? phasePlayer.stop(atTime: CHHapticTimeImmediate)
      self.phasePlayer = nil
    }

    let durationSec: Double = 0.32
    let intensity: Float = 0.95
    let sharpness: Float = 0.25

    let event = CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
      ],
      relativeTime: 0,
      duration: durationSec
    )

    do {
      let pattern = try CHHapticPattern(events: [event], parameters: [])
      let player = try engine.makeAdvancedPlayer(with: pattern)
      self.phasePlayer = player
      try player.start(atTime: CHHapticTimeImmediate)
      return true
    } catch {
      return false
    }
  }

  private func playCoreOtherBeat() -> Bool {
    guard ensureEngineStarted(), let engine else { return false }

    let intensity: Float = 0.60
    let sharpness: Float = 0.70

    let event = CHHapticEvent(
      eventType: .hapticTransient,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
      ],
      relativeTime: 0
    )

    do {
      let pattern = try CHHapticPattern(events: [event], parameters: [])
      let player = try engine.makePlayer(with: pattern)
      try player.start(atTime: CHHapticTimeImmediate)
      return true
    } catch {
      return false
    }
  }

  private func playCoreStrongTick() -> Bool {
    guard ensureEngineStarted(), let engine else { return false }

    let intensity: Float = 1.0
    let sharpness: Float = 0.70

    let event = CHHapticEvent(
      eventType: .hapticTransient,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
      ],
      relativeTime: 0
    )

    do {
      let pattern = try CHHapticPattern(events: [event], parameters: [])
      let player = try engine.makePlayer(with: pattern)
      try player.start(atTime: CHHapticTimeImmediate)
      return true
    } catch {
      return false
    }
  }

  private func playCoreDrumrollTap() -> Bool {
    guard ensureEngineStarted(), let engine else { return false }

    // Drum-hit envelope: instant attack, quick decay — feels like a real "boom".
    let click = CHHapticEvent(
      eventType: .hapticTransient,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
      ],
      relativeTime: 0
    )
    let boom = CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15),
        CHHapticEventParameter(parameterID: .attackTime, value: 0.0),
        CHHapticEventParameter(parameterID: .sustained, value: 0.0),
        CHHapticEventParameter(parameterID: .decayTime, value: 0.18),
        CHHapticEventParameter(parameterID: .releaseTime, value: 0.05),
      ],
      relativeTime: 0,
      duration: 0.25
    )

    do {
      let pattern = try CHHapticPattern(events: [click, boom], parameters: [])
      let player = try engine.makePlayer(with: pattern)
      try player.start(atTime: CHHapticTimeImmediate)
      return true
    } catch {
      return false
    }
  }
}

final class AudioCuePlayer {
  enum OceanPreset {
    case gentle
    case balanced
    case deep

    var surfCenterHz: Double {
      switch self {
      case .gentle:
        return 220
      case .balanced:
        return 260
      case .deep:
        return 185
      }
    }

    var surfQ: Double {
      switch self {
      case .gentle:
        return 0.70
      case .balanced:
        return 0.80
      case .deep:
        return 0.60
      }
    }

    var swellHz: Double {
      switch self {
      case .gentle:
        return 0.07
      case .balanced:
        return 0.12
      case .deep:
        return 0.05
      }
    }

    var swellPeriodSec: Double {
      1 / max(0.0001, swellHz)
    }

    // Ocean amplitude = swellBase + swellDepth * swell(0..1)
    var swellBase: Double {
      switch self {
      case .gentle:
        return 0.60
      case .balanced:
        return 0.35
      case .deep:
        return 0.70
      }
    }

    var swellDepth: Double {
      switch self {
      case .gentle:
        return 0.25
      case .balanced:
        return 0.65
      case .deep:
        return 0.20
      }
    }

    // Final ocean synth gain before global nature volume scaling.
    var synthGain: Double {
      switch self {
      case .gentle:
        return 0.06
      case .balanced:
        return 0.08
      case .deep:
        return 0.05
      }
    }
  }

  struct Config {
    static let basePitch: Double = 220
    static let pulsesPerSecond: Double = 1
    static let quietScalar: Double = 0.1
    static let leadInSec: Double = 0.04
    static let pulseDurationSec: Double = 0.42
    static let attackSec: Double = 0.04
    static let peakVoice: Double = 0.22
    static let masterDb: Double = 12
    // Layer toggles for quick A/B listening during tuning.
    static let enableReverb: Bool = false
    static let enableDroneLayer: Bool = false
    static let reverbWetDryMix: Float = 12
    static let droneBaseHz: Double = 110
    static let droneLoopSec: Double = 8.0
    static let dronePeakVolume: Double = 0.12
    static let natureMinimumLoopSec: Double = 24.0
    static let natureSwellCyclesPerLoop: Double = 2.0
    static let natureVolume: Double = 0.60
    static let natureSessionVolume: Double = 0.36
    static let natureFadeInDelaySec: Double = 0.12
    static let natureFadeInSec: Double = 2.6
    static let natureDuckSec: Double = 1.8
    static let natureRenderWarmupSec: Double = 0.18
    static let natureSeamBlendSec: Double = 1.2
    // Temporarily hide the ocean bed without deleting the synth path.
    static let enableNatureOcean: Bool = false
    static let enableNatureRain: Bool = false
    static var enableNatureLayer: Bool { enableNatureOcean || enableNatureRain }
    // Quick A/B switch: .gentle, .balanced, .deep
    static let oceanPreset: OceanPreset = .gentle
  }

  private let queue = DispatchQueue(label: "Breathe.AudioCuePlayer")
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var dronePlayer: AVAudioPlayerNode?
  private var naturePlayer: AVAudioPlayerNode?
  private var renderFormat: AVAudioFormat?
  private var reverbNode: AVAudioUnitReverb?
  private var dronePitchNode: AVAudioUnitTimePitch?
  private var droneLoopBuffer: AVAudioPCMBuffer?
  private var natureLoopBuffer: AVAudioPCMBuffer?
  private var currentDroneVolume: Double = 0
  private var currentDronePitchCents: Double = 0
  private var isStarted: Bool = false
  private var configChangeObserver: NSObjectProtocol?
  private var natureVolumeRampToken: Int = 0

  func startIfNeeded() {
    queue.async {
      self.startIfNeededLocked()
    }
  }

  func stop() {
    queue.async {
      self.teardownEngineLocked(deactivateSession: true)
    }
  }

  /// Fade in nature bed for the launcher/welcome experience.
  func beginWelcomeNatureFadeIn() {
    queue.async {
      guard Config.enableNatureLayer else { return }
      self.startIfNeededLocked()
      guard self.isStarted else { return }
      self.rampNatureVolumeLocked(
        to: Float(Config.natureVolume),
        durationSec: Config.natureFadeInSec,
        startDelaySec: Config.natureFadeInDelaySec
      )
    }
  }

  /// Lower nature bed once countdown completes and session officially starts.
  func duckNatureForSessionStart() {
    queue.async {
      guard Config.enableNatureLayer else { return }
      self.startIfNeededLocked()
      guard self.isStarted else { return }
      self.rampNatureVolumeLocked(to: Float(Config.natureSessionVolume), durationSec: Config.natureDuckSec)
    }
  }

  /// Bring nature bed back up after a naturally completed session.
  func restoreNatureAfterSessionEnd() {
    queue.async {
      guard Config.enableNatureLayer else { return }
      self.startIfNeededLocked()
      guard self.isStarted else { return }
      self.rampNatureVolumeLocked(to: Float(Config.natureVolume), durationSec: Config.natureFadeInSec)
    }
  }

  func playPulse(role: PhaseRole, accent: Double) {
    queue.async {
      self.startIfNeededLocked()
      guard self.isStarted else { return }
      guard let player = self.player, let format = self.renderFormat else { return }

      let sampleRate = max(1, format.sampleRate)
      let frames = AVAudioFrameCount(sampleRate * Config.pulseDurationSec)

      guard
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
      else {
        return
      }
      buffer.frameLength = frames

      let pitch = self.pitch(for: role)
      let formant = self.formant(for: role)
      let breath = self.breath(for: role)

      self.renderPulse(
        into: buffer,
        sampleRate: sampleRate,
        pitch: pitch,
        formant: formant * 0.85,
        breath: breath,
        accent: max(0, accent)
      )

      player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
      if !player.isPlaying {
        self.startNodeIfPossible(player)
      }
    }
  }

  /// Modal "sus" chord on natural session completion. Uses only intervals
  /// already present in the drone (A2 / E3 / A3) plus a soft B3 sus2 color —
  /// deliberately no major third, so the chord reads as the drone settling
  /// onto its root rather than announcing a major resolution.
  func playModalChord() {
    queue.async {
      self.startIfNeededLocked()
      guard self.isStarted else { return }
      guard let player = self.player, let format = self.renderFormat else { return }

      let sampleRate = max(1, format.sampleRate)
      let durationSec: Double = 6.8
      let frames = AVAudioFrameCount(sampleRate * durationSec)

      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
        return
      }
      buffer.frameLength = frames

      self.renderModalChord(into: buffer, sampleRate: sampleRate, durationSec: durationSec)
      player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
      if !player.isPlaying {
        player.play()
      }
    }
  }

  /// Smoothly fade the drone and nature layers to silence over `durationSec`.
  /// Used to let the ambient bed dissolve alongside the closing exhale rather
  /// than being cut at engine stop.
  func fadeOutAmbient(durationSec: Double) {
    queue.async {
      guard Config.enableDroneLayer || Config.enableNatureLayer else { return }
      guard self.isStarted else { return }
      let stepSec: Double = 0.05
      let steps = max(1, Int(durationSec / stepSec))
      let startDrone = self.dronePlayer?.volume ?? 0
      let startNature = self.naturePlayer?.volume ?? 0

      for step in 1...steps {
        let progress = Double(step) / Double(steps)
        let factor = Float(max(0, 1 - progress))
        let droneVol = startDrone * factor
        let natureVol = startNature * factor
        self.queue.asyncAfter(deadline: .now() + stepSec * Double(step)) { [weak self] in
          guard let self, self.isStarted else { return }
          self.dronePlayer?.volume = droneVol
          self.naturePlayer?.volume = natureVol
          self.currentDroneVolume = Double(droneVol)
        }
      }
    }
  }

  func updateAmbient(role: PhaseRole, phaseProgress: Double) {
    queue.async {
      guard Config.enableDroneLayer else { return }
      guard self.isStarted else { return }
      guard let dronePlayer = self.dronePlayer, let dronePitchNode = self.dronePitchNode else { return }

      let progress = max(0, min(1, phaseProgress))
      let targetVolume = self.droneVolume(for: role, phaseProgress: progress)
      let targetPitchCents = self.dronePitchCents(for: role)

      self.currentDroneVolume += (targetVolume - self.currentDroneVolume) * 0.12
      self.currentDronePitchCents += (targetPitchCents - self.currentDronePitchCents) * 0.08

      dronePlayer.volume = Float(self.currentDroneVolume)
      dronePitchNode.pitch = Float(self.currentDronePitchCents)
    }
  }

  private func startIfNeededLocked() {
    guard !isStarted else { return }

    let session = AVAudioSession.sharedInstance()
    do {
      try configureAudioSession(session)
    } catch {
      #if DEBUG
      NSLog("[Breathe] Audio session configuration failed: \(error.localizedDescription)")
      #endif
      return
    }

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let dronePlayer = AVAudioPlayerNode()
    let naturePlayer = AVAudioPlayerNode()
    let reverbNode = AVAudioUnitReverb()
    let dronePitchNode = AVAudioUnitTimePitch()
    reverbNode.loadFactoryPreset(.mediumHall)
    reverbNode.wetDryMix = Config.reverbWetDryMix
    dronePitchNode.pitch = 0
    self.engine = engine
    self.player = player
    self.dronePlayer = dronePlayer
    self.naturePlayer = naturePlayer
    self.reverbNode = reverbNode
    self.dronePitchNode = dronePitchNode

    // Touch mainMixerNode to trigger its lazy connect to outputNode so we can
    // read the actual hardware sample rate the engine will use. Falling back
    // to the audio session value if the output format isn't ready yet.
    let mixer = engine.mainMixerNode
    let outputFormat = engine.outputNode.outputFormat(forBus: 0)
    let sampleRate: Double = {
      if outputFormat.sampleRate > 0 { return outputFormat.sampleRate }
      return max(1, session.sampleRate)
    }()
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
      return
    }
    self.renderFormat = format

    let useReverb = Config.enableReverb
    let useDrone = Config.enableDroneLayer
    let useNature = Config.enableNatureLayer

    engine.attach(player)
    if useReverb {
      engine.attach(reverbNode)
      engine.connect(player, to: reverbNode, format: format)
      engine.connect(reverbNode, to: mixer, format: nil)
    } else {
      // Guaranteed fallback path for reliable countdown/session audibility.
      engine.connect(player, to: mixer, format: format)
    }

    if useDrone {
      engine.attach(dronePlayer)
      engine.attach(dronePitchNode)
      // Keep source/effect edges pinned to our mono render format so scheduled
      // PCM buffers always match each player's output format.
      engine.connect(dronePlayer, to: dronePitchNode, format: format)
      if useReverb {
        engine.connect(dronePitchNode, to: reverbNode, format: format)
      } else {
        engine.connect(dronePitchNode, to: mixer, format: format)
      }
    }

    if useNature {
      engine.attach(naturePlayer)
      engine.connect(naturePlayer, to: mixer, format: format)
    }
    mixer.outputVolume = 1.0

    engine.prepare()

    do {
      try engine.start()
      if useDrone || useNature {
        scheduleAmbientLoopsLocked(sampleRate: sampleRate, format: format)
      }
      startNodeIfPossible(player)
      if useDrone {
        startNodeIfPossible(dronePlayer)
      }
      if useNature {
        startNodeIfPossible(naturePlayer)
      }
      isStarted = true
      if useReverb || useDrone || useNature {
        // Observe configuration changes after successful start so startup route
        // negotiation does not immediately tear down a freshly built graph.
        installConfigChangeObserver(for: engine)
      }
    } catch {
      isStarted = false
      #if DEBUG
      NSLog("[Breathe] AVAudioEngine start failed: \(error.localizedDescription)")
      #endif
      teardownEngineLocked(deactivateSession: false)
    }
  }

  /// Starts a player node only when its engine is alive and running.
  private func startNodeIfPossible(_ node: AVAudioPlayerNode) {
    guard let engine = node.engine, engine.isRunning else { return }
    if !node.isPlaying {
      node.play()
    }
  }

  private func installConfigChangeObserver(for engine: AVAudioEngine) {
    if let existing = configChangeObserver {
      NotificationCenter.default.removeObserver(existing)
      configChangeObserver = nil
    }
    configChangeObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: nil
    ) { [weak self] _ in
      guard let self else { return }
      self.queue.async {
        #if DEBUG
        NSLog("[Breathe] AVAudioEngine configuration changed — tearing down audio chain.")
        #endif
        self.teardownEngineLocked(deactivateSession: false)
      }
    }
  }

  /// Tears down the engine + nodes without touching the audio session.
  /// Called from both `stop()` and the configuration-change handler.
  private func teardownEngineLocked(deactivateSession: Bool) {
    if isStarted {
      player?.stop()
      dronePlayer?.stop()
      naturePlayer?.stop()
      engine?.stop()
      engine?.reset()
    }
    isStarted = false
    if let observer = configChangeObserver {
      NotificationCenter.default.removeObserver(observer)
      configChangeObserver = nil
    }
    player = nil
    dronePlayer = nil
    naturePlayer = nil
    engine = nil
    renderFormat = nil
    reverbNode = nil
    dronePitchNode = nil
    droneLoopBuffer = nil
    natureLoopBuffer = nil
    currentDroneVolume = 0
    currentDronePitchCents = 0
    natureVolumeRampToken += 1
    if deactivateSession {
      let session = AVAudioSession.sharedInstance()
      try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
  }

  private func rampNatureVolumeLocked(to target: Float, durationSec: Double, startDelaySec: Double = 0) {
    guard let naturePlayer, naturePlayer.engine != nil else { return }

    natureVolumeRampToken += 1
    let token = natureVolumeRampToken
    let start = naturePlayer.volume
    let clampedTarget = max(0, target)
    let rampDuration = max(0.05, durationSec)
    let rampStartDelay = max(0, startDelaySec)
    let stepSec: Double = 0.05
    let steps = max(1, Int((rampDuration / stepSec).rounded()))

    for step in 1...steps {
      let progress = Float(step) / Float(steps)
      let volume = start + (clampedTarget - start) * progress
      queue.asyncAfter(deadline: .now() + rampStartDelay + stepSec * Double(step)) { [weak self] in
        guard let self else { return }
        guard self.natureVolumeRampToken == token else { return }
        guard self.isStarted else { return }
        self.naturePlayer?.volume = volume
      }
    }
  }

  private func configureAudioSession(_ session: AVAudioSession) throws {
    // Use .playback so audio routes to the speaker (or connected Bluetooth)
    // without requiring microphone permission.
    try session.setCategory(.playback, mode: .default)
    try session.setActive(true)

    #if false // GLASSES_SDK: temporarily disabled — original routing for Meta AI glasses
    // .playAndRecord enables bidirectional audio with glasses but requires
    // NSMicrophoneUsageDescription. Re-enable when glasses capability is ready.
    try session.setCategory(
      .playAndRecord,
      mode: .default,
      options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
    )
    if let bluetoothInput = preferredBluetoothInput(from: session.availableInputs) {
      try session.setPreferredInput(bluetoothInput)
    }
    try session.setActive(true)

    if !hasBluetoothOutput(session.currentRoute) {
      try session.setCategory(
        .playback,
        mode: .default,
        options: [.allowBluetoothA2DP]
      )
      try session.setActive(true)
    }
    #endif // GLASSES_SDK
  }

  private func preferredBluetoothInput(from inputs: [AVAudioSessionPortDescription]?) -> AVAudioSessionPortDescription? {
    guard let inputs else { return nil }
    return inputs.first(where: { $0.portType == .bluetoothHFP })
      ?? inputs.first(where: { $0.portType == .bluetoothLE })
  }

  private func hasBluetoothOutput(_ route: AVAudioSessionRouteDescription) -> Bool {
    route.outputs.contains(where: {
      $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
    })
  }

  #if DEBUG
  private func logCurrentRoute(_ session: AVAudioSession) {
    let outputPorts = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ", ")
    NSLog("[Breathe] Audio route outputs: \(outputPorts)")
  }
  #endif

  private func masterGain() -> Double {
    pow(10, Config.masterDb / 20)
  }

  private func scheduleAmbientLoopsLocked(sampleRate: Double, format: AVAudioFormat) {
    if Config.enableDroneLayer, let dronePlayer, dronePlayer.engine != nil,
      let droneBuffer = makeDroneLoopBuffer(sampleRate: sampleRate, format: format)
    {
      droneLoopBuffer = droneBuffer
      dronePlayer.volume = 0
      dronePlayer.scheduleBuffer(droneBuffer, at: nil, options: [.loops], completionHandler: nil)
    }

    if Config.enableNatureLayer, let naturePlayer, naturePlayer.engine != nil,
      let natureBuffer = makeNatureLoopBuffer(sampleRate: sampleRate, format: format)
    {
      natureLoopBuffer = natureBuffer
      naturePlayer.volume = 0
      naturePlayer.scheduleBuffer(natureBuffer, at: nil, options: [.loops], completionHandler: nil)
    }
  }

  private func renderPulse(
    into buffer: AVAudioPCMBuffer,
    sampleRate: Double,
    pitch: Double,
    formant: Double,
    breath: Double,
    accent: Double
  ) {
    guard let channels = buffer.floatChannelData else { return }
    let channelCount = Int(buffer.format.channelCount)
    guard channelCount > 0 else { return }

    let duration = Double(buffer.frameLength) / sampleRate
    let attack = min(Config.attackSec, duration * 0.5)
    let peak = Config.peakVoice * accent * masterGain()
    let omega = 2 * Double.pi * pitch

    let q = 0.6
    var filter = BiquadBandpass(sampleRate: sampleRate, centerHz: formant, q: q)

    for i in 0..<Int(buffer.frameLength) {
      let t = Double(i) / sampleRate

      let envelope: Double
      if t <= attack {
        envelope = (t / max(0.0001, attack))
      } else {
        let remaining = max(0.0001, duration - attack)
        let x = (t - attack) / remaining
        envelope = pow(0.0001, x)
      }

      let tone = sin(omega * t)
      let noise = filter.process(Double.random(in: -1...1))

      let sample = (tone + noise * breath) * peak * envelope
      let value = Float(sample)
      for ch in 0..<channelCount {
        channels[ch][i] = value
      }
    }
  }

  private func makeDroneLoopBuffer(sampleRate: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let frameCount = AVAudioFrameCount(sampleRate * Config.droneLoopSec)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
    buffer.frameLength = frameCount
    guard let channels = buffer.floatChannelData else { return nil }

    let base = Config.droneBaseHz
    let gain = Config.dronePeakVolume * masterGain()

    for i in 0..<Int(frameCount) {
      let t = Double(i) / sampleRate
      // Slow "singing bowl" shimmer with soft harmonics.
      let slowBeat = 0.5 + 0.5 * sin(2 * Double.pi * 0.08 * t)
      let fundamental = sin(2 * Double.pi * base * t)
      let octave = 0.33 * sin(2 * Double.pi * base * 2 * t + 0.3)
      let fifth = 0.22 * sin(2 * Double.pi * base * 1.5 * t + 1.1)
      let sample = (fundamental + octave + fifth) * gain * (0.65 + 0.35 * slowBeat)
      let value = Float(sample)
      channels[0][i] = value
    }

    return buffer
  }

  private func makeNatureLoopBuffer(sampleRate: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard Config.enableNatureOcean || Config.enableNatureRain else { return nil }
    let preset = Config.oceanPreset
    let loopFrameCount = max(1, Int(sampleRate * natureLoopDurationSec(for: preset)))
    let seamFrames = max(1, min(loopFrameCount / 4, Int(sampleRate * Config.natureSeamBlendSec)))
    let renderFrameCount = loopFrameCount + seamFrames
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(loopFrameCount)
      )
    else {
      return nil
    }
    buffer.frameLength = AVAudioFrameCount(loopFrameCount)
    guard let channels = buffer.floatChannelData else { return nil }

    var lowpass = OnePoleLowpass(sampleRate: sampleRate, cutoffHz: 1400)
    var surfBand = BiquadBandpass(sampleRate: sampleRate, centerHz: preset.surfCenterHz, q: preset.surfQ)
    let warmupFrames = max(0, Int(sampleRate * Config.natureRenderWarmupSec))
    let rainWeight = Config.enableNatureRain ? 0.35 : 0.0
    let oceanWeight = Config.enableNatureOcean ? 0.65 : 0.0
    let totalWeight = max(0.0001, rainWeight + oceanWeight)
    var rawSamples = [Double](repeating: 0, count: renderFrameCount)

    // Warm the filters up off-path, then render slightly past the loop end so
    // the first ~1s of the loop can blend from the "future" continuation back
    // into the true start instead of dipping to silence at every wrap.
    for i in 0..<warmupFrames {
      let t = Double(i) / sampleRate
      _ = renderNatureSample(
        at: t,
        preset: preset,
        lowpass: &lowpass,
        surfBand: &surfBand,
        rainWeight: rainWeight,
        oceanWeight: oceanWeight,
        totalWeight: totalWeight
      )
    }

    for i in 0..<renderFrameCount {
      let t = Double(i + warmupFrames) / sampleRate
      rawSamples[i] = renderNatureSample(
        at: t,
        preset: preset,
        lowpass: &lowpass,
        surfBand: &surfBand,
        rainWeight: rainWeight,
        oceanWeight: oceanWeight,
        totalWeight: totalWeight
      )
    }

    let channelCount = Int(buffer.format.channelCount)
    guard channelCount > 0 else { return nil }

    for i in 0..<loopFrameCount {
      let sample: Float
      if i < seamFrames, seamFrames > 1 {
        let x = Double(i) / Double(seamFrames - 1)
        let continuationGain = cos(0.5 * Double.pi * x)
        let restartGain = sin(0.5 * Double.pi * x)
        sample = Float(
          rawSamples[loopFrameCount + i] * continuationGain
            + rawSamples[i] * restartGain
        )
      } else {
        sample = Float(rawSamples[i])
      }

      for ch in 0..<channelCount {
        channels[ch][i] = sample
      }
    }

    return buffer
  }

  private func natureLoopDurationSec(for preset: OceanPreset) -> Double {
    max(
      Config.natureMinimumLoopSec,
      preset.swellPeriodSec * Config.natureSwellCyclesPerLoop
    )
  }

  private func renderNatureSample(
    at timeSec: Double,
    preset: OceanPreset,
    lowpass: inout OnePoleLowpass,
    surfBand: inout BiquadBandpass,
    rainWeight: Double,
    oceanWeight: Double,
    totalWeight: Double
  ) -> Double {
    let white = Double.random(in: -1...1)
    let rain = lowpass.process(white)
    let swell = 0.5 + 0.5 * sin(2 * Double.pi * preset.swellHz * timeSec)
    let ocean = surfBand.process(white) * (preset.swellBase + preset.swellDepth * swell)
    return ((rain * rainWeight) + (ocean * oceanWeight)) / totalWeight * preset.synthGain * masterGain()
  }

  private func renderModalChord(
    into buffer: AVAudioPCMBuffer,
    sampleRate: Double,
    durationSec: Double
  ) {
    guard let channels = buffer.floatChannelData else { return }
    let channelCount = Int(buffer.format.channelCount)
    guard channelCount > 0 else { return }

    // Open-fifth / sus2 voicing — matches the drone's A2/E3/A3 spectrum
    // and adds a soft B3 (sus2) for gentle motion. No major third — keeps
    // the modal character of the session intact.
    let components: [(freq: Double, amp: Double)] = [
      (110.0, 0.55),    // A2 — drone fundamental
      (165.0, 0.32),    // E3 — drone fifth
      (220.0, 0.28),    // A3 — base voice pitch
      (247.5, 0.16),    // B3 — sus2 color
    ]
    // Worst-case constructive sum of the amplitudes — used to normalize so
    // the chord peaks at ~the same level as a single phase pulse.
    let normalizer = components.reduce(0.0) { $0 + $1.amp }

    // Slow cosine bloom, brief plateau, long exponential decay — gives the
    // chord time to settle in alongside the drone instead of striking.
    let attackSec: Double = 1.4
    let releaseSec: Double = 3.4
    let sustainSec = max(0, durationSec - attackSec - releaseSec)
    let peak = Config.peakVoice * 0.7 * masterGain()

    // Same bandpass-filtered breath texture used in renderPulse, mixed in
    // very quietly so the chord shares timbre with every phase voice.
    var filter = BiquadBandpass(
      sampleRate: sampleRate,
      centerHz: self.formant(for: .exhale) * 0.85,
      q: 0.6
    )
    let breathAmount = 0.04

    for i in 0..<Int(buffer.frameLength) {
      let t = Double(i) / sampleRate

      let envelope: Double
      if t < attackSec {
        let x = t / max(0.0001, attackSec)
        envelope = 0.5 * (1 - cos(Double.pi * x))
      } else if t < attackSec + sustainSec {
        envelope = 1.0
      } else {
        let releaseT = (t - attackSec - sustainSec) / max(0.0001, releaseSec)
        envelope = pow(0.0001, releaseT)
      }

      var tone = 0.0
      for comp in components {
        tone += sin(2 * Double.pi * comp.freq * t) * comp.amp
      }
      tone /= max(0.0001, normalizer)

      let noise = filter.process(Double.random(in: -1...1))
      let sample = (tone + noise * breathAmount) * peak * envelope

      let value = Float(sample)
      for ch in 0..<channelCount {
        channels[ch][i] = value
      }
    }
  }

  private func pitch(for role: PhaseRole) -> Double {
    switch role {
    case .inhale:
      return Config.basePitch * 1.1
    case .holdIn:
      return Config.basePitch * 1.3
    case .exhale:
      return Config.basePitch * 0.75
    case .holdOut:
      return Config.basePitch * 0.6
    }
  }

  private func formant(for role: PhaseRole) -> Double {
    switch role {
    case .inhale:
      return 1100
    case .holdIn:
      return 1200
    case .exhale:
      return 650
    case .holdOut:
      return 460
    }
  }

  private func breath(for role: PhaseRole) -> Double {
    switch role {
    case .exhale:
      return 0.12
    case .inhale:
      return 0.08
    case .holdIn, .holdOut:
      return 0.02
    }
  }

  private func droneVolume(for role: PhaseRole, phaseProgress: Double) -> Double {
    let base = Config.dronePeakVolume
    switch role {
    case .inhale:
      // Fade up during inhale.
      return base * (0.45 + 0.55 * phaseProgress)
    case .exhale:
      // Fade down during exhale.
      return base * (1.0 - 0.55 * phaseProgress)
    case .holdIn:
      return base * 0.85
    case .holdOut:
      return base * 0.38
    }
  }

  private func dronePitchCents(for role: PhaseRole) -> Double {
    switch role {
    case .inhale:
      return 18
    case .holdIn:
      return 28
    case .exhale:
      return -26
    case .holdOut:
      return -42
    }
  }
}

private struct BiquadBandpass {
  private let b0: Double
  private let b1: Double
  private let b2: Double
  private let a1: Double
  private let a2: Double

  private var x1: Double = 0
  private var x2: Double = 0
  private var y1: Double = 0
  private var y2: Double = 0

  init(sampleRate: Double, centerHz: Double, q: Double) {
    let omega = 2 * Double.pi * (centerHz / sampleRate)
    let alpha = sin(omega) / (2 * max(0.0001, q))

    let bb0 = alpha
    let bb1 = 0.0
    let bb2 = -alpha
    let aa0 = 1 + alpha
    let aa1 = -2 * cos(omega)
    let aa2 = 1 - alpha

    b0 = bb0 / aa0
    b1 = bb1 / aa0
    b2 = bb2 / aa0
    a1 = aa1 / aa0
    a2 = aa2 / aa0
  }

  mutating func process(_ x0: Double) -> Double {
    let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
    x2 = x1
    x1 = x0
    y2 = y1
    y1 = y0
    return y0
  }
}

private struct OnePoleLowpass {
  private let alpha: Double
  private var y1: Double = 0

  init(sampleRate: Double, cutoffHz: Double) {
    let sr = max(1, sampleRate)
    let wc = 2 * Double.pi * max(1, cutoffHz)
    let dt = 1 / sr
    let rc = 1 / wc
    alpha = dt / (rc + dt)
  }

  mutating func process(_ x: Double) -> Double {
    y1 += alpha * (x - y1)
    return y1
  }
}
