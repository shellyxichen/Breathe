/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// RegistrationView.swift
//
// Background view that handles callbacks from the Meta AI mobile app during
// DAT SDK registration and permission flows. This invisible view processes deep links
// that complete the OAuth authorization process initiated by the DAT SDK.
//

#if false // GLASSES_SDK: temporarily disabled — re-enable when glasses capability is ready

import MWDATCore
import SwiftUI

struct RegistrationView: View {
  @ObservedObject var viewModel: WearablesViewModel

  var body: some View {
    EmptyView()
      .onOpenURL { url in
        guard
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
        else {
          return
        }
        Task {
          do {
            _ = try await Wearables.shared.handleUrl(url)
          } catch let error as RegistrationError {
            viewModel.showError(error.description)
          } catch {
            viewModel.showError("Unknown error: \(error.localizedDescription)")
          }
        }
      }
  }
}

#endif // GLASSES_SDK
