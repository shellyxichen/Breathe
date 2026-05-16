/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// CardView.swift
//
// Reusable container component that provides consistent card styling throughout the app.
//

import SwiftUI

struct CardView<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .background(Color(.systemBackground))
    .cornerRadius(12)
    .shadow(
      color: Color.black.opacity(0.1),
      radius: 4,
      x: 0,
      y: 2
    )
  }
}

struct CalmBackground: View {
  var body: some View {
    RadialGradient(
      colors: [Color(red: 0.11, green: 0.13, blue: 0.19), Color(red: 0.04, green: 0.05, blue: 0.08)],
      center: .init(x: 0.35, y: 0.45),
      startRadius: 0,
      endRadius: 700
    )
    .overlay {
      LinearGradient(
        colors: [Color.white.opacity(0.05), Color.black.opacity(0.45)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .blendMode(.overlay)
      .opacity(0.35)
    }
  }
}

struct PrimaryCalmButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.white.opacity(configuration.isPressed ? 0.78 : 0.92))
      .background(
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.14))
          .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
              .stroke(Color.white.opacity(0.22), lineWidth: 1)
          )
      )
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
  }
}
