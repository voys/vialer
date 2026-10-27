//
//  EventsManager.swift
//  PIL
//
//  Created by Jeremy Norman on 15/02/2021.
//

import Foundation

public class EventsManager {
    
    private let pil: PIL
    private let calls: Calls
    private var listeners = [ObjectIdentifier : EventListener]()
    
    init(pil: PIL, calls: Calls) {
        self.pil = pil
        self.calls = calls
    }
    
    public func listen(delegate: PILEventDelegate) {
        let id = ObjectIdentifier(delegate)
        listeners[id] = EventListener(listener: delegate)
    }
    
    public func stopListening(delegate: PILEventDelegate) {
        let id = ObjectIdentifier(delegate)
        listeners.removeValue(forKey: id)
    }
    
    internal func broadcast(event: Event) {
        if !pil.isStarted {
            return
        }
        
        for (id, listener) in listeners {
            guard let delegate = listener.listener else {
                listeners.removeValue(forKey: id)
                continue
            }
            
            delegate.onEvent(event: event)
        }
    }

    struct EventListener {
        weak var listener: PILEventDelegate?
    }
}
