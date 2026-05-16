/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// BreathingActivityController.swift
//
// Thin wrapper around ActivityKit that mirrors the running breathing
// session to the Lock Screen + Dynamic Island. Owned by SessionViewModel.
//
// Update cadence policy:
//   - Phase changes are always pushed (.immediate so the timer/label flips
//     without lag).
//   - Within a phase we throttle to ~2 Hz, which is plenty for the pulsing
//     circle and the countdown — anything faster gets coalesced by the
//     system anyway and just wastes budget.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class BreathingActivityController {
  private static let intraPhaseUpdateInterval: TimeInterval = 0.5

#if canImport(ActivityKit)
  private var activity: Activity<BreathingActivityAttributes>?
  private var lastPhaseLabel: String = ""
  private var lastUpdateAt: TimeInterval = 0
#endif

  var isAvailable: Bool {
#if canImport(ActivityKit)
    if #available(iOS 16.2, *) {
      return ActivityAuthorizationInfo().areActivitiesEnabled
    }
#endif
    return false
  }

  func start(
    modeName: String,
    modeSubtitle: String,
    initial: BreathingActivityContent
  ) {
#if canImport(ActivityKit)
    guard #available(iOS 16.2, *) else {
      #if DEBUG
      NSLog("[Breathe] Live Activity skipped: iOS < 16.2")
      #endif
      return
    }
    let authInfo = ActivityAuthorizationInfo()
    guard authInfo.areActivitiesEnabled else {
      #if DEBUG
      NSLog("[Breathe] Live Activity skipped: areActivitiesEnabled=false. Check Settings > Breathe > Allow Live Activities and active Focus modes.")
      #endif
      return
    }

    end(finalState: nil)

    let attributes = BreathingActivityAttributes(
      modeName: modeName,
      modeSubtitle: modeSubtitle,
      startedAt: Date()
    )
    let state = initial.asState()
    let content = ActivityContent(state: state, staleDate: nil)

    do {
      activity = try Activity.request(
        attributes: attributes,
        content: content,
        pushType: nil
      )
      lastPhaseLabel = state.phaseLabel
      lastUpdateAt = CFAbsoluteTimeGetCurrent()
      #if DEBUG
      NSLog("[Breathe] Live Activity started: id=\(activity?.id ?? "?")")
      #endif
    } catch {
      #if DEBUG
      NSLog("[Breathe] Failed to start Live Activity: \(error.localizedDescription) (\(error))")
      #endif
      activity = nil
    }
#endif
  }

  func update(_ content: BreathingActivityContent) {
#if canImport(ActivityKit)
    guard #available(iOS 16.2, *), let activity else { return }

    let state = content.asState()
    let now = CFAbsoluteTimeGetCurrent()
    let phaseChanged = state.phaseLabel != lastPhaseLabel
    let elapsedSinceLast = now - lastUpdateAt

    guard phaseChanged || elapsedSinceLast >= Self.intraPhaseUpdateInterval else {
      return
    }

    let staleDate = content.sessionEndsAt.map { $0.addingTimeInterval(60) }
    let activityContent = ActivityContent(state: state, staleDate: staleDate)

    Task {
      await activity.update(activityContent)
    }
    lastPhaseLabel = state.phaseLabel
    lastUpdateAt = now
#endif
  }

  func end(finalState: BreathingActivityContent?) {
#if canImport(ActivityKit)
    guard #available(iOS 16.2, *), let activity else { return }

    let finalContent: ActivityContent<BreathingActivityAttributes.ContentState>?
    if let finalState {
      finalContent = ActivityContent(state: finalState.asState(), staleDate: nil)
    } else {
      finalContent = nil
    }
    self.activity = nil
    lastPhaseLabel = ""
    lastUpdateAt = 0

    Task {
      await activity.end(finalContent, dismissalPolicy: .immediate)
    }
#endif
  }
}

struct BreathingActivityContent {
  var phaseLabel: String
  var phaseCountdownSec: Double
  var sessionProgress: Double
  var pulse: Double
  var sessionEndsAt: Date?
  var isRunning: Bool

#if canImport(ActivityKit)
  @available(iOS 16.2, *)
  func asState() -> BreathingActivityAttributes.ContentState {
    BreathingActivityAttributes.ContentState(
      phaseLabel: phaseLabel,
      phaseCountdownSec: phaseCountdownSec,
      sessionProgress: sessionProgress,
      pulse: pulse,
      sessionEndsAt: sessionEndsAt,
      isRunning: isRunning
    )
  }
#endif
}
