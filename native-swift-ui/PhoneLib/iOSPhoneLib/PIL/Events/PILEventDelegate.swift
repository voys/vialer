//
//  PILEventDelegate.swift
//  PIL
//
//  Created by Jeremy Norman on 05/03/2021.
//

import Foundation

public protocol PILEventDelegate: class {
    func onEvent(event: Event)
}
