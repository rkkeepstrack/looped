//
//  EmptyStateView.swift
//  looped
//
//  Placeholder for the content column when nothing is loaded (first launch,
//  or the current track was removed). The mark is a stand-in for a real
//  logo — keep it swappable.
//

import SwiftUI

struct EmptyStateView: View {
	/// A failed load's message — with no header on screen, the placeholder is
	/// the only place left to surface it.
	var error: String?

	var body: some View {
		VStack(spacing: 14) {
			Image(systemName: "waveform.circle")
				.font(.system(size: 56, weight: .light))
				.foregroundStyle(Theme.accentDim)
			Text("looped")
				.font(.title2.weight(.semibold))
				.foregroundStyle(Theme.textPrimary)
			Text("Load a track to get started — drop audio here or press ⌘O")
				.font(.callout)
				.foregroundStyle(Theme.textSecondary)
			if let error {
				Text(error)
					.font(.callout)
					.foregroundStyle(Theme.accent)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
