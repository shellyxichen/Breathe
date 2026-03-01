/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// TimeUtils.swift
//
// Utility types for breathing session timers and formatting.
//

import Foundation
import SwiftUI

enum BreathingTimerOption: String, CaseIterable, Identifiable {
  case sec30 = "30"
  case sec60 = "60"
  case sec120 = "120"
  case sec180 = "180"
  case sec300 = "300"
  case sec600 = "600"
  case infinity = "infinity"

  var id: String { rawValue }

  var displayText: String {
    switch self {
    case .sec30:
      return "00:30"
    case .sec60:
      return "01:00"
    case .sec120:
      return "02:00"
    case .sec180:
      return "03:00"
    case .sec300:
      return "05:00"
    case .sec600:
      return "10:00"
    case .infinity:
      return "Infinity"
    }
  }

  var durationSec: TimeInterval? {
    switch self {
    case .sec30:
      return 30
    case .sec60:
      return 60
    case .sec120:
      return 120
    case .sec180:
      return 180
    case .sec300:
      return 300
    case .sec600:
      return 600
    case .infinity:
      return nil
    }
  }
}

extension TimeInterval {
  var formattedCountdown: String {
    let minutes = Int(self) / 60
    let seconds = Int(self) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}

func formattedPhaseCountdown(_ secondsRemaining: Double) -> String {
  let seconds = max(1, Int(ceil(secondsRemaining)))
  return String(seconds).padLeft(toLength: 2, withPad: "0")
}

private extension String {
  func padLeft(toLength: Int, withPad pad: String) -> String {
    guard count < toLength else { return self }
    return String(repeating: pad, count: toLength - count) + self
  }
}
