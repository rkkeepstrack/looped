//
//  ContentView.swift
//  looped
//
//  Created by Raphael Kalinowski on 28.09.25.
//

import SwiftUI

struct ContentView: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel
	@EnvironmentObject var offsetCalculator: WaveformViewModel
	@EnvironmentObject var library: LibraryViewModel
	/// A file drag is hovering the waveform drop zone (drop → load immediately).
	@State private var waveformDropTargeted = false
	@AppStorage("sidebarOpen") private var sidebarOpen = true
	@AppStorage("sidebarWidth") private var sidebarWidth = Double(Theme.sidebarWidth)
	/// Width latched at drag start, so the resize tracks the cursor without drift.
	@State private var sidebarDragStartWidth: Double?

	var body: some View {
		HStack(spacing: 0) {
			if sidebarOpen {
				Sidebar()
					.frame(width: clampedSidebarWidth)
					.transition(.move(edge: .leading))
				sidebarResizeHandle
			}
			mainColumn
		}
		// Drive the push animation off the flag itself — more reliable than
		// withAnimation for @AppStorage, whose change can land outside the block.
		.animation(Theme.sidebarAnimation, value: sidebarOpen)
		.background(Theme.background)
		// A fixed top-left toggle (over the sidebar when open, over the header when
		// collapsed), matching the mock.
		.overlay(alignment: .topLeading) {
			Button {
				// Just toggle: the waveform's render width is viewport-independent,
				// so this only re-centers (pans) — no re-analysis or repaint.
				sidebarOpen.toggle()
			} label: {
				Image(systemName: "sidebar.leading").font(.title3)
			}
			.buttonStyle(.borderless)
			.help("Toggle sidebar")
			.padding(10)
		}
		// Keyboard shortcuts (spacebar → play/pause)
		.background(KeyboardHandler(audioPlayer: audioPlayer))
	}

	// MARK: Sidebar resize

	private var clampedSidebarWidth: CGFloat {
		CGFloat(min(max(sidebarWidth, Double(Theme.sidebarMinWidth)), Double(Theme.sidebarMaxWidth)))
	}

	/// The sidebar/main divider, widened into a grabbable resize handle.
	private var sidebarResizeHandle: some View {
		Divider()
			// A hairline is impossible to grab — pad the hit area without
			// visually widening the divider.
			.contentShape(Rectangle().inset(by: -4))
			.onHover { inside in
				if inside {
					NSCursor.resizeLeftRight.push()
				} else {
					NSCursor.pop()
				}
			}
			.gesture(
				DragGesture(minimumDistance: 1, coordinateSpace: .global)
					.onChanged { value in
						let start = sidebarDragStartWidth ?? sidebarWidth
						sidebarDragStartWidth = start
						sidebarWidth = min(
							max(start + value.translation.width, Double(Theme.sidebarMinWidth)),
							Double(Theme.sidebarMaxWidth)
						)
					}
					.onEnded { _ in sidebarDragStartWidth = nil }
			)
	}

	// MARK: Main column

	private var mainColumn: some View {
		VStack(spacing: 0) {
			header
			Divider()
			waveformDropZone
			Divider()
			ControlsView()
		}
	}

	/// The waveform as a drop zone: while a file drag hovers, the whole
	/// waveform gets a translucent light-gray wash; dropping loads the file
	/// immediately (the library zone — the sidebar list — only inserts).
	private var waveformDropZone: some View {
		WaveformDisplayView()
			.overlay {
				if waveformDropTargeted {
					Rectangle()
						.fill(Theme.waveformDropHighlight)
						.allowsHitTesting(false)
				}
			}
			.onDrop(of: [.fileURL], isTargeted: $waveformDropTargeted) { providers in
				guard !providers.isEmpty else { return false }
				Task {
					let urls = await LibraryViewModel.urls(from: providers)
					await library.loadDropped(urls: urls)
				}
				return true
			}
	}

	// MARK: Header (name + currentTime | fileTime)

	private var header: some View {
		VStack(spacing: 2) {
			Text(audioPlayer.currentFileName ?? "No file loaded")
				.font(.headline)
				.foregroundStyle(audioPlayer.currentFileName == nil ? Theme.textSecondary : Theme.textPrimary)

			if let error = audioPlayer.loadError {
				Text(error)
					.font(.subheadline)
					.foregroundStyle(Theme.accent)
			} else if audioPlayer.audioURL != nil {
				Text("\(TimeFormatter.mmss(audioPlayer.currentTime)) | \(TimeFormatter.mmss(audioPlayer.duration))")
					.font(.subheadline.monospacedDigit())
					.foregroundStyle(Theme.textSecondary)
			}
		}
		// Centered within the content column, so it re-centers as the sidebar
		// pushes everything right.
		.frame(maxWidth: .infinity)
		.frame(height: 64)
	}
}

// MARK: - Sidebar

/// Collapsible left panel: the import button + the track library list. The
/// list is the "library" drop zone: external file/folder drops and internal
/// reorder drags both show a themed insertion line at the drop point.
///
/// The list is hand-rolled (plain VStack + our own drag/drop) rather than a
/// native List: the NSTableView under a List paints its selection highlight
/// and drop indicator in the system accent with no public recolor API, which
/// clashed with the theme. Owning the ~150 lines keeps every pixel themeable —
/// the standard trade for custom-look audio apps. Cost: no keyboard list
/// navigation, no auto-scroll while dragging (fine at library scale).
private struct Sidebar: View {
	@EnvironmentObject var library: LibraryViewModel
	/// Row picked by a single click — purely visual until a double-click plays it.
	@State private var selectedTrackID: UUID?
	/// A file drag is hovering the empty-library drop zone.
	@State private var emptyDropTargeted = false
	/// Row index being drag-reordered, and its live vertical translation.
	@State private var draggedIndex: Int?
	@State private var dragTranslation: CGFloat = 0
	/// Insertion gap while an external file drag hovers the list.
	@State private var externalGapIndex: Int?

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Button {
				Task { await library.openFiles() }
			} label: {
				Label("Import Files", systemImage: "square.and.arrow.down")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.bordered)
			.controlSize(.large)

			if library.tracks.isEmpty {
				emptyDropZone
			} else {
				trackList
			}

			Spacer(minLength: 0)
		}
		.padding(.horizontal, 12)
		.padding(.top, 48) // clear the top-left toggle
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.background(Theme.surface)
	}

	private var trackList: some View {
		ScrollView {
			// A plain (non-lazy) VStack: rows must exist for zIndex to lift
			// the dragged one, and the library is small.
			VStack(spacing: 0) {
				ForEach(Array(library.tracks.enumerated()), id: \.element.id) { index, track in
					trackRow(track, at: index)
				}
				// Tail area so a drop can land below the last row (gap = count).
				Color.clear.frame(height: Theme.trackRowHeight * 2)
			}
			.overlay(alignment: .top) { insertionLine }
			// Attached to the content (not the ScrollView), so DropInfo.location
			// stays in row coordinates even when scrolled.
			.onDrop(
				of: [.fileURL],
				delegate: TrackListDropDelegate(library: library, gapIndex: $externalGapIndex)
			)
		}
	}

	private func trackRow(_ track: Track, at index: Int) -> some View {
		TrackRow(
			track: track,
			isCurrent: track.id == library.currentTrackID,
			isSelected: track.id == selectedTrackID
		)
		.frame(height: Theme.trackRowHeight)
		// The dragged row follows the cursor, floats above its siblings, and
		// dims slightly so it reads as picked up.
		.offset(y: index == draggedIndex ? dragTranslation : 0)
		.zIndex(index == draggedIndex ? 1 : 0)
		.opacity(index == draggedIndex ? 0.8 : 1)
		// Single click selects instantly (also the first click of a double);
		// the simultaneous double-click loads the track into the waveform.
		.onTapGesture { selectedTrackID = track.id }
		.simultaneousGesture(
			TapGesture(count: 2)
				.onEnded { Task { await library.load(track) } }
		)
		// High priority so the drag wins gesture arbitration as soon as the
		// cursor moves — attached after the taps it would otherwise have to
		// wait them out, which read as the row needing a hard pull to pick
		// up. Clicks are unaffected: a stationary press never becomes a drag.
		.highPriorityGesture(reorderGesture(for: index, track: track))
	}

	/// Drag-to-reorder: the minimum distance keeps clicks (select/load) intact;
	/// only the vertical translation matters, `RowInsertion` turns it into the
	/// target gap, and `LibraryViewModel.move` commits on release.
	private func reorderGesture(for index: Int, track: Track) -> some Gesture {
		DragGesture(minimumDistance: 2)
			.onChanged { value in
				if draggedIndex == nil {
					draggedIndex = index
					selectedTrackID = track.id
				}
				dragTranslation = value.translation.height
			}
			.onEnded { value in
				defer {
					draggedIndex = nil
					dragTranslation = 0
				}
				guard let from = draggedIndex else { return }
				let gap = RowInsertion.dragGapIndex(
					from: from,
					translation: value.translation.height,
					rowHeight: Theme.trackRowHeight,
					count: library.tracks.count
				)
				guard gap != from, gap != from + 1 else { return }
				library.move(fromOffsets: IndexSet(integer: from), toOffset: gap)
			}
	}

	/// The themed insertion line: a 2pt rule at the active gap.
	@ViewBuilder private var insertionLine: some View {
		if let gap = activeGapIndex {
			Rectangle()
				.fill(Theme.insertionLine)
				.frame(height: 2)
				.offset(y: CGFloat(gap) * Theme.trackRowHeight - 1)
				.allowsHitTesting(false)
		}
	}

	/// The gap to draw the line at: an external file drag, or an internal
	/// reorder drag pointing somewhere other than the row's own slot.
	private var activeGapIndex: Int? {
		if let external = externalGapIndex { return external }
		guard let from = draggedIndex else { return nil }
		let gap = RowInsertion.dragGapIndex(
			from: from,
			translation: dragTranslation,
			rowHeight: Theme.trackRowHeight,
			count: library.tracks.count
		)
		return (gap == from || gap == from + 1) ? nil : gap
	}

	/// Empty-library state doubling as the drop target (the track list handles
	/// drops once rows exist).
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
				Task {
					let urls = await LibraryViewModel.urls(from: providers)
					await library.addDropped(urls: urls)
				}
				return true
			}
	}
}

/// One library row: title + duration; the current track reads in accent orange,
/// the (single-click) selected row gets a lighter background.
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

/// External-file drops on the track list: tracks the insertion gap under the
/// cursor while a drag hovers (drives the themed line) and inserts there on
/// drop via `LibraryViewModel.addDropped(urls:at:)`.
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
		Task {
			let urls = await LibraryViewModel.urls(from: providers)
			await library.addDropped(urls: urls, at: index)
		}
		return true
	}
}
