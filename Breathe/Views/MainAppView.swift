/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// MainAppView.swift
//
// Root navigation for Breathe.
//

import BreathingSessionEngine
import SwiftUI

struct MainAppView: View {
  @StateObject private var sessionViewModel = SessionViewModel()

  @State private var modes: [BreathingModeSpec] = []
  @State private var selectedModeId: String = "box"
  @State private var modesLoadError: String?

  #if false // GLASSES_SDK: temporarily disabled
  @ObservedObject private var wearablesViewModel: WearablesViewModel

  init(viewModel: WearablesViewModel) {
    self.wearablesViewModel = viewModel
  }
  #endif // GLASSES_SDK

  var body: some View {
    StreamSessionView(
      sessionViewModel: sessionViewModel,
      modes: modes,
      selectedModeId: $selectedModeId,
      modesLoadError: modesLoadError
    )
    .task {
      // Load mode catalog up front (fast — bundle JSON read), but defer cue
      // priming until after the launch HomeScreen finishes. Initializing the
      // AVAudioEngine + CHHapticEngine during the very first frame can race
      // with iOS's launch transitions and leave the launch screen blank if
      // the audio engine throws (debugger pauses on the exception → main
      // thread can't render). StreamSessionView calls primeCues() once the
      // HomeScreen intro completes.
      await loadModesIfNeeded()
    }
  }

  private func loadModesIfNeeded() async {
    if !modes.isEmpty || modesLoadError != nil { return }
    do {
      let loaded = try BreathingModeCatalog.loadAll()
      let order = ["box", "box_8888", "coherent_55", "relax_478", "physiological_sigh_326"]
      modes = loaded.sorted {
        let a = order.firstIndex(of: $0.id) ?? Int.max
        let b = order.firstIndex(of: $1.id) ?? Int.max
        return a < b
      }
      if !modes.contains(where: { $0.id == selectedModeId }), let first = modes.first {
        selectedModeId = first.id
      }
    } catch {
      modesLoadError = error.localizedDescription
    }
  }
}
