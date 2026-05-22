//
//  LimitPickerSheet.swift
//  GoldTime
//

import SwiftUI

struct LimitPickerSheet: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("취소", action: onCancel)
                Spacer()
                Button("완료") { onConfirm() }
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            
            HStack(spacing: 0) {
                Picker("시간", selection: $hours) {
                    ForEach(0..<24, id: \.self) { h in
                        Text("\(h)시간").tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("분", selection: $minutes) {
                    ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { m in
                        Text("\(m)분").tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 216)
        }
    }
}
