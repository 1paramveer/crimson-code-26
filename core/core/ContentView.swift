//
//  ContentView.swift
//  core
//
//  Created by Paramveer Singh on 2/22/26.
//
import SwiftUI
import SmartSpectraSwiftSDK

struct ContentView: View {
    @ObservedObject var sdk = SmartSpectraSwiftSDK.shared
    
    init() {
            sdk.setApiKey("zzdWamBg835EPXHJFEtQrsBFSAm2wmCaBTFLPNfb")
        }

    var body: some View {
            SmartSpectraView()  // Presage handles camera + face detection
    }
}

#Preview {
    ContentView()
}
