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
  @Binding var selectedTimerOption: BreathingTimerOption
  let modesLoadError: String?
  @State private var startButtonTopY: CGFloat = 0
  @State private var countdownText: String = ""
  @State private var isCountingDown = false

  var body: some View {
    ZStack {
      BreathingAmbientBackground(
        tempScalar: displayedTempScalar,
        intensity: displayedAmbientIntensity
      )
        .ignoresSafeArea()

      GeometryReader { proxy in
        HaloView(
          scale: displayedHaloScale,
          glow: displayedHaloGlow,
          tempScalar: displayedTempScalar,
          phaseLabel: displayedPhaseLabel,
          phaseCountdown: displayedPhaseCountdown
        )
        .position(x: proxy.size.width * 0.5, y: haloCenterY(in: proxy))
      }
      .ignoresSafeArea()
      .allowsHitTesting(false)

      if !countdownText.isEmpty {
        GeometryReader { proxy in
          Text(countdownText)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.50))
            .position(x: proxy.size.width * 0.5, y: haloCenterY(in: proxy))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
      }

      VStack(spacing: 12) {
        if let error = modesLoadError {
          Text("Unable to load modes: \(error)")
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.white.opacity(0.58))
            .multilineTextAlignment(.center)
        }

        if !sessionViewModel.isRunning && !isCountingDown, let desc = selectedMode.flatMap({ modeDescription($0) }) {
          Group {
            if let url = desc.url {
              Link(destination: url) {
                (Text(desc.text) + Text(" ") + Text(Image(systemName: "info.circle")))
                  .foregroundStyle(.white.opacity(0.6))
              }
              .tint(.white.opacity(0.6))
            } else {
              Text(desc.text)
                .foregroundStyle(.white.opacity(0.6))
            }
          }
          .font(.system(.subheadline, design: .rounded))
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 8)
          .padding(.bottom, 36)
          .transition(.opacity)
        }

        Button {
          toggleSession()
        } label: {
          Text(sessionViewModel.isRunning || isCountingDown ? "Stop" : "Start")
            .font(.system(.body, design: .rounded).weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .background(
          GeometryReader { geometry in
            Color.clear
              .preference(
                key: StartButtonTopPreferenceKey.self,
                value: geometry.frame(in: .named("sessionRoot")).minY
              )
          }
        )
        .buttonStyle(BreathingActionButtonStyle(isPrimary: !sessionViewModel.isRunning && !isCountingDown))
        .disabled(selectedMode == nil)

        HStack(spacing: 10) {
          pickerTile {
            Menu {
              ForEach(orderedModes.reversed()) { mode in
                Button(modeMenuText(mode)) {
                  selectedModeId = mode.id
                }
              }
              Divider()
                .padding(.vertical, -6)
              Text("Mode")
            } label: {
              menuLabel(text: selectedMode.map(modeMenuText) ?? "Select mode")
            }
          }
          .frame(maxWidth: .infinity)

          pickerTile {
            Menu {
              ForEach(orderedTimerOptions.reversed()) { option in
                Button(option.displayText) {
                  selectedTimerOption = option
                }
              }
              Divider()
                .padding(.vertical, -6)
              Text("Timer")
            } label: {
              menuLabel(text: selectedTimerOption.displayText)
            }
          }
          .frame(width: 118, alignment: .leading)
        }
        .opacity(sessionViewModel.isRunning || isCountingDown ? 0 : 1)
        .allowsHitTesting(!sessionViewModel.isRunning && !isCountingDown)
        .animation(.easeInOut(duration: 0.24), value: sessionViewModel.isRunning)
        .animation(.easeInOut(duration: 0.24), value: isCountingDown)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 0)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

      if sessionViewModel.isRunning, let progress = sessionViewModel.sessionProgress {
        SubtleSessionProgressBar(progress: progress)
          .padding(.horizontal, 24)
          .padding(.bottom, 1)
          .opacity(0.42)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .transition(.opacity)
      }
    }
    .coordinateSpace(name: "sessionRoot")
    .onPreferenceChange(StartButtonTopPreferenceKey.self) { value in
      if let value {
        startButtonTopY = value
      }
    }
  }

  private var selectedMode: BreathingModeSpec? {
    if let mode = modes.first(where: { $0.id == selectedModeId }) { return mode }
    return modes.first
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

  private var orderedTimerOptions: [BreathingTimerOption] {
    [.sec30, .sec60, .sec120, .sec180, .sec300, .sec600, .infinity]
  }

  private var displayedHaloScale: Double {
    sessionViewModel.isRunning ? sessionViewModel.haloScale : 0.3
  }

  private var displayedHaloGlow: Double {
    sessionViewModel.isRunning ? sessionViewModel.haloGlow : 0.2
  }

  private var displayedTempScalar: Double {
    sessionViewModel.isRunning ? sessionViewModel.tempScalar : 0
  }

  private var displayedPhaseLabel: String {
    sessionViewModel.isRunning ? sessionViewModel.phaseLabel : ""
  }

  private var displayedPhaseCountdown: String {
    sessionViewModel.isRunning ? sessionViewModel.phaseCountdown : ""
  }

  private var displayedAmbientIntensity: Double {
    sessionViewModel.isRunning ? sessionViewModel.ambientIntensity : 0
  }

  private func toggleSession() {
    if sessionViewModel.isRunning {
      sessionViewModel.stop()
      return
    }
    if isCountingDown {
      cancelCountdown()
      return
    }
    guard let spec = selectedMode else { return }
    startCountdown(spec: spec)
  }

  private func cancelCountdown() {
    isCountingDown = false
    withAnimation(.easeInOut(duration: 0.2)) { countdownText = "" }
  }

  private func startCountdown(spec: BreathingModeSpec) {
    isCountingDown = true
    Task { @MainActor in
      for text in ["3", "2", "1"] {
        withAnimation(.easeInOut(duration: 0.2)) { countdownText = text }
        sessionViewModel.playCountdownTick()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
      withAnimation(.easeInOut(duration: 0.2)) { countdownText = "Go" }
      sessionViewModel.playCountdownGo()
      try? await Task.sleep(nanoseconds: 600_000_000)
      withAnimation(.easeInOut(duration: 0.2)) { countdownText = "" }
      isCountingDown = false
      sessionViewModel.start(spec: spec, durationSec: selectedTimerOption.durationSec)
    }
  }

  private func haloCenterY(in proxy: GeometryProxy) -> CGFloat {
    guard startButtonTopY > 0 else { return proxy.size.height * 0.5 }
    return (statusBarBottomInset + haloTopPadding + startButtonTopY) * 0.5
  }

  private var haloTopPadding: CGFloat { 64 }

  private var statusBarBottomInset: CGFloat {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .safeAreaInsets.top ?? 0
  }

  @ViewBuilder
  private func pickerTile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 16)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.white.opacity(0.08))
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    )
  }

  private func menuLabel(text: String) -> some View {
    HStack(spacing: 8) {
      Text(text)
        .font(.system(.subheadline, design: .rounded))
        .foregroundStyle(.white.opacity(0.88))
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 4)
      Image(systemName: "chevron.down")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.62))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  private func modeDescription(_ mode: BreathingModeSpec) -> (text: String, url: URL?)? {
    switch mode.id {
    case "box":
      return ("Equal inhale, hold, exhale, hold for 4 seconds — a steady rhythm to ground your attention.", nil)
    case "box_8888":
      return ("Equal inhale, hold, exhale, hold for 8 seconds — a slower, deeper box breath for sustained calm.", nil)
    case "coherent_55":
      return (
        "Inhale 5s, exhale 5s — a smooth, continuous breath with no pauses, supporting balance and heart rate variability.", 
        URL(string: "https://www.nature.com/articles/s41598-023-49279-8")
      )
    case "relax_478":
      return (
        "Inhale 4s, hold 7s, exhale 8s — longer exhales to gently calm the mind and quiet the nervous system, by Dr. Andrew Weil.",
        URL(string: "https://nursing.rutgers.edu/wp-content/uploads/2020/07/Dr.-Weil-4-7-8-Breathing-Exercise.pdf")
      )
    case "physiological_sigh_326":
      return (
        "Double inhale 3s, hold 2s, long exhale 6s — a rapid breath to offload carbon dioxide, by Dr. Huberman.",
        URL(string: "https://www.hubermanlab.com/newsletter/breathwork-protocols-for-health-focus-stress")
      )
    default:
      return nil
    }
  }

  private func modeMenuText(_ mode: BreathingModeSpec) -> String {
    switch mode.id {
    case "box":
      return "Box breathing"
    case "box_8888":
      return "Box breathing (deep)"
    case "coherent_55":
      return "Coherent breathing"
    case "relax_478":
      return "Relax breathing"
    case "physiological_sigh_326":
      return "Physiological sigh"
    default:
      return mode.displayName
    }
  }
}

private struct StartButtonTopPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat? = nil

  static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
    if let next = nextValue() {
      value = next
    }
  }
}

private struct BreathingAmbientBackground: View {
  let tempScalar: Double
  let intensity: Double

  var body: some View {
    let center = ambientCenterColor(tempScalar: tempScalar, intensity: intensity)
    let edge = ambientEdgeColor(tempScalar: tempScalar, intensity: intensity)

    RadialGradient(
      colors: [center, edge],
      center: .init(x: 0.35, y: 0.45),
      startRadius: 0,
      endRadius: 700
    )
    .overlay {
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
    .animation(.easeInOut(duration: 0.8), value: tempScalar)
    .animation(.easeInOut(duration: 0.8), value: intensity)
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

struct BreathingActionButtonStyle: ButtonStyle {
  let isPrimary: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.white.opacity(configuration.isPressed ? 0.86 : 0.92))
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                isPrimary
                  ? Color(red: 130.0 / 255.0, green: 180.0 / 255.0, blue: 1.0).opacity(0.42)
                  : Color.white.opacity(0.20),
                isPrimary
                  ? Color(red: 120.0 / 255.0, green: 150.0 / 255.0, blue: 1.0).opacity(0.18)
                  : Color.white.opacity(0.06),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(
                isPrimary
                  ? Color(red: 140.0 / 255.0, green: 180.0 / 255.0, blue: 1.0).opacity(0.55)
                  : Color.white.opacity(0.22),
                lineWidth: 1
              )
          )
      )
      .shadow(
        color: isPrimary
          ? Color(red: 80.0 / 255.0, green: 130.0 / 255.0, blue: 1.0).opacity(0.28)
          : Color(red: 15.0 / 255.0, green: 20.0 / 255.0, blue: 32.0 / 255.0).opacity(0.32),
        radius: isPrimary ? 24 : 22,
        x: 0,
        y: isPrimary ? 10 : 12
      )
      .shadow(
        color: Color.white.opacity(isPrimary ? 0.0 : 0.35),
        radius: isPrimary ? 0 : 0.5,
        x: 0,
        y: -1
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color.white.opacity(isPrimary ? 0.45 : 0.35), lineWidth: 1)
          .blur(radius: 0.2)
      )
      .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
  }
}
