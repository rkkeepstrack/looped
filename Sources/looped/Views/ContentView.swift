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
			WaveformDisplayView()
			Divider()
			ControlsView()
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

/// Collapsible left panel: the import button + the track library list.
private struct Sidebar: View {
	@EnvironmentObject var library: LibraryViewModel

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
				Text("Your tracks will appear here")
					.font(.caption)
					.foregroundStyle(Theme.textSecondary)
			} else {
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 2) {
						ForEach(library.tracks) { track in
							TrackRow(track: track, isCurrent: track.id == library.currentTrackID)
								.onTapGesture {
									Task { await library.play(track) }
								}
						}
					}
				}
			}

			Spacer(minLength: 0)
		}
		.padding(.horizontal, 12)
		.padding(.top, 48) // clear the top-left toggle
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.background(Theme.surface)
	}
}

/// One library row: title + duration; the current track reads in accent orange.
private struct TrackRow: View {
	let track: Track
	let isCurrent: Bool
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
				.fill(hovering ? Color.white.opacity(0.06) : Color.clear)
		)
		.contentShape(Rectangle())
		.onHover { hovering = $0 }
	}
}
