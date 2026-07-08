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

	var body: some View {
		HStack(spacing: 0) {
			if sidebarOpen {
				Sidebar()
					.frame(width: Theme.sidebarWidth)
					.transition(.move(edge: .leading))
				Divider()
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

/// Collapsible left panel. For now it holds the import button; the track list
/// lands here in Plan 5.
private struct Sidebar: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Button {
				Task { await audioPlayer.openFile() }
			} label: {
				Label("Import File", systemImage: "square.and.arrow.down")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.bordered)
			.controlSize(.large)

			Text("Your tracks will appear here")
				.font(.caption)
				.foregroundStyle(Theme.textSecondary)

			Spacer()
		}
		.padding(.horizontal, 12)
		.padding(.top, 48) // clear the top-left toggle
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.background(Theme.surface)
	}
}
