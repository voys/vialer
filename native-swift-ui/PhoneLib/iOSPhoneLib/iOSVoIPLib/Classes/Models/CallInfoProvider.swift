//
//  VoIPLibCallInfoProvider.swift
//  iOSVoIPLib
//
//  Created by Chris Kontos on 20/04/2021.
//

import Foundation
import linphonesw

class CallInfoProvider {
    
    let VoIPLibCall: VoIPLibCall
    
    init(VoIPLibCall: VoIPLibCall){
        self.VoIPLibCall = VoIPLibCall
    }
    
    func provide() -> String {
        let audio = provideAudioInfo()
        let advancedSettings = provideAdvancedSettings()
        let toAddressInfo = provideToAddressInfo()
        let remoteParams = provideRemoteParams()
        let params = provideParams()
        let VoIPLibCallProperties = provideVoIPLibCallProperties()
        let errorInfo = provideErrorInfo()
        
        let VoIPLibCallInfo: [String: Any] = [
            "Audio": audio.map{"  \($0): \($1)"}.sorted().joined(separator: "\n"),
            "Advanced Settings": advancedSettings.map{"  \($0): \($1)"}.sorted().joined(separator: "\n"),
            "To Address": toAddressInfo.map{"  \($0): \($1)"}.sorted().joined(separator: "\n"),
            "Remote Params": remoteParams.map{"  \($0): \($1)"}.sorted().joined(separator: "\n"),
            "Params": params.map{"  \($0): \($1)"}.sorted().joined(separator: "\n"),
            "VoIPLibCall": VoIPLibCallProperties.map{"  \($0): \($1)"}.sorted().joined(separator: "\n"),
            "Error": errorInfo.map{"  \($0): \($1)"}.sorted().joined(separator: "\n")
        ]
        
        return VoIPLibCallInfo.map{"\($0)\n\($1)\n"}.sorted().joined(separator: "\n")
    }
    
    private func provideAudioInfo() -> [String:Any] {
        guard let codec = VoIPLibCall.linphoneCall.currentParams?.usedAudioPayloadType?.description,
        let codecChannels = VoIPLibCall.linphoneCall.currentParams?.usedAudioPayloadType?.channels,
        let downloadBandwidth = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.downloadBandwidth,
        let estimatedDownloadBandwidth = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.estimatedDownloadBandwidth,
        let jitterBufferSizeMs = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.jitterBufferSizeMs,
              let loVoIPLibCallateRate = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.localLateRate,
        let loVoIPLibCallossRate = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.localLossRate,
        let receiverInterarrivalJitter = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.receiverInterarrivalJitter,
        let receiverLossRate = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.receiverLossRate,
        let roundTripDelay = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.roundTripDelay,
        let rtcpDownloadBandwidth = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.rtcpDownloadBandwidth,
        let rtcpUploadBandwidth = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.rtcpUploadBandwidth,
        let senderInterarrivalJitter = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.senderInterarrivalJitter,
        let senderLossRate = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.senderLossRate,
        let iceState = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.iceState,
        let uploadBandwidth = VoIPLibCall.linphoneCall.getStats(type: .Audio)?.uploadBandwidth else {return ["":""]}
        
        let audio: [String:Any] = [
            "codec": codec,
            "codecChannels": codecChannels,
            "downloadBandwidth": downloadBandwidth,
            "estimatedDownloadBandwidth": estimatedDownloadBandwidth,
            "jitterBufferSizeMs": jitterBufferSizeMs,
            "loVoIPLibCallateRate": loVoIPLibCallateRate,
            "loVoIPLibCallossRate": loVoIPLibCallossRate,
            "receiverInterarrivalJitter": receiverInterarrivalJitter,
            "receiverLossRate": receiverLossRate,
            "roundTripDelay": roundTripDelay,
            "rtcpDownloadBandwidth": rtcpDownloadBandwidth,
            "rtcpUploadBandwidth": rtcpUploadBandwidth,
            "senderInterarrivalJitter": senderInterarrivalJitter,
            "senderLossRate": senderLossRate,
            "iceState": iceState,
            "uploadBandwidth": uploadBandwidth
        ]
        
        return audio
    }
        
    private func provideAdvancedSettings() -> [String:Any] {
        guard let mtu = VoIPLibCall.linphoneCall.core?.mtu,
        let echoCancellationEnabled = VoIPLibCall.linphoneCall.core?.echoCancellationEnabled,
        let adaptiveRateControlEnabled = VoIPLibCall.linphoneCall.core?.adaptiveRateControlEnabled,
        let audioAdaptiveJittcompEnabled = VoIPLibCall.linphoneCall.core?.audioAdaptiveJittcompEnabled,
        let rtpBundleEnabled = VoIPLibCall.linphoneCall.core?.rtpBundleEnabled,
        let adaptiveRateAlgorithm = VoIPLibCall.linphoneCall.core?.adaptiveRateAlgorithm else {return ["":""]}
        
        let advancedSettings: [String:Any] = [
            "mtu": mtu,
            "echoCancellationEnabled": echoCancellationEnabled,
            "adaptiveRateControlEnabled": adaptiveRateControlEnabled,
            "audioAdaptiveJittcompEnabled": audioAdaptiveJittcompEnabled,
            "rtpBundleEnabled": rtpBundleEnabled,
            "adaptiveRateAlgorithm": adaptiveRateAlgorithm
        ]
        
        return advancedSettings
    }
    
    private func provideToAddressInfo() -> [String:Any] {
        guard let transport = VoIPLibCall.linphoneCall.toAddress?.transport,
              let domain = VoIPLibCall.linphoneCall.toAddress?.domain else {return ["":""]}
        
        let toAddressInfo: [String:Any] = [
            "transport": transport,
            "domain": domain,
        ]
        
        return toAddressInfo
    }
    
    private func provideRemoteParams() -> [String:Any] {
        guard let remoteEncryption = VoIPLibCall.linphoneCall.remoteParams?.mediaEncryption,
              let remoteSessionName = VoIPLibCall.linphoneCall.remoteParams?.sessionName,
              let remotePartyId = VoIPLibCall.linphoneCall.remoteParams?.getCustomHeader(headerName: "Remote-Party-ID"),
              let pAssertedIdentity = VoIPLibCall.linphoneCall.remoteParams?.getCustomHeader(headerName: "P-Asserted-Identity") else {return ["":""]}
        
        let remoteParams: [String:Any] = [
            "encryption": remoteEncryption,
            "sessionName": remoteSessionName,
            "remotePartyId": remotePartyId,
            "pAssertedIdentity": pAssertedIdentity,
        ]
        
        return remoteParams
    }
    
    private func provideParams() -> [String:Any] {
        guard let encryption = VoIPLibCall.linphoneCall.params?.mediaEncryption,
              let sessionName = VoIPLibCall.linphoneCall.params?.sessionName else {return ["":""]}
        
        let params: [String:Any] = [
            "encryption": encryption,
            "sessionName": sessionName
        ]
        
        return params
    }

    private func provideVoIPLibCallProperties() -> [String:Any] {
        let reason = VoIPLibCall.linphoneCall.reason
        let duration = VoIPLibCall.linphoneCall.duration
        
        guard let VoIPLibCallId = VoIPLibCall.linphoneCall.callLog?.callId,
              let refKey = VoIPLibCall.linphoneCall.callLog?.refKey,
              let status = VoIPLibCall.linphoneCall.callLog?.status,
              let direction = VoIPLibCall.linphoneCall.callLog?.dir,
              let quality = VoIPLibCall.linphoneCall.callLog?.quality,
              let startDate = VoIPLibCall.linphoneCall.callLog?.startDate
        else { return ["reason": reason, "duration": duration]}
        
        let VoIPLibCallProperties: [String:Any] = [
            "VoIPLibCallId": VoIPLibCallId,
            "refKey": refKey,
            "status": status,
            "direction": direction,
            "quality": quality,
            "startDate": startDate,
            "reason": reason,
            "duration": duration
        ]
        
        return VoIPLibCallProperties
    }
    
    private func provideErrorInfo() -> [String:Any] {
        guard let phrase = VoIPLibCall.linphoneCall.errorInfo?.phrase,
            let errorProtocol = VoIPLibCall.linphoneCall.errorInfo?.proto,
            let errorReason = VoIPLibCall.linphoneCall.errorInfo?.reason,
            let protocolCode = VoIPLibCall.linphoneCall.errorInfo?.protocolCode else {return ["":""]}
        
        let errorInfo: [String:Any] = [
            "phrase": phrase,
            "protocol": errorProtocol,
            "reason": errorReason,
            "protocolCode": protocolCode
        ]
        
        return errorInfo
    }
}
