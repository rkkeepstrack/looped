//
//  TrackListView.swift
//  looped
//
//  Hand-rolled track list (VStack, not a native List) so selection, reorder,
//  and the drop insertion line stay themeable — the NSTableView under a List
//  draws them in the system accent with no recolor API. Cost: no keyboard
//  navigation or drag auto-scroll.
//

import SwiftUI

struct TrackListView: View {
	@EnvironmentObject var library: LibraryViewModel
	/// Single-click selection — purely visual until a double-click loads.
	@State private var selectedTrackID: UUID?
	@StateObject private var reorder = ReorderState()

	var body: some View {
		ScrollView {
			// Non-lazy so zIndex can lift the dragged row; the library is small.
			VStack(spacing: 0) {
				ForEach(Array(library.tracks.enumerated()), id: \.element.id) { index, track in
					trackRow(track, at: index)
				}
				// Tail area so a drop can land below the last row (gap = count).
				Color.clear.frame(height: Theme.trackRowHeight * 2)
			}
			.overlay(alignment: .top) { insertionLine }
			// On the content, not the ScrollView: DropInfo.location must stay
			// in row coordinates when scrolled.
			.onDrop(
				of: [.fileURL],
				delegate: TrackListDropDelegate(library: library, gapIndex: $reorder.externalGapIndex)
			)
			// Headroom for the gap-0 indicator; outside the drop/overlay so gap
			// coordinates are unaffected.
			.padding(.top, 4)
		}
	}

	private func trackRow(_ track: Track, at index: Int) -> some View {
		TrackRow(
			track: track,
			isCurrent: track.id == library.currentTrackID,
			isSelected: track.id == selectedTrackID
		)
		.frame(height: Theme.trackRowHeight)
		.offset(y: index == reorder.draggedIndex ? reorder.dragTranslation : 0)
		.zIndex(index == reorder.draggedIndex ? 1 : 0)
		.opacity(index == reorder.draggedIndex ? 0.8 : 1)
		.onTapGesture { selectedTrackID = track.id }
		.simultaneousGesture(
			TapGesture(count: 2)
				.onEnded { Task { await library.load(track) } }
		)
		// High priority or the taps win arbitration and the drag starts late
		// (a hard pull); stationary clicks still resolve as taps.
		.highPriorityGesture(reorderGesture(for: index, track: track))
	}

	private func reorderGesture(for index: Int, track: Track) -> some Gesture {
		DragGesture(minimumDistance: 2)
			.onChanged { value in
				if !reorder.isDragging { selectedTrackID = track.id }
				reorder.dragChanged(index: index, translation: value.translation.height)
			}
			.onEnded { value in
				guard let move = reorder.dragEnded(
					translation: value.translation.height,
					rowHeight: Theme.trackRowHeight,
					count: library.tracks.count
				) else { return }
				library.move(fromOffsets: IndexSet(integer: move.from), toOffset: move.toGap)
			}
	}

	/// Native-style insertion indicator: 1pt hairline + leading hollow dot.
	@ViewBuilder private var insertionLine: some View {
		if let gap = reorder.activeGapIndex(rowHeight: Theme.trackRowHeight, count: library.tracks.count) {
			HStack(spacing: 2) {
				Circle()
					.strokeBorder(Theme.insertionLine, lineWidth: 1)
					.frame(width: 5, height: 5)
				Capsule()
					.fill(Theme.insertionLine)
					.frame(height: 1)
			}
			.padding(.horizontal, 3)
			.frame(height: 5)
			.offset(y: CGFloat(gap) * Theme.trackRowHeight - 2.5)
			.allowsHitTesting(false)
		}
	}
}

private struct TrackRow: View {
	let track: Track
	let isCurrent: Bool
	let isSelected: Bool
	@State private var hovering = false

	var body: some View {
		HStack(spacing: 8) {
			Text(track.title)
				.font(.callout)
				.lineLimit(1)
				.truncationMode(.tail)
				.foregroundStyle(isCurrent ? Theme.accent : Theme.textPrimary)

			Spacer(minLength: 4)

			if let duration = track.duration {
				Text(TimeFormatter.mmss(duration))
					.font(.caption.monospacedDigit())
					.foregroundStyle(isCurrent ? Theme.accentDim : Theme.textSecondary)
			}
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 5)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(
			RoundedRectangle(cornerRadius: 6)
				.fill(isSelected ? Color.white.opacity(0.12) : hovering ? Color.white.opacity(0.06) : Color.clear)
				.padding(.vertical, 1)
		)
		.contentShape(Rectangle())
		.onHover { hovering = $0 }
	}
}

private struct TrackListDropDelegate: DropDelegate {
	let library: LibraryViewModel
	@Binding var gapIndex: Int?

	func validateDrop(info: DropInfo) -> Bool {
		info.hasItemsConforming(to: [.fileURL])
	}

	func dropUpdated(info: DropInfo) -> DropProposal? {
		gapIndex = RowInsertion.gapIndex(
			y: info.location.y,
			rowHeight: Theme.trackRowHeight,
			count: library.tracks.count
		)
		return DropProposal(operation: .copy)
	}

	func dropExited(info _: DropInfo) {
		gapIndex = nil
	}

	func performDrop(info: DropInfo) -> Bool {
		let providers = info.itemProviders(for: [.fileURL])
		guard !providers.isEmpty else { return false }
		let index = gapIndex
		gapIndex = nil
		Task { await library.handleLibraryDrop(providers: providers, at: index) }
		return true
	}
}
