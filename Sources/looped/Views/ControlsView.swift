//
//  ControlsView.swift
//  looped
//
//  Created by Raphael Kalinowsi on 30.10.25.
//

import SwiftUI

struct ControlsView: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel
	@EnvironmentObject var offsetCalculator: WaveformViewModel

	@State private var ratePosition: Double = 0.5 // normalized 0…1 (0.5 → 1.0×)
	@State private var volume: Double = 1.0

	var body: some View {
		// Sliders pinned left, loop panel pinned right, transport centered over the
		// content column (independent of the side elements' widths) — so it stays
		// centered as the sidebar pushes everything right.
		ZStack {
			HStack(spacing: 24) {
				sliders
				Spacer()
				LoopPanel()
			}
			transport
		}
		.padding()
	}

	// MARK: Bottom-left — Volume + Pitch

	private var sliders: some View {
		VStack(spacing: 12) {
			CompactSlider(label: "Volume", value: $volume, format: { v in
				"\(Int((v * 100).rounded())) %"
			}) { v in
				audioPlayer.updateVolume(volume: Float(v))
			}
			CompactSlider(label: "Pitch", value: $ratePosition, format: { pos in
				String(format: "%.2f×", 0.5 * pow(4, pos))
			}) { pos in
				// Logarithmic map so 0.5 sits at 1.0× and the range is ~0.5×–2×.
				audioPlayer.rate = Float(0.5 * pow(4, pos))
				audioPlayer.updateRate()
			}
		}
	}

	// MARK: Bottom-center — transport

	private var transport: some View {
		HStack(spacing: 14) {
			Button {
				audioPlayer.togglePlayPause()
			} label: {
				Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
					.frame(width: 28, height: 24)
			}
			.buttonStyle(.borderedProminent)
			.tint(Theme.accent)
			.controlSize(.large)

			Button {
				audioPlayer.stop()
				offsetCalculator.currentScrollOffset = 0
			} label: {
				Image(systemName: "stop.fill")
					.frame(width: 28, height: 24)
			}
			.buttonStyle(.bordered)
			.controlSize(.large)
		}
	}
}

// MARK: - Compact labeled slider (native Slider, themed)

private struct CompactSlider: View {
	let label: String
	@Binding var value: Double
	var range: ClosedRange<Double> = 0 ... 1
	/// Human-friendly rendering of the current value, shown in place of the
	/// label while dragging (bug-fixes.md #3).
	var format: (Double) -> String
	var onChange: (Double) -> Void

	@State private var isDragging = false

	var body: some View {
		VStack(spacing: 4) {
			Text(isDragging ? format(value) : label)
				.font(.caption)
				.foregroundStyle(isDragging ? Theme.textPrimary : Theme.textSecondary)
				.monospacedDigit()
			Slider(value: $value, in: range) { editing in
				isDragging = editing
			}
			.controlSize(.small)
			.tint(Theme.accent)
			.onChange(of: value) { _, newValue in onChange(newValue) }
		}
		.frame(width: 190)
	}
}

// MARK: - Loop panel (bottom-right card)

/// A/B loop points + reset, in their own card. The `«`/`»` nudge arrows are laid
/// out here but disabled — they get wired to fine-adjust in Plan 5.
private struct LoopPanel: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel

	var body: some View {
		VStack(spacing: 8) {
			Text("Loop")
				.font(.caption.weight(.semibold))
				.foregroundStyle(Theme.textSecondary)

			loopRow(symbol: "a.circle", isSet: audioPlayer.loopStart.1 != nil) {
				audioPlayer.setLoopStart(time: audioPlayer.currentTime)
			}
			loopRow(symbol: "b.circle", isSet: audioPlayer.loopEnd.1 != nil) {
				audioPlayer.setLoopEnd(time: audioPlayer.currentTime)
			}

			Button("Reset Loop") {
				audioPlayer.setLoopStart(time: nil)
				audioPlayer.setLoopEnd(time: nil)
			}
			.buttonStyle(.borderless)
			.font(.caption)
		}
		.padding(12)
		.background(RoundedRectangle(cornerRadius: Theme.panelCorner).fill(Theme.surface))
		.overlay(RoundedRectangle(cornerRadius: Theme.panelCorner).stroke(Theme.panelBorder))
	}

	private func loopRow(symbol: String, isSet: Bool, set: @escaping () -> Void) -> some View {
		HStack(spacing: 8) {
			Button {} label: { Image(systemName: "chevron.backward.2") }
				.buttonStyle(.borderless)
				.disabled(true) // nudge → Plan 5

			Button(action: set) {
				Image(systemName: isSet ? "\(symbol).fill" : symbol)
					.font(.title3)
			}
			.buttonStyle(.borderless)
			.foregroundStyle(isSet ? Theme.accent : Theme.textPrimary)

			Button {} label: { Image(systemName: "chevron.forward.2") }
				.buttonStyle(.borderless)
				.disabled(true) // nudge → Plan 5
		}
	}
}
