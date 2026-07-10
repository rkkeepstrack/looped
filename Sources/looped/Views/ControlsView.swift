//
//  ControlsView.swift
//  looped
//
//  Created by Raphael Kalinowsi on 30.10.25.
//

import SwiftUI

struct ControlsView: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel
	@EnvironmentObject var library: LibraryViewModel
	@EnvironmentObject var offsetCalculator: WaveformViewModel

	@State private var ratePosition: Double = 0.5 // normalized 0…1 (0.5 → 1.0×)
	@State private var pitchSemitones: Double = 0 // −12…+12, snapped to integers
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

	// MARK: Bottom-left — Volume + Rate + Pitch (+ sync)

	private var sliders: some View {
		VStack(spacing: 10) {
			CompactSlider(label: "Volume", value: $volume, defaultValue: 1.0, format: { v in
				"\(Int((v * 100).rounded())) %"
			}) { v in
				audioPlayer.updateVolume(volume: Float(v))
			}
			CompactSlider(label: audioPlayer.syncPitchAndRate ? "Speed" : "Rate", value: $ratePosition, defaultValue: 0.5, format: { pos in
				String(format: "%.2f×", 0.5 * pow(4, pos))
			}) { pos in
				// Logarithmic map so 0.5 sits at 1.0× and the range is ~0.5×–2×.
				audioPlayer.rate = Float(0.5 * pow(4, pos))
				audioPlayer.updateRate()
			}
			CompactSlider(label: "Pitch", value: pitchBinding, range: -12 ... 12, defaultValue: 0, format: { st in
				String(format: "%+d st", Int(st.rounded()))
			}) { st in
				audioPlayer.pitchSemitones = Float(st.rounded())
				audioPlayer.updatePitch()
			}
			.disabled(audioPlayer.syncPitchAndRate)
			.opacity(audioPlayer.syncPitchAndRate ? 0.5 : 1)

			// Synced = tape-style varispeed: the Speed slider moves tempo + pitch
			// together (artifact-free); the Pitch slider shows the implied shift.
			Toggle("Sync pitch & rate", isOn: Binding(
				get: { audioPlayer.syncPitchAndRate },
				set: { audioPlayer.updateSync($0) }
			))
			.toggleStyle(.checkbox)
			.font(.caption)
			.foregroundStyle(Theme.textSecondary)
			.help("One slider drives speed and pitch together (tape-style, highest quality)")
		}
	}

	/// While synced, the (disabled) pitch slider tracks the shift the varispeed
	/// implies; user edits only flow in independent mode.
	private var pitchBinding: Binding<Double> {
		Binding(
			get: {
				audioPlayer.syncPitchAndRate ? Double(audioPlayer.impliedSyncSemitones) : pitchSemitones
			},
			set: { pitchSemitones = $0.rounded() }
		)
	}

	// MARK: Bottom-center — transport

	private var transport: some View {
		HStack(spacing: 14) {
			Button {
				Task { await library.previous() }
			} label: {
				Image(systemName: "backward.fill")
					.frame(width: 28, height: 24)
			}
			.buttonStyle(.bordered)
			.controlSize(.large)
			.disabled(library.tracks.count < 2)
			.help("Previous track (restarts when > 3 s in)")

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
				Task { await library.next() }
			} label: {
				Image(systemName: "forward.fill")
					.frame(width: 28, height: 24)
			}
			.buttonStyle(.bordered)
			.controlSize(.large)
			.disabled(library.tracks.count < 2)
			.help("Next track")

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
	/// Clicking the label ("Reset" on hover) snaps back to this value.
	var defaultValue: Double = 0
	/// Human-friendly rendering of the current value, shown in place of the
	/// label while dragging (bug-fixes.md #3).
	var format: (Double) -> String
	var onChange: (Double) -> Void

	@State private var isDragging = false
	@State private var isHoveringLabel = false

	/// Dragging wins (live value), then hover ("Reset"), then the plain label.
	private var labelText: String {
		if isDragging { return format(value) }
		return isHoveringLabel ? "Reset" : label
	}

	var body: some View {
		VStack(spacing: 4) {
			Text(labelText)
				.font(.caption)
				.foregroundStyle(isDragging || isHoveringLabel ? Theme.textPrimary : Theme.textSecondary)
				.monospacedDigit()
				.contentShape(Rectangle())
				.onHover { isHoveringLabel = $0 }
				.onTapGesture { value = defaultValue }
				.help("Reset to default")
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

/// A/B loop points + reset, in their own card. The `«`/`»` arrows nudge the set
/// point by ±0.05 s; disabled while unset.
private struct LoopPanel: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel

	var body: some View {
		VStack(spacing: 8) {
			Text("Loop")
				.font(.caption.weight(.semibold))
				.foregroundStyle(Theme.textSecondary)

			loopRow(symbol: "a.circle", isSet: audioPlayer.loopStart.1 != nil, set: {
				audioPlayer.setLoopStart(time: audioPlayer.currentTime)
			}, nudge: { delta in
				audioPlayer.nudgeLoopStart(by: delta)
			})
			loopRow(symbol: "b.circle", isSet: audioPlayer.loopEnd.1 != nil, set: {
				audioPlayer.setLoopEnd(time: audioPlayer.currentTime)
			}, nudge: { delta in
				audioPlayer.nudgeLoopEnd(by: delta)
			})

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

	/// Per-click nudge step for the chevron buttons.
	private static let nudgeStep: TimeInterval = 0.05

	private func loopRow(symbol: String, isSet: Bool, set: @escaping () -> Void, nudge: @escaping (TimeInterval) -> Void) -> some View {
		HStack(spacing: 8) {
			Button { nudge(-Self.nudgeStep) } label: { Image(systemName: "chevron.backward.2") }
				.buttonStyle(.borderless)
				.disabled(!isSet)
				.help("Nudge earlier by 0.05 s")

			Button(action: set) {
				Image(systemName: isSet ? "\(symbol).fill" : symbol)
					.font(.title3)
			}
			.buttonStyle(.borderless)
			.foregroundStyle(isSet ? Theme.accent : Theme.textPrimary)

			Button { nudge(Self.nudgeStep) } label: { Image(systemName: "chevron.forward.2") }
				.buttonStyle(.borderless)
				.disabled(!isSet)
				.help("Nudge later by 0.05 s")
		}
	}
}
