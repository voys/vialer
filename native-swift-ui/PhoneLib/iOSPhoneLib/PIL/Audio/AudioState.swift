//
//  AudioState.swift
//  PIL
//
//  Created by Jeremy Norman on 07/03/2021.
//

import Foundation

public struct AudioState {
    public let currentRoute: AudioRoute
    public let availableRoutes: [AudioRoute]
    public let bluetoothDeviceName: String?
    public let isMicrophoneMuted: Bool
}
