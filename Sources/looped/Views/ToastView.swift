//
//  ToastView.swift
//  looped
//
//  The toast overlay: ToastCenter's queue as themed cards, bottom-trailing
//  above the controls bar; hosted as an overlay in ContentView.
//

import SwiftUI

struct ToastStackView: View {
	@EnvironmentObject var toasts: ToastCenter

	var body: some View {
		VStack(alignment: .trailing, spacing: 8) {
			ForEach(toasts.toasts) { toast in
				ToastCard(toast: toast) {
					toasts.dismiss(id: toast.id)
				}
				.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
		.padding(16)
		.animation(.easeInOut(duration: 0.2), value: toasts.toasts)
	}
}

private struct ToastCard: View {
	let toast: Toast
	let dismiss: () -> Void

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 10) {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundStyle(Theme.accent)
			VStack(alignment: .leading, spacing: 4) {
				// By offset, not \.self — identical messages must not collide.
				ForEach(Array(toast.messages.enumerated()), id: \.offset) { _, message in
					Text(message)
						.font(.callout)
						.foregroundStyle(Theme.textPrimary)
				}
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.frame(maxWidth: Theme.toastMaxWidth, alignment: .leading)
		.background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.panelCorner))
		.overlay(
			RoundedRectangle(cornerRadius: Theme.panelCorner)
				.strokeBorder(Theme.panelBorder)
		)
		.onTapGesture(perform: dismiss)
	}
}
