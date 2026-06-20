//
//  ConsentFlowModifier.swift
//  GoldTime
//

import SwiftUI

private struct ConsentFlowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .task {
                await ConsentService.shared.requestConsentAndBeginAdInitialization()
            }
    }
}

extension View {
    func withConsentFlow() -> some View {
        modifier(ConsentFlowModifier())
    }
}
