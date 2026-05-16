/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// BreatheApp.swift
//
// Main entry point for the Breathe companion app.
//

import Foundation
// import MWDATCore // GLASSES_SDK: temporarily disabled
import SwiftUI

@main
struct BreatheApp: App {

  #if false // GLASSES_SDK: temporarily disabled — re-enable when glasses capability is ready
  @StateObject private var wearablesViewModel: WearablesViewModel

  init() {
    do {
      try Wearables.configure()
    } catch {
      #if DEBUG
      NSLog("[Breathe] Failed to configure Wearables SDK: \(error)")
      #endif
    }
    let wearables = Wearables.shared
    self._wearablesViewModel = StateObject(wrappedValue: WearablesViewModel(wearables: wearables))
  }
  #endif // GLASSES_SDK

  var body: some Scene {
    WindowGroup {
      // GLASSES_SDK: temporarily disabled — re-enable modifiers and RegistrationView below
      // when glasses capability is ready:
      //   MainAppView()
      //     .alert("Error", isPresented: $wearablesViewModel.showError) {
      //       Button("OK") { wearablesViewModel.dismissError() }
      //     } message: {
      //       Text(wearablesViewModel.errorMessage)
      //     }
      //   RegistrationView(viewModel: wearablesViewModel)
      MainAppView()
    }
  }
}
