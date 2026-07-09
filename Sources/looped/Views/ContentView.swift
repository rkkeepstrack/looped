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
/// reorder drags both show the List's native insertion line at the drop point.
private struct Sidebar: View {
	@EnvironmentObject var library: LibraryViewModel
	/// Row picked by a single click — purely visual until a double-click plays it.
	@State private var selectedTrackID: UUID?
	/// A file drag is hovering the empty-library drop zone.
	@State private var emptyDropTargeted = false

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

	/// A themed plain List rather than a LazyVStack: List provides native
	/// drag-reorder (`onMove`) and external-drop insertion (`onInsert`), both
	/// drawing the standard insertion line between rows / below the last row.
	private var trackList: some View {
		List {
			ForEach(library.tracks) { track in
				TrackRow(
					track: track,
					isCurrent: track.id == library.currentTrackID,
					isSelected: track.id == selectedTrackID
				)
				// Single click selects instantly (also on the first
				// click of a double); the simultaneous double-click
				// loads the track into the waveform. Both taps must be
				// simultaneousGestures: a plain .onTapGesture claims the
				// mouse-down and the List's row drag (reordering) never starts.
				.simultaneousGesture(
					TapGesture().onEnded { selectedTrackID = track.id }
				)
				.simultaneousGesture(
					TapGesture(count: 2)
						.onEnded { Task { await library.load(track) } }
				)
				.listRowSeparator(.hidden)
				.listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
			}
			.onMove { source, destination in
				library.move(fromOffsets: source, toOffset: destination)
			}
			.onInsert(of: [.fileURL]) { index, providers in
				Task {
					let urls = await LibraryViewModel.urls(from: providers)
					await library.addDropped(urls: urls, at: index)
				}
			}
		}
		.listStyle(.plain)
		.scrollContentBackground(.hidden)
		// Cancel the List's built-in content inset so rows align with the
		// import button above.
		.padding(.horizontal, -10)
	}

	/// Empty-library state doubling as the drop target (the List handles drops
	/// once rows exist).
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
		)
		.contentShape(Rectangle())
		.onHover { hovering = $0 }
	}
}
