/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// BreathingActivityAttributes.swift
//
// Shared between the Breathe app and the BreatheActivity widget extension.
// Defines the static and dynamic surface area of the Live Activity that
// mirrors the in-app session on the Lock Screen and Dynamic Island.
//

import ActivityKit
import Foundation

@available(iOS 16.2, *)
public struct BreathingActivityAttributes: ActivityAttributes {
  public typealias ContentState = State

  public struct State: Codable, Hashable {
    public var phaseLabel: String
    public var phaseCountdownSec: Double
    public var sessionProgress: Double
    public var pulse: Double
    public var sessionEndsAt: Date?
    public var isRunning: Bool

    public init(
      phaseLabel: String,
      phaseCountdownSec: Double,
      sessionProgress: Double,
      pulse: Double,
      sessionEndsAt: Date?,
      isRunning: Bool
    ) {
      self.phaseLabel = phaseLabel
      self.phaseCountdownSec = phaseCountdownSec
      self.sessionProgress = sessionProgress
      self.pulse = pulse
      self.sessionEndsAt = sessionEndsAt
      self.isRunning = isRunning
    }
  }

  public var modeName: String
  public var modeSubtitle: String
  public var startedAt: Date

  public init(modeName: String, modeSubtitle: String, startedAt: Date) {
    self.modeName = modeName
    self.modeSubtitle = modeSubtitle
    self.startedAt = startedAt
  }
}
