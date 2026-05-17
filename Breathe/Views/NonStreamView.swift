/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// NonStreamView.swift
//
// Combined session configuration + visualization screen.
//

import BreathingSessionEngine
import SwiftUI
import UIKit

struct NonStreamView: View {
  @ObservedObject var sessionViewModel: SessionViewModel
  let modes: [BreathingModeSpec]
  @Binding var selectedModeId: String
  let modesLoadError: String?

  @State private var countdownText: String = ""
  @State private var isCountingDown = false

  @State private var startTextOpacity: Double = 1
  @State private var modeAndDotsOpacity: Double = 1
  @State private var countdownOpacity: Double = 0
  @State private var phaseTextOpacity: Double = 0
  @State private var progressBarOpacity: Double = 0
  @State private var haloPulseAmount: Double = 0
  @State private var modeTextOpacity: Double = 1
  @State private var startTask: Task<Void, Never>?

  @State private var pressGlowBoost: Double = 0
  @State private var pressRimAmount: Double = 0
  @State private var pressScaleAmount: Double = 0
  @State private var pressTask: Task<Void, Never>?

  var body: some View {
    ZStack {
      BreathingAmbientBackground(
        tempScalar: backgroundTempScalar,
        intensity: backgroundIntensity,
        modeTintRGB: modeBackgroundSignature.tintRGB,
        modeTintOpacity: modeBackgroundSignature.tintOpacity * modeSignatureIdleWeight
      )
        .ignoresSafeArea()

      GeometryReader { proxy in
        HaloView(
          scale: sessionViewModel.haloScale,
          glow: sessionViewModel.haloGlow,
          tempScalar: sessionViewModel.tempScalar,
          phaseLabel: sessionViewModel.phaseLabel,
          phaseCountdown: sessionViewModel.phaseCountdown,
          phaseTextOpacity: phaseTextOpacity,
          pulseScale: haloPulseAmount + pressScaleAmount,
          pressGlowBoost: pressGlowBoost,
          pressRimAmount: pressRimAmount
        )
        .position(x: proxy.size.width * 0.5, y: haloCenterY(in: proxy))
      }
      .ignoresSafeArea()
      .allowsHitTesting(false)

      GeometryReader { proxy in
        Text(countdownText)
          .font(.system(size: 20, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.white.opacity(0.50))
          .contentTransition(.opacity)
          .position(x: proxy.size.width * 0.5, y: haloCenterY(in: proxy))
      }
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .opacity(countdownOpacity)

      GeometryReader { proxy in
        Text("Start")
          .font(.system(size: 20, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.50))
          .position(x: proxy.size.width * 0.5, y: haloCenterY(in: proxy))
      }
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .opacity(startTextOpacity)

      VStack(spacing: 24) {
        if let error = modesLoadError {
          Text("Unable to load modes: \(error)")
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.white.opacity(0.58))
            .multilineTextAlignment(.center)
        }

        if let mode = selectedMode {
          VStack(spacing: 6) {
            Text(modeSubtitle(mode))
              .font(.system(.subheadline, design: .rounded).weight(.medium))
              .foregroundStyle(.white.opacity(0.7))
              .multilineTextAlignment(.center)
              .contentTransition(.opacity)

            if let desc = modeDescription(mode) {
              Text(desc)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .contentTransition(.opacity)
            }
          }
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 8)
          .opacity(modeTextOpacity)
        }

        DotIndicator(
          count: orderedModes.count,
          activeIndex: currentModeIndex
        )
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 56)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      .opacity(modeAndDotsOpacity)
      .allowsHitTesting(modeAndDotsOpacity > 0.5)

      SubtleSessionProgressBar(progress: sessionViewModel.sessionProgress ?? 0)
        .padding(.horizontal, 24)
        .padding(.bottom, 1)
        .opacity(0.42 * progressBarOpacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    .contentShape(Rectangle())
    .onTapGesture {
      handleTap()
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 50)
        .onEnded { value in
          handleSwipe(translation: value.translation)
        }
    )
    .onChange(of: sessionViewModel.isRunning) { wasRunning, isNow in
      if wasRunning && !isNow {
        runStopSequence(naturalCompletion: sessionViewModel.lastStopWasNatural)
      }
    }
  }

  private var selectedMode: BreathingModeSpec? {
    if let mode = modes.first(where: { $0.id == selectedModeId }) { return mode }
    return modes.first
  }

  /// Keep the mode tint most visible at idle so inhale/exhale colors remain the
  /// primary visual signal once a session starts.
  private var modeSignatureIdleWeight: Double {
    let phasePresence = abs(sessionViewModel.tempScalar)
    let ambientPresence = min(1, sessionViewModel.ambientIntensity / 0.22)
    return max(0, 1 - max(phasePresence, ambientPresence))
  }

  private var backgroundTempScalar: Double {
    let tint = modeBackgroundSignature.tempBias * modeSignatureIdleWeight
    return max(-1, min(1, sessionViewModel.tempScalar + tint))
  }

  private var backgroundIntensity: Double {
    let lift = modeBackgroundSignature.intensityLift * modeSignatureIdleWeight
    return max(0, sessionViewModel.ambientIntensity + lift)
  }

  private var modeBackgroundSignature: ModeBackgroundSignature {
    switch selectedMode?.id ?? selectedModeId {
    case "box":
      return .init(
        tempBias: -0.040,
        intensityLift: 0.008,
        tintRGB: RGB(66, 86, 118),
        tintOpacity: 0.200
      )
    case "box_8888":
      return .init(
        tempBias: -0.120,
        intensityLift: 0.012,
        tintRGB: RGB(84, 86, 154),
        tintOpacity: 0.225
      )
    case "coherent_55":
      return .init(
        tempBias: -0.050,
        intensityLift: 0.010,
        tintRGB: RGB(54, 118, 116),
        tintOpacity: 0.215
      )
    case "relax_478":
      return .init(
        tempBias: 0.160,
        intensityLift: 0.016,
        tintRGB: RGB(156, 98, 58),
        tintOpacity: 0.230
      )
    case "physiological_sigh_326":
      return .init(
        tempBias: -0.100,
        intensityLift: 0.012,
        tintRGB: RGB(66, 128, 140),
        tintOpacity: 0.220
      )
    default:
      return .init(
        tempBias: -0.040,
        intensityLift: 0.008,
        tintRGB: RGB(66, 86, 118),
        tintOpacity: 0.100
      )
    }
  }

  private var orderedModes: [BreathingModeSpec] {
    let order = ["box", "box_8888", "coherent_55", "relax_478", "physiological_sigh_326"]
    var ordered = order.compactMap { orderedId in
      modes.first(where: { $0.id == orderedId })
    }
    let leftovers = modes
      .filter { mode in !order.contains(mode.id) }
      .sorted { $0.displayName < $1.displayName }
    ordered.append(contentsOf: leftovers)
    return ordered
  }

  private func handleTap() {
    // Reserve the press-shrink feedback for launching a session; using it for
    // stop/cancel makes the long finish settle feel abrupt.
    if !sessionViewModel.isRunning, !isCountingDown {
      runPressFeedback()
    }
    toggleSession()
  }

  private func toggleSession() {
    if sessionViewModel.isRunning {
      sessionViewModel.stop(playFinishTone: true)
      return
    }
    if isCountingDown {
      cancelCountdown()
      return
    }
    guard let spec = selectedMode else { return }
    startSequence(spec: spec)
  }

  /// Glassmorphic tap feedback: glow alpha briefly boosts to 1.4x, the inner
  /// rim thickens (1.5px -> 2.5px) and brightens (alpha 0.25 -> 0.50), and
  /// the halo scales down to 95% over 100ms before springing back to 100%.
  /// Mirrors the wearable Start-button press spec.
  private func runPressFeedback() {
    pressTask?.cancel()
    withAnimation(.easeOut(duration: 0.10)) {
      pressScaleAmount = -0.05
      pressGlowBoost = 0.4
      pressRimAmount = 1.0
    }
    pressTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 100_000_000)
      guard !Task.isCancelled else { return }
      withAnimation(.spring(response: 0.20, dampingFraction: 0.55)) {
        pressScaleAmount = 0
      }
      try? await Task.sleep(nanoseconds: 100_000_000)
      guard !Task.isCancelled else { return }
      withAnimation(.easeInOut(duration: 0.20)) {
        pressGlowBoost = 0
        pressRimAmount = 0
      }
    }
  }

  private func cancelCountdown() {
    startTask?.cancel()
    startTask = nil
    sessionViewModel.cancelCountdownCues()
    isCountingDown = false
    withAnimation(.easeInOut(duration: 0.2)) {
      countdownOpacity = 0
      haloPulseAmount = 0
    }
    withAnimation(.easeInOut(duration: 0.3)) {
      startTextOpacity = 1
      modeAndDotsOpacity = 1
    }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 300_000_000)
      countdownText = ""
    }
  }

  private func startSequence(spec: BreathingModeSpec) {
    startTask?.cancel()
    isCountingDown = true

    withAnimation(.easeInOut(duration: 0.2)) { startTextOpacity = 0 }
    withAnimation(.easeInOut(duration: 0.3)) { modeAndDotsOpacity = 0 }

    startTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 500_000_000)
      guard !Task.isCancelled else { return }

      countdownOpacity = 1

      for (index, n) in ["3", "2", "1"].enumerated() {
        guard !Task.isCancelled else { return }
        sessionViewModel.playCountdownCue(step: index)
        await pulseBeat(text: n, amplitude: 0.04, durationSec: 1.0)
      }
      guard !Task.isCancelled else { return }

      sessionViewModel.playCountdownCue(step: 3)
      await pulseBeat(text: "Go", amplitude: 0.08, durationSec: 0.6)
      try? await Task.sleep(nanoseconds: 200_000_000)
      guard !Task.isCancelled else { return }

      withAnimation(.easeInOut(duration: 0.2)) { countdownOpacity = 0 }
      sessionViewModel.start(
        spec: spec,
        durationSec: BreathingTimerOption.sec120.durationSec
      )
      isCountingDown = false
      withAnimation(.easeInOut(duration: 0.3)) { phaseTextOpacity = 1 }
      withAnimation(.easeInOut(duration: 0.5)) { progressBarOpacity = 1 }

      try? await Task.sleep(nanoseconds: 200_000_000)
      countdownText = ""
    }
  }

  private func pulseBeat(text: String, amplitude: Double, durationSec: Double) async {
    // Drum-hit envelope: fast rise (matches audio attack), slow decay.
    let riseSec = min(0.12, durationSec * 0.18)
    let fallSec = max(0.05, durationSec - riseSec)
    withAnimation(.easeOut(duration: riseSec)) {
      countdownText = text
      haloPulseAmount = amplitude
    }
    try? await Task.sleep(nanoseconds: UInt64(riseSec * 1_000_000_000))
    withAnimation(.easeOut(duration: fallSec)) {
      haloPulseAmount = 0
    }
    try? await Task.sleep(nanoseconds: UInt64(fallSec * 1_000_000_000))
  }

  private func runStopSequence(naturalCompletion _: Bool) {
    startTask?.cancel()
    startTask = nil
    isCountingDown = false

    // Mirror the website stop sequence: a simple settle back to idle over
    // ~5.5 s, then let the idle UI fade back in with the same "soft lift"
    // cubic-bezier used by the website's halo/mode-description text.
    withAnimation(.easeInOut(duration: 0.8)) {
      phaseTextOpacity = 0
      progressBarOpacity = 0
      countdownOpacity = 0
    }
    withAnimation(.easeInOut(duration: 5.5)) {
      sessionViewModel.haloScale = 0.45
      sessionViewModel.haloGlow = 0.2
      sessionViewModel.tempScalar = 0
      sessionViewModel.ambientIntensity = 0
      haloPulseAmount = 0
    }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 5_500_000_000)
      withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 1.2)) {
        startTextOpacity = 1
        modeAndDotsOpacity = 1
      }
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      sessionViewModel.phaseLabel = ""
      sessionViewModel.phaseCountdown = ""
      sessionViewModel.sessionProgress = nil
      countdownText = ""
    }
  }

  private func haloCenterY(in proxy: GeometryProxy) -> CGFloat {
    proxy.size.height * 0.5
  }

  private var currentModeIndex: Int {
    let ordered = orderedModes
    if let idx = ordered.firstIndex(where: { $0.id == selectedModeId }) {
      return idx
    }
    return 0
  }

  private func handleSwipe(translation: CGSize) {
    guard !sessionViewModel.isRunning, !isCountingDown else { return }
    guard abs(translation.width) > abs(translation.height) else { return }
    let ordered = orderedModes
    guard !ordered.isEmpty else { return }
    let count = ordered.count
    let current = currentModeIndex
    let nextIndex: Int
    if translation.width < -50 {
      nextIndex = (current + 1) % count
    } else if translation.width > 50 {
      nextIndex = (current - 1 + count) % count
    } else {
      return
    }
    let nextId = ordered[nextIndex].id
    withAnimation(.easeInOut(duration: 0.15)) { modeTextOpacity = 0 }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 150_000_000)
      selectedModeId = nextId
      withAnimation(.easeInOut(duration: 0.15)) { modeTextOpacity = 1 }
    }
  }

  private func modeSubtitle(_ mode: BreathingModeSpec) -> String {
    switch mode.id {
    case "box":
      return "4-4-4-4 box breathing"
    case "box_8888":
      return "8-8-8-8 box breathing"
    case "coherent_55":
      return "5-5 coherent"
    case "relax_478":
      return "4-7-8 relax"
    case "physiological_sigh_326":
      return "3-1-2-6 sigh"
    default:
      return mode.displayName.lowercased()
    }
  }

  private func modeDescription(_ mode: BreathingModeSpec) -> String? {
    switch mode.id {
    case "box":
      return "A steady, balanced rhythm to ground your attention."
    case "box_8888":
      return "A slower, deeper version for sustained calm."
    case "coherent_55":
      return "A smooth, continuous breath with no pauses, supporting balance and heart-rate variability."
    case "relax_478":
      return "Longer exhales to gently quiet the nervous system, often used for rest and sleep."
    case "physiological_sigh_326":
      return "A double inhale followed by a long release, helping the body settle into rapid calm."
    default:
      return nil
    }
  }
}

private struct DotIndicator: View {
  let count: Int
  let activeIndex: Int

  @State private var activeScale: Double = 1.0
  @State private var settleTask: Task<Void, Never>?

  var body: some View {
    HStack(spacing: 8) {
      ForEach(0..<count, id: \.self) { i in
        Circle()
          .fill(Color.white.opacity(i == activeIndex ? 1.0 : 0.3))
          .frame(width: 6, height: 6)
          .scaleEffect(i == activeIndex ? activeScale : 1.0)
      }
    }
    .onChange(of: activeIndex) { _, _ in pulseActive() }
  }

  /// On swipe to a new mode the active dot scales up to 1.3x over 200ms
  /// (decelerate), then settles back to 1x over 400ms.
  private func pulseActive() {
    settleTask?.cancel()
    withAnimation(.easeOut(duration: 0.20)) {
      activeScale = 1.30
    }
    settleTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 200_000_000)
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.40)) {
        activeScale = 1.0
      }
    }
  }
}

private struct ModeBackgroundSignature {
  let tempBias: Double
  let intensityLift: Double
  let tintRGB: RGB
  let tintOpacity: Double
}

private struct BreathingAmbientBackground: View {
  let tempScalar: Double
  let intensity: Double
  let modeTintRGB: RGB
  let modeTintOpacity: Double

  var body: some View {
    let center = ambientCenterColor(tempScalar: tempScalar, intensity: intensity)
    let edge = ambientEdgeColor(tempScalar: tempScalar, intensity: intensity)
    let tint = Color(
      red: modeTintRGB.r / 255.0,
      green: modeTintRGB.g / 255.0,
      blue: modeTintRGB.b / 255.0
    )

    RadialGradient(
      colors: [center, edge],
      center: .init(x: 0.35, y: 0.45),
      startRadius: 0,
      endRadius: 700
    )
    .overlay {
      ZStack {
        RadialGradient(
          colors: [
            tint.opacity(modeTintOpacity),
            tint.opacity(modeTintOpacity * 0.35),
            Color.clear,
          ],
          center: .init(x: 0.35, y: 0.42),
          startRadius: 0,
          endRadius: 560
        )

        ZStack {
          RadialGradient(
            colors: [Color.white.opacity(0.06), Color.clear],
            center: .init(x: 0.4, y: 0.4),
            startRadius: 0,
            endRadius: 460
          )
          RadialGradient(
            colors: [Color.black.opacity(0.55), Color.clear],
            center: .init(x: 0.6, y: 0.6),
            startRadius: 0,
            endRadius: 600
          )
        }
        .blendMode(.overlay)
        .opacity(0.35)
      }
    }
    .animation(.easeInOut(duration: 0.8), value: tempScalar)
    .animation(.easeInOut(duration: 0.8), value: intensity)
    .animation(.easeInOut(duration: 0.8), value: modeTintRGB.r)
    .animation(.easeInOut(duration: 0.8), value: modeTintRGB.g)
    .animation(.easeInOut(duration: 0.8), value: modeTintRGB.b)
    .animation(.easeInOut(duration: 0.8), value: modeTintOpacity)
  }

  private func ambientCenterColor(tempScalar: Double, intensity: Double) -> Color {
    let warmCenter = RGB(36, 28, 22)
    let coolCenter = RGB(20, 28, 46)
    let neutralCenter = RGB(14, 14, 16)
    let target = tempScalar > 0 ? warmCenter : coolCenter
    let blended = mix(from: neutralCenter, to: target, t: abs(tempScalar))
    return brighten(blended, amount: intensity)
  }

  private func ambientEdgeColor(tempScalar: Double, intensity: Double) -> Color {
    let warmEdge = RGB(14, 12, 10)
    let coolEdge = RGB(8, 12, 20)
    let neutralEdge = RGB(6, 6, 8)
    let target = tempScalar > 0 ? warmEdge : coolEdge
    let blended = mix(from: neutralEdge, to: target, t: abs(tempScalar))
    return brighten(blended, amount: intensity)
  }

  private func mix(from: RGB, to: RGB, t: Double) -> RGB {
    let tt = max(0, min(1, t))
    return RGB(
      from.r + (to.r - from.r) * tt,
      from.g + (to.g - from.g) * tt,
      from.b + (to.b - from.b) * tt
    )
  }

  private func brighten(_ rgb: RGB, amount: Double) -> Color {
    let offset = max(0, amount) * 18.0
    return Color(
      red: min(255.0, rgb.r + offset) / 255.0,
      green: min(255.0, rgb.g + offset) / 255.0,
      blue: min(255.0, rgb.b + offset) / 255.0
    )
  }
}

private struct RGB {
  let r: Double
  let g: Double
  let b: Double

  init(_ r: Double, _ g: Double, _ b: Double) {
    self.r = r
    self.g = g
    self.b = b
  }
}

private struct SubtleSessionProgressBar: View {
  let progress: Double

  var body: some View {
    GeometryReader { proxy in
      let clamped = max(0, min(1, progress))
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.white.opacity(0.08))
        Capsule()
          .fill(Color.white.opacity(0.42))
          .frame(width: proxy.size.width * clamped)
      }
      .frame(height: 1.5)
      .accessibilityLabel("Session progress")
    }
    .frame(height: 1.5)
  }
}

