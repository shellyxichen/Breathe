/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// HomeScreenView.swift
//
// Launcher screen shown every time the app opens.
// Displays an inspirational quote with staggered fade-in,
// then signals completion so the parent can transition to the breathing controls.
//

import SwiftUI

struct HomeScreenView: View {
  var onComplete: () -> Void = {}

  @State private var isLineOneVisible: Bool = false
  @State private var isLineTwoVisible: Bool = false

  var body: some View {
    ZStack {
      CalmBackground()
        .ignoresSafeArea()

      VStack(spacing: 16) {
        Spacer()

        VStack(spacing: 10) {
          Text("What does it mean to 'do nothing'?")
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .multilineTextAlignment(.center)
            .opacity(isLineOneVisible ? 1 : 0)
            .offset(y: isLineOneVisible ? 0 : 8)
            .animation(.easeInOut(duration: 1.1), value: isLineOneVisible)

          Text("Just simply breathe.")
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .multilineTextAlignment(.center)
            .opacity(isLineTwoVisible ? 1 : 0)
            .offset(y: isLineTwoVisible ? 0 : 8)
            .animation(.easeInOut(duration: 1.1), value: isLineTwoVisible)
        }
        .padding(.horizontal, 24)

        Spacer()

        #if false // GLASSES_SDK: temporarily disabled — connect glasses CTA
        VStack(spacing: 12) {
          Button {
            viewModel.connectGlasses()
          } label: {
            Text("Connect glasses")
              .font(.system(.body, design: .rounded).weight(.semibold))
              .frame(maxWidth: .infinity)
              .frame(height: 54)
          }
          .buttonStyle(BreathingActionButtonStyle(isPrimary: false))
          .disabled(viewModel.isConnecting)

          Text("You'll be redirected to the Meta AI app.")
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .opacity(isCTAVisible ? 1 : 0)
        .offset(y: isCTAVisible ? 0 : 8)
        .animation(.easeInOut(duration: 1.0), value: isCTAVisible)
        .padding(.horizontal, 24)
        #endif // GLASSES_SDK
      }
      .padding(.vertical, 32)
    }
    .onAppear {
      isLineOneVisible = false
      isLineTwoVisible = false
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isLineOneVisible = true
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        isLineTwoVisible = true
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        onComplete()
      }
    }
  }
}
