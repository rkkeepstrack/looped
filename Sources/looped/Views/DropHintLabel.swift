//
//  DropHintLabel.swift
//  looped
//
//  The "drop audio here" field: shared styling between the sidebar's
//  empty-state drop zone and the track list's drag-over drop hint.
//

import SwiftUI

struct DropHintLabel: View {
	/// Accented border while a drag hovers the zone.
	var highlighted = false

	var body: some View {
		Text("Drop audio files or folders here")
			.font(.caption)
			.foregroundStyle(Theme.textSecondary)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(
				RoundedRectangle(cornerRadius: Theme.panelCorner)
					.strokeBorder(
						highlighted ? Theme.accent.opacity(0.6) : Theme.panelBorder,
						lineWidth: highlighted ? 2 : 1
					)
			)
	}
}
