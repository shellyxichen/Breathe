/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// PhotoPreviewView.swift
//
// Reusable halo visual for breathing sessions.
//

import SwiftUI

struct HaloView: View {
  let scale: Double
  let glow: Double
  let tempScalar: Double
  let phaseLabel: String
  let phaseCountdown: String

  var body: some View {
    let (_, glowColor) = colors(for: tempScalar)
    let clampedGlow = max(0, min(1, glow))
    let outerGlow = 140 * clampedGlow
    let midGlow = 45 * clampedGlow

    ZStack {
      Circle()
        .fill(Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.98))
        .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
        .shadow(color: Color(red: 250.0 / 255.0, green: 235.0 / 255.0, blue: 1.0, opacity: 0.4), radius: 20, x: 0, y: 0)
        .shadow(color: Color(red: 200.0 / 255.0, green: 190.0 / 255.0, blue: 1.0, opacity: 0.3), radius: midGlow, x: 0, y: 0)
        .shadow(color: glowColor.opacity(0.90), radius: outerGlow, x: 0, y: 0)
        .scaleEffect(max(0.1, scale))

      if !phaseLabel.isEmpty || !phaseCountdown.isEmpty {
        VStack(spacing: 8) {
          Text(phaseLabel.uppercased())
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.88))

          Text(phaseCountdown)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.50))
            .monospacedDigit()
        }
      }
    }
    .frame(width: 280, height: 280)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(phaseLabel) \(phaseCountdown)")
  }

  private func colors(for tempScalar: Double) -> (Color, Color) {
    let t = min(1, abs(tempScalar))
    let warm = RGBA(255, 190, 140, 0.26)
    let cool = RGBA(120, 170, 255, 0.22)
    let neutral = RGBA(40, 40, 40, 0.20)

    let warmGlow = RGBA(255, 160, 110, 0.35)
    let coolGlow = RGBA(120, 170, 255, 0.35)
    let neutralGlow = RGBA(250, 250, 250, 0.25)

    let base = tempScalar > 0 ? warm : cool
    let glowBase = tempScalar > 0 ? warmGlow : coolGlow

    return (blend(neutral, base, t).color, blend(neutralGlow, glowBase, t).color)
  }
}

private struct RGBA: Sendable {
  let r: Double
  let g: Double
  let b: Double
  let a: Double

  init(_ r: Double, _ g: Double, _ b: Double, _ a: Double) {
    self.r = r
    self.g = g
    self.b = b
    self.a = a
  }

  var color: Color {
    Color(
      red: r / 255.0,
      green: g / 255.0,
      blue: b / 255.0,
      opacity: a
    )
  }
}

private func blend(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
  let tt = max(0, min(1, t))
  return RGBA(
    a.r + (b.r - a.r) * tt,
    a.g + (b.g - a.g) * tt,
    a.b + (b.b - a.b) * tt,
    a.a + (b.a - a.a) * tt
  )
}
