/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamView.swift
//
// Breathing session screen: halo + progress bar + stop.
//

import SwiftUI

struct StreamView: View {
  @ObservedObject var viewModel: SessionViewModel

  var body: some View {
    ZStack {
      CalmBackground()
        .ignoresSafeArea()

      VStack(spacing: 16) {
        Spacer()

        HaloView(
          scale: viewModel.haloScale,
          glow: viewModel.haloGlow,
          tempScalar: viewModel.tempScalar,
          phaseLabel: viewModel.phaseLabel,
          phaseCountdown: viewModel.phaseCountdown
        )

        Spacer()

        VStack(spacing: 14) {
          if let progress = viewModel.sessionProgress {
            SessionProgressBar(progress: progress)
              .padding(.horizontal, 24)
          }

          Button {
            viewModel.stop()
          } label: {
            Text("Stop")
              .font(.system(.body, design: .rounded).weight(.semibold))
              .frame(maxWidth: .infinity)
              .frame(height: 54)
          }
          .buttonStyle(PrimaryCalmButtonStyle())
          .padding(.horizontal, 24)
        }
        .padding(.bottom, 18)
      }
    }
    .onDisappear {
      viewModel.stop()
    }
  }
}

private struct SessionProgressBar: View {
  let progress: Double

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(Color.white.opacity(0.10))
        Rectangle()
          .fill(Color.white.opacity(0.75))
          .frame(width: width * CGFloat(max(0, min(1, progress))))
      }
      .frame(height: 2)
      .clipShape(Capsule())
      .accessibilityLabel("Session progress")
    }
    .frame(height: 2)
  }
}
