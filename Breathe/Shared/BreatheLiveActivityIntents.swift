/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// BreatheLiveActivityIntents.swift
//
// Shared between the Breathe app and the BreatheActivity widget extension.
// Hosts the LiveActivityIntent for the Lock Screen stop button, plus the
// notification name the app process uses to relay it to SessionViewModel.
//
// How the Stop button works:
//   1. User taps the stop glyph in the Live Activity (Lock Screen or
//      Dynamic Island).
//   2. iOS executes StopBreatheSessionIntent.perform() *in the app's
//      process* (LiveActivityIntent runs in-app, not in the widget
//      extension). The app may be foreground, background, or even
//      previously suspended — iOS wakes it.
//   3. perform() posts .breatheStopSessionRequested on NotificationCenter.
//   4. SessionViewModel (which is observing) calls stop() on the main
//      actor, which ends both the session and the activity.
//

import AppIntents
import Foundation

@available(iOS 17.0, *)
public struct StopBreatheSessionIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "Stop Breathing Session"
  public static var description = IntentDescription("Ends the current breathing session.")

  public init() {}

  public func perform() async throws -> some IntentResult {
    await MainActor.run {
      NotificationCenter.default.post(
        name: .breatheStopSessionRequested,
        object: nil
      )
    }
    return .result()
  }
}

public extension Notification.Name {
  static let breatheStopSessionRequested = Notification.Name("BreatheStopSessionRequested")
}
