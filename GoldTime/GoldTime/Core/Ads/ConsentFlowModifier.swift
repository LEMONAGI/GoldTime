//
//  ConsentFlowModifier.swift
//  GoldTime
//

import SwiftUI

private struct ConsentFlowModifier: ViewModifier {
    let onCompleted: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .task {
                await ConsentService.shared.requestConsentAndBeginAdInitialization()
                onCompleted()
            }
    }
}

extension View {
    /// 사용자 대면 프레젠테이션은 UMP/ATT 시스템 팝업이 닫힌 뒤에 이어서 요청할 수 있다.
    func withConsentFlow(onCompleted: @escaping @MainActor () -> Void = {}) -> some View {
        modifier(ConsentFlowModifier(onCompleted: onCompleted))
    }
}
