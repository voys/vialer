//
//  Contacts.swift
//  PIL
//
//  Created by Jeremy Norman on 07/03/2021.
//

import Foundation
import Contacts

typealias ContactCallback = (Contact?) -> Void

class Contacts {
    
    private let store = CNContactStore()
    
    private var cachedContacts = [String: Contact?]()
    
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(addressBookDidChange),
            name: NSNotification.Name.CNContactStoreDidChange,
            object: nil
        )
    }
    
    
    func find(call: VoIPLibCall) -> Contact? {
        find(number: call.remoteNumber, identifier: call.identifier)
    }
    
    func find(number: String, identifier: String)  -> Contact? {
        if let contact = self.cachedContacts[identifier] {
            if let contact = contact {
                return contact.exists ? contact : nil
            }
        }
        
        if CNContactStore.authorizationStatus(for: .contacts) != .authorized {
            return nil
        }
        
        if let cachedContact = cachedContacts[identifier] {
            return cachedContact
        }
        
        let contact = searchForNumberInUnifiedContacts(number: number)
        
        if contact != nil {
            cachedContacts[identifier] = contact?.toContact() ?? Contact.notFound()
        }
        
        return cachedContacts[identifier, default: nil]
    }
    
    private func searchForNumberInUnifiedContacts(number: String) -> CNContact? {
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactImageDataAvailableKey, CNContactThumbnailImageDataKey]
        let request = CNContactFetchRequest(keysToFetch: keys as [CNKeyDescriptor])
        
        let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: number))
        
        do {
            return try store.unifiedContacts(matching: predicate, keysToFetch: keys as [CNKeyDescriptor]).first
        } catch {
            log("Unable to access contacts")
            return nil
        }
    }
    
    internal func clearCache() {
        cachedContacts.removeAll()
    }
    
    @objc func addressBookDidChange() {
        clearCache()
    }
}

public struct Contact {
    public let name: String
    public let image: Data?
    
    internal var exists: Bool {
        return !name.isEmpty
    }
    
    init(_ name: String) {
        self.name = name
        self.image = nil
    }
    
    init() {
        self.init("")
    }
    
    public static func notFound() -> Contact {
        return Contact()
    }
}

extension VoIPLibCall {
    var identifier: String {
        return callId.description
    }
}

extension CNContact {
    func toContact() -> Contact {
        return Contact("\(givenName) \(familyName)")
    }
}
