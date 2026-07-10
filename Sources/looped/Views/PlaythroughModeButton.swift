//
//  PlaythroughModeButton.swift
//  looped
//
//  One button cycling the end-of-track playthrough mode (loop → advance →
//  stop), icon per mode, tooltip explaining the current one. A small
//  self-contained view so plan 07 can move it into the bottom-bar transport.
//

import SwiftUI

struct PlaythroughModeButton: View {
	@EnvironmentObject var player: PlayerViewModel

	var body: some View {
		Button {
			player.cyclePlaythroughMode()
		} label: {
			Image(systemName: icon)
				.foregroundStyle(Theme.controlActive)
				.frame(width: 20)
		}
		.buttonStyle(.bordered)
		.help(help)
	}

	private var icon: String {
		switch player.playthroughMode {
		case .loop: "repeat"
		case .advance: "text.line.first.and.arrowtriangle.forward"
		case .stop: "stop"
		}
	}

	private var help: String {
		switch player.playthroughMode {
		case .loop: "Loop: restart this track when it ends"
		case .advance: "Advance: play the next track when this one ends"
		case .stop: "Stop: stop playback when this track ends"
		}
	}
}
