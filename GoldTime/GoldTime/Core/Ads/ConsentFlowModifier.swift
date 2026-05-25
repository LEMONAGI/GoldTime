//
//  ConsentFlowModifier.swift
//  GoldTime
//

import SwiftUI

private struct ConsentFlowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .task {
                guard !ConsentService.shared.isAdSdkReady else { return }
                await ConsentService.shared.requestConsentAndInitialize()
            }
    }
}

extension View {
    func withConsentFlow() -> some View {
        modifier(ConsentFlowModifier())
    }
}
