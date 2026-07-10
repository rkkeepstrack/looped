//
//  SidebarView.swift
//  looped
//
//  Collapsible left panel: import button + the track list (TrackListView),
//  with the empty state doubling as a drop zone.
//

import SwiftUI

struct SidebarView: View {
	@EnvironmentObject var library: LibraryViewModel
	@State private var emptyDropTargeted = false

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(spacing: 8) {
				Button {
					Task { await library.openFiles() }
				} label: {
					Label("Import Files", systemImage: "square.and.arrow.down")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)

				// End-of-track mode; sidebar-hosted until plan 07 moves it to
				// the transport cluster.
				PlaythroughModeButton()
			}
			.controlSize(.large)

			if library.tracks.isEmpty {
				emptyDropZone
			} else {
				TrackListView()
			}

			Spacer(minLength: 0)
		}
		.padding(.horizontal, 12)
		.padding(.top, 48) // clear the top-left toggle
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.background(Theme.surface)
	}

	private var emptyDropZone: some View {
		Text("Drop audio files or folders here")
			.font(.caption)
			.foregroundStyle(Theme.textSecondary)
			.frame(maxWidth: .infinity, minHeight: 100)
			.background(
				RoundedRectangle(cornerRadius: Theme.panelCorner)
					.strokeBorder(
						emptyDropTargeted ? Theme.accent.opacity(0.6) : Theme.panelBorder,
						lineWidth: emptyDropTargeted ? 2 : 1
					)
			)
			.onDrop(of: [.fileURL], isTargeted: $emptyDropTargeted) { providers in
				guard !providers.isEmpty else { return false }
				Task { await library.handleLibraryDrop(providers: providers) }
				return true
			}
	}
}
