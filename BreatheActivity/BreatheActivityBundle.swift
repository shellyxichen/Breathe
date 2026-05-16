/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// BreatheActivityBundle.swift
//
// Entry point for the BreatheActivity widget extension. The bundle hosts
// the Live Activity that mirrors a running breathing session.
//

import SwiftUI
import WidgetKit

@main
struct BreatheActivityBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 16.2, *) {
      BreatheLiveActivity()
    }
  }
}
