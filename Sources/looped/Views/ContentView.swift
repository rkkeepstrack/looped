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
				SidebarView()
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
				Task { await library.handleWaveformDrop(providers: providers) }
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
