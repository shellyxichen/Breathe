/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// MockDeviceViewModel.swift
//
// View model for individual mock devices used in development and testing of DAT SDK features.
// This controls mock device behaviors like power states, physical states (folded/unfolded),
// and media content (camera feeds and captured images).
//

#if false // GLASSES_SDK: temporarily disabled — re-enable when glasses capability is ready

#if DEBUG

import Foundation
import MWDATMockDevice

extension MockDeviceCardView {
  @MainActor
  final class ViewModel: ObservableObject {
    let device: MockDevice
    @Published var hasCameraFeed: Bool = false
    @Published var hasCapturedImage: Bool = false

    init(device: MockDevice, hasCameraFeed: Bool = false, hasCapturedImage: Bool = false) {
      self.device = device
      self.hasCameraFeed = hasCameraFeed
      self.hasCapturedImage = hasCapturedImage
    }

    var id: String { device.deviceIdentifier }

    var deviceName: String {
      if device is MockRaybanMeta {
        return "RayBan Meta Glasses"
      }
      return "Device"
    }

    func powerOn() {
      device.powerOn()
    }

    func powerOff() {
      device.powerOff()
    }

    func don() {
      device.don()
    }

    func doff() {
      device.doff()
    }

    func unfold() {
      if let rayBanDevice = device as? MockDisplaylessGlasses {
        rayBanDevice.unfold()
      }
    }

    func fold() {
      if let rayBanDevice = device as? MockDisplaylessGlasses {
        rayBanDevice.fold()
      }
    }

    func selectVideo(from url: URL) {
      if let cameraKit = (device as? MockDisplaylessGlasses)?.getCameraKit() {
        Task {
          await cameraKit.setCameraFeed(fileURL: url)
          hasCameraFeed = true
        }
      }
    }

    func selectImage(from url: URL) {
      if let cameraKit = (device as? MockDisplaylessGlasses)?.getCameraKit() {
        Task {
          await cameraKit.setCapturedImage(fileURL: url)
          hasCapturedImage = true
        }
      }
    }
  }
}

#endif

#endif // GLASSES_SDK
