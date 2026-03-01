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

  @Published var phaseLabel: String = ""
  @Published var phaseCountdown: String = ""
  @Published var sessionProgress: Double?

  @Published var haloScale: Double = 0.3
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
  private var beatTask: Task<Void, Never>?
  private var lastBeatKey: String = ""

  func start(spec: BreathingModeSpec, durationSec: TimeInterval?) {
    stop()

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
    if let firstPhase = spec.phases.first {
      phaseLabel = phaseLabelText(for: firstPhase.type)
      phaseCountdown = formattedPhaseCountdown(firstPhase.durationSec)
    } else {
      phaseLabel = ""
      phaseCountdown = ""
    }
    haloScale = 0.3
    haloGlow = 0.2
    tempScalar = 0
    ambientIntensity = 0

    isRunning = true

    hapticPlayer.startIfNeeded()
    startDisplayLink()
    startBeatTask()
  }

  func stop() {
    isRunning = false
    displayLink?.invalidate()
    displayLink = nil

    beatTask?.cancel()
    beatTask = nil
    lastBeatKey = ""

    cuePlayer.stop()
    hapticPlayer.stop()
    sessionProgress = nil
    phaseLabel = ""
    phaseCountdown = ""
    haloScale = 0.3
    haloGlow = 0.2
    tempScalar = 0
    ambientIntensity = 0
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
      stop()
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

    updateHalo(engine: engine, frame: frame)

    if frame.phaseIndex != lastPhaseIndex {
      lastPhaseIndex = frame.phaseIndex
    }
  }

  private func updateHalo(engine: BreathingSessionEngine, frame: BreathingFrame) {
    let baseScale = 0.3
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

      cuePlayer.playPulse(role: engine.phaseRole(phaseIndex: 0), accent: 1.0)
      hapticPlayer.playPhaseStart()
      lastBeatKey = "0:0"

      while !Task.isCancelled, isRunning {
        let now = CACurrentMediaTime()
        if let endTime, now >= endTime {
          stop()
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
    _ = ensureEngineStarted()
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

  private func ensureEngineStarted() -> Bool {
    guard supportsCoreHaptics else { return false }

    if engine == nil {
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
            guard let self else { return }
            _ = self.ensureEngineStarted()
          }
        }
        engine = newEngine
      } catch {
        engine = nil
        return false
      }
    }

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
}

final class AudioCuePlayer {
  struct Config {
    static let basePitch: Double = 220
    static let pulsesPerSecond: Double = 1
    static let quietScalar: Double = 0.1
    static let leadInSec: Double = 0.04
    static let pulseDurationSec: Double = 0.42
    static let attackSec: Double = 0.04
    static let peakVoice: Double = 0.22
    static let masterDb: Double = 0
  }

  private let queue = DispatchQueue(label: "Breathe.AudioCuePlayer")
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var renderFormat: AVAudioFormat?
  private var isStarted: Bool = false

  func startIfNeeded() {
    queue.async {
      self.startIfNeededLocked()
    }
  }

  func stop() {
    queue.async {
      if self.isStarted {
        self.player?.stop()
        self.engine?.stop()
        self.engine?.reset()
        self.isStarted = false
      }
      self.player = nil
      self.engine = nil
      self.renderFormat = nil
      let session = AVAudioSession.sharedInstance()
      try? session.setActive(false, options: [.notifyOthersOnDeactivation])
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
        player.play()
      }
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
    self.engine = engine
    self.player = player

    let sampleRate = max(1, session.sampleRate)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
      return
    }
    self.renderFormat = format

    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = 1.0

    do {
      try engine.start()
      player.play()
      isStarted = true
    } catch {
      isStarted = false
      #if DEBUG
      NSLog("[Breathe] AVAudioEngine start failed: \(error.localizedDescription)")
      #endif
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
