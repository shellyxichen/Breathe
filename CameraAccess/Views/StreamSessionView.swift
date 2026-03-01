/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionView.swift
//
//

import BreathingSessionEngine
import SwiftUI

struct StreamSessionView: View {
  @ObservedObject var sessionViewModel: SessionViewModel
  let modes: [BreathingModeSpec]
  @Binding var selectedModeId: String
  @Binding var selectedTimerOption: BreathingTimerOption
  let modesLoadError: String?

  @State private var showLauncher = true

  init(
    sessionViewModel: SessionViewModel,
    modes: [BreathingModeSpec],
    selectedModeId: Binding<String>,
    selectedTimerOption: Binding<BreathingTimerOption>,
    modesLoadError: String?
  ) {
    self.sessionViewModel = sessionViewModel
    self.modes = modes
    self._selectedModeId = selectedModeId
    self._selectedTimerOption = selectedTimerOption
    self.modesLoadError = modesLoadError
  }

  var body: some View {
    ZStack {
      NonStreamView(
        sessionViewModel: sessionViewModel,
        modes: modes,
        selectedModeId: $selectedModeId,
        selectedTimerOption: $selectedTimerOption,
        modesLoadError: modesLoadError
      )

      if showLauncher {
        HomeScreenView {
          withAnimation(.easeInOut(duration: 1)) {
            showLauncher = false
          }
        }
        .transition(.opacity)
        .zIndex(1)
      }
    }

    #if false // GLASSES_SDK: temporarily disabled — original glass-gated navigation
    // Previously the view switched between HomeScreenView (not connected)
    // and NonStreamView (connected) based on wearablesVM.isRegistered.
    //
    // @ObservedObject var wearablesVM: WearablesViewModel
    //
    // var body: some View {
    //   ZStack {
    //     if isConnected {
    //       NonStreamView(...)
    //         .transition(.opacity)
    //     } else {
    //       HomeScreenView(viewModel: wearablesVM)
    //         .onAppear { sessionViewModel.stop() }
    //         .transition(.opacity)
    //     }
    //   }
    //   .animation(.easeInOut(duration: 0.35), value: isConnected)
    // }
    //
    // private var isConnected: Bool {
    //   #if DEBUG
    //   return wearablesVM.isRegistered || wearablesVM.hasMockDevice
    //   #else
    //   return wearablesVM.isRegistered
    //   #endif
    // }
    #endif // GLASSES_SDK
  }
}
