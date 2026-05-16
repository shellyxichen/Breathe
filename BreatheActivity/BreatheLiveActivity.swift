/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// BreatheLiveActivity.swift
//
// Live Activity surface for an in-progress breathing session. Renders on
// the Lock Screen and in the Dynamic Island. Mirrors the state owned by
// SessionViewModel via BreathingActivityAttributes.
//
// Visual model:
//   ┌────────────────────────────────────────────────┐
//   │                                                │
//   │   ●                          INHALE  04        │
//   │  stop                                          │
//   │                                                │
//   └────────────────────────────────────────────────┘
//   Left:  soft circular stop button (LiveActivityIntent)
//   Right: small phase label (Inhale / Hold / Exhale) sitting immediately
//          left of the large 2-digit padded countdown, baseline-aligned.
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 16.2, *)
struct BreatheLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BreathingActivityAttributes.self) { context in
      LockScreenView(
        attributes: context.attributes,
        state: context.state
      )
      .activityBackgroundTint(Color.black.opacity(0.55))
      .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 10) {
            StopButton(size: 40)
            PhaseLabel(text: context.state.phaseLabel, font: .caption.weight(.semibold))
          }
          .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          CountdownText(
            seconds: context.state.phaseCountdownSec,
            font: .system(size: 44, weight: .semibold, design: .rounded).monospacedDigit()
          )
          .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.bottom) {
          EmptyView()
        }
      } compactLeading: {
        ProgressRing(progress: context.state.sessionProgress, lineWidth: 2.4)
          .frame(width: 18, height: 18)
          .padding(.leading, 2)
      } compactTrailing: {
        CountdownText(
          seconds: context.state.phaseCountdownSec,
          font: .system(.body, design: .rounded).monospacedDigit().weight(.semibold)
        )
      } minimal: {
        ProgressRing(progress: context.state.sessionProgress, lineWidth: 2.2)
          .frame(width: 16, height: 16)
      }
      .widgetURL(URL(string: "breathe://session"))
      .keylineTint(Color.white.opacity(0.4))
    }
  }
}

// MARK: - Lock Screen

@available(iOS 16.2, *)
private struct LockScreenView: View {
  let attributes: BreathingActivityAttributes
  let state: BreathingActivityAttributes.ContentState

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      StopButton(size: 56)

      Spacer(minLength: 0)

      HStack(alignment: .lastTextBaseline, spacing: 10) {
        PhaseLabel(text: state.phaseLabel, font: .subheadline.weight(.semibold))
        CountdownText(
          seconds: state.phaseCountdownSec,
          font: .system(size: 56, weight: .semibold, design: .rounded).monospacedDigit()
        )
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }
}

// MARK: - Components

@available(iOS 16.2, *)
private struct StopButton: View {
  let size: CGFloat

  var body: some View {
    // Live Activity Intent buttons need iOS 17+. On 16.2/16.3 the button
    // falls back to a non-interactive glyph (still better than nothing).
    if #available(iOS 17.0, *) {
      Button(intent: StopBreatheSessionIntent()) {
        StopGlyph(size: size)
      }
      .buttonStyle(.plain)
    } else {
      StopGlyph(size: size)
    }
  }
}

private struct StopGlyph: View {
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(Color.white.opacity(0.18))

      RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
        .fill(Color.white)
        .frame(width: size * 0.34, height: size * 0.34)
    }
    .frame(width: size, height: size)
    .accessibilityLabel("Stop session")
  }
}

private struct PhaseLabel: View {
  let text: String
  let font: Font

  var body: some View {
    Text(text.isEmpty ? " " : text)
      .font(font)
      .foregroundStyle(.white.opacity(0.7))
      .textCase(.uppercase)
      .tracking(0.6)
      .lineLimit(1)
  }
}

private struct CountdownText: View {
  let seconds: Double
  let font: Font

  var body: some View {
    // Instant digit snap — no cross-fade, no morph. Audio-visual sync
    // matters more than smooth typography here. Anything other than
    // .identity causes a perceptible lag behind the audio beat because
    // it stacks on top of ActivityKit's own propagation latency.
    Text(formattedCountdown(seconds))
      .font(font)
      .foregroundStyle(.white)
      .contentTransition(.identity)
  }
}

/// Apple-Timer-style ring used in the Dynamic Island compact/minimal pills.
/// Fills clockwise from the 12 o'clock position; the unfilled portion shows
/// a faint track so it still reads as a ring at 100% progress.
///
/// We `inset(by: lineWidth / 2)` because `stroke` centers the line on the
/// path — without the inset, half the stroke renders outside the frame and
/// gets clipped by the Dynamic Island pill bounds.
private struct ProgressRing: View {
  let progress: Double
  let lineWidth: CGFloat

  var body: some View {
    let clamped = max(0.0, min(1.0, progress))
    let inset = lineWidth / 2

    ZStack {
      Circle()
        .inset(by: inset)
        .stroke(Color.white.opacity(0.22), lineWidth: lineWidth)

      Circle()
        .inset(by: inset)
        .trim(from: 0, to: max(0.001, clamped))
        .stroke(
          Color.white,
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .animation(.linear(duration: 0.5), value: clamped)
    }
    .padding(0.5)
  }
}

private func formattedCountdown(_ seconds: Double) -> String {
  // Per-phase countdown is a small integer (typically 1–8 s). Pad to 2
  // digits to match Apple's Timer Live Activity rhythm: 04 → 03 → 02 → 01.
  let s = max(0, Int(seconds.rounded(.up)))
  return String(format: "%02d", s)
}
