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
	@StateObject private var reorder = ReorderState()

	/// Below this much free space the drop hint stays hidden — the insertion
	/// line alone carries the feedback.
	private let minDropHintHeight: CGFloat = 60
	/// Headroom above gap 0 for its insertion indicator.
	private let topInset: CGFloat = 4

	var body: some View {
		GeometryReader { geo in
			ScrollView {
				// Non-lazy so zIndex can lift the dragged row; the library is small.
				VStack(spacing: 0) {
					ForEach(Array(library.tracks.enumerated()), id: \.element.id) { index, track in
						trackRow(track, at: index)
					}
					// Tail area so a drop can land below the last row (gap = count).
					Color.clear.frame(height: Theme.trackRowHeight * 2)
				}
				// Fill the viewport so the whole column below the rows is a drop
				// target (a drop past the tail clamps to gap = count → append).
				.frame(minHeight: max(0, geo.size.height - topInset), alignment: .top)
				.overlay(alignment: .top) { insertionLine }
				.overlay(alignment: .bottom) { dropHint(viewportHeight: geo.size.height) }
				// On the content, not the ScrollView: DropInfo.location must stay
				// in row coordinates when scrolled.
				.onDrop(
					of: [.fileURL],
					delegate: TrackListDropDelegate(library: library, gapIndex: $reorder.externalGapIndex)
				)
				// Outside the drop/overlay so gap coordinates are unaffected.
				.padding(.top, topInset)
			}
		}
	}

	/// "Drop audio files or folders here", faded in while an external drag
	/// hovers the list.
	@ViewBuilder private func dropHint(viewportHeight: CGFloat) -> some View {
		let free = viewportHeight - topInset - CGFloat(library.tracks.count + 2) * Theme.trackRowHeight
		if free >= minDropHintHeight {
			DropHintLabel()
				.frame(height: free)
				.opacity(reorder.isExternalDragHovering ? 1 : 0)
				.animation(.linear(duration: 0.15), value: reorder.isExternalDragHovering)
				.allowsHitTesting(false)
		}
	}

	private func trackRow(_ track: Track, at index: Int) -> some View {
		TrackRow(
			track: track,
			isCurrent: track.id == library.currentTrackID,
			isSelected: track.id == library.selectedTrackID
		)
		.frame(height: Theme.trackRowHeight)
		.offset(y: index == reorder.draggedIndex ? reorder.dragTranslation : 0)
		.zIndex(index == reorder.draggedIndex ? 1 : 0)
		.opacity(index == reorder.draggedIndex ? 0.8 : 1)
		.onTapGesture { library.selectedTrackID = track.id }
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
				if !reorder.isDragging { library.selectedTrackID = track.id }
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
