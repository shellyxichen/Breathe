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
  var phaseTextOpacity: Double = 1
  var pulseScale: Double = 0
  var pressGlowBoost: Double = 0
  var pressRimAmount: Double = 0

  private static let coreDiameter: CGFloat = 280
  private static let glowDiameter: CGFloat = 280 * 2.4

  // 13-stop Gaussian falloff (sigma ~ 0.35) — smooth bloom, no visible banding.
  private static let gaussianStops: [(loc: Double, alpha: Double)] = [
    (0.00, 1.000), (0.083, 0.920), (0.167, 0.800), (0.250, 0.650),
    (0.333, 0.500), (0.417, 0.360), (0.500, 0.240), (0.583, 0.150),
    (0.667, 0.085), (0.750, 0.045), (0.833, 0.020), (0.917, 0.007),
    (1.000, 0.000),
  ]

  var body: some View {
    let glowColor = glowColor(for: tempScalar)
    let rimColor = rimColor(for: tempScalar)
    let clampedGlow = max(0, min(1, glow))
    let glowAlpha = 0.45 * clampedGlow * (1 + pressGlowBoost)
    let effectiveScale = max(0.1, scale) * (1 + pulseScale)
    let rimWidth: CGFloat = 1.5 + 1.0 * pressRimAmount
    let rimAlpha = 0.25 + 0.25 * pressRimAmount

    ZStack {
      ZStack {
        Circle()
          .fill(
            RadialGradient(
              gradient: Gradient(stops: Self.gaussianStops.map { stop in
                Gradient.Stop(
                  color: glowColor.opacity(stop.alpha * glowAlpha),
                  location: stop.loc
                )
              }),
              center: .center,
              startRadius: 0,
              endRadius: Self.glowDiameter / 2
            )
          )
          .frame(width: Self.glowDiameter, height: Self.glowDiameter)
          .blendMode(.plusLighter)
          .allowsHitTesting(false)

        Circle()
          .fill(Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.98))
          .overlay(
            Circle().stroke(rimColor.opacity(rimAlpha), lineWidth: rimWidth)
          )
          .frame(width: Self.coreDiameter, height: Self.coreDiameter)
      }
      .scaleEffect(effectiveScale)

      VStack(spacing: 8) {
        Text(phaseLabel.uppercased())
          .font(.system(size: 14, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.88))

        Text(phaseCountdown)
          .font(.system(size: 20, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.50))
          .monospacedDigit()
      }
      .opacity(phaseTextOpacity)
    }
    .frame(width: Self.coreDiameter, height: Self.coreDiameter)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(phaseLabel) \(phaseCountdown)")
  }

  private func glowColor(for tempScalar: Double) -> Color {
    let t = min(1, abs(tempScalar))
    let warmGlow = RGBA(255, 160, 110, 1.0)
    let coolGlow = RGBA(120, 170, 255, 1.0)
    let neutralGlow = RGBA(250, 250, 250, 1.0)
    let target = tempScalar > 0 ? warmGlow : coolGlow
    return blend(neutralGlow, target, t).color
  }

  private func rimColor(for tempScalar: Double) -> Color {
    let t = min(1, abs(tempScalar))
    let warm = RGBA(255, 190, 140, 1.0)
    let cool = RGBA(150, 190, 255, 1.0)
    let neutral = RGBA(255, 255, 255, 1.0)
    let target = tempScalar > 0 ? warm : cool
    return blend(neutral, target, t).color
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
