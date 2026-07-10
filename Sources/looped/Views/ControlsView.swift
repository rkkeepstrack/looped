//
//  ControlsView.swift
//  looped
//
//  Created by Raphael Kalinowsi on 30.10.25.
//

import SwiftUI

/// Aligns the slider *tracks* (not the label+slider stacks — the labels sit on
/// top and would drag the geometric center down) with the transport row.
/// `CompactSlider` marks its track; everything else falls back to its center.
private extension VerticalAlignment {
	enum ControlRow: AlignmentID {
		static func defaultValue(in context: ViewDimensions) -> CGFloat {
			context[VerticalAlignment.center]
		}
	}

	static let controlRow = VerticalAlignment(ControlRow.self)
}

struct ControlsView: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel
	@EnvironmentObject var library: LibraryViewModel
	@EnvironmentObject var offsetCalculator: WaveformViewModel

	var body: some View {
		// The transport is pinned to the exact viewport center (both side slots
		// get equal flexible width); sliders and loop panel hug it from either side.
		HStack(alignment: .controlRow, spacing: 44) {
			HStack(alignment: .controlRow, spacing: 28) {
				volumeSlider
				ratePitchCluster
			}
			.frame(maxWidth: .infinity, alignment: .trailing)

			transport

			LoopPanel()
				.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(.horizontal)
		.padding(.vertical, 16)
	}

	// MARK: Sliders — volume + the rate/pitch pair with the sync link

	private var volumeSlider: some View {
		CompactSlider(label: "Volume", value: volumeBinding, defaultValue: 1.0, format: { v in
			"\(Int((v * 100).rounded())) %"
		}) { _ in
			audioPlayer.updateVolume()
		}
	}

	/// Independent mode: Rate + Pitch stacked. Synced: the pair collapses into a
	/// single Speed slider (tempo + pitch move together, nothing else to show).
	private var ratePitchCluster: some View {
		HStack(alignment: .controlRow, spacing: 6) {
			VStack(spacing: 6) {
				CompactSlider(label: audioPlayer.syncPitchAndRate ? "Speed" : "Rate", value: ratePositionBinding, defaultValue: 0.5, format: { pos in
					String(format: "%.2f×", 0.5 * pow(4, pos))
				}) { _ in
					audioPlayer.updateRate()
				}
				if !audioPlayer.syncPitchAndRate {
					CompactSlider(label: "Pitch", value: pitchBinding, range: -12 ... 12, defaultValue: 0, format: { st in
						String(format: "%+d st", Int(st.rounded()))
					}) { _ in
						audioPlayer.updatePitch()
					}
				}
			}
			syncButton
		}
	}

	/// The sync toggle beside the sliders — a lock ("pitch locked to speed"),
	/// closed and yellow while synced (tape-style varispeed: the Speed slider
	/// moves tempo + pitch together).
	private var syncButton: some View {
		Button {
			audioPlayer.updateSync(!audioPlayer.syncPitchAndRate)
		} label: {
			Image(systemName: audioPlayer.syncPitchAndRate ? "lock.fill" : "lock.open")
				.font(.body)
				.foregroundStyle(audioPlayer.syncPitchAndRate ? Theme.controlActive : Theme.textSecondary)
				.frame(width: 24, height: 24)
		}
		.buttonStyle(.borderless)
		.hoverHighlight()
		.help("Sync pitch & rate: one slider drives speed and pitch together (tape-style, highest quality)")
	}

	// The view-model is the source of truth for all slider values (they are
	// per-track: switching tracks swaps them), so the sliders bind through it.

	private var volumeBinding: Binding<Double> {
		Binding(
			get: { Double(audioPlayer.volume) },
			set: { audioPlayer.volume = Float($0) }
		)
	}

	/// Normalized 0…1 slider position ↔ rate, mapped logarithmically so 0.5
	/// sits at 1.0× and the range is ~0.5×–2×.
	private var ratePositionBinding: Binding<Double> {
		Binding(
			get: { Double(log2(audioPlayer.rate * 2) / 2) },
			set: { audioPlayer.rate = Float(0.5 * pow(4, $0)) }
		)
	}

	private var pitchBinding: Binding<Double> {
		Binding(
			get: { Double(audioPlayer.pitchSemitones) },
			set: { audioPlayer.pitchSemitones = Float($0.rounded()) }
		)
	}

	// MARK: Transport toolbar

	private var transport: some View {
		HStack(spacing: 10) {
			transportButton("stop.fill", help: "Stop and reset to the start") {
				audioPlayer.stop()
				offsetCalculator.currentScrollOffset = 0
			}

			transportButton("play.fill", help: "Play (restarts when already playing)", prominent: true) {
				audioPlayer.play()
			}

			transportButton("pause.fill", help: "Pause") {
				audioPlayer.pause()
			}

			transportButton("backward.fill", help: "Previous track (restarts when > 3 s in)") {
				Task { await library.previous() }
			}
			.disabled(library.tracks.count < 2)

			transportButton("forward.fill", help: "Next track") {
				Task { await library.next() }
			}
			.disabled(library.tracks.count < 2)

			PlaythroughModeButton()
		}
	}

	@ViewBuilder
	private func transportButton(_ symbol: String, help: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
		let button = Button(action: action) {
			Image(systemName: symbol)
				.frame(width: 24, height: 18)
		}
		.help(help)

		if prominent {
			button.buttonStyle(.borderedProminent).tint(Theme.accent).hoverBrightness()
		} else {
			button.buttonStyle(.bordered).hoverBrightness()
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

	var body: some View {
		VStack(spacing: 2) {
			// Dragging wins (live value), then hover ("Reset"), then the label.
			HoverActionLabel(title: label, overrideText: isDragging ? format(value) : nil) {
				value = defaultValue
			}
			.help("Reset to default")
			Slider(value: $value, in: range) { editing in
				isDragging = editing
			}
			.controlSize(.mini)
			.tint(Theme.accent)
			.onChange(of: value) { _, newValue in onChange(newValue) }
			.alignmentGuide(.controlRow) { $0[VerticalAlignment.center] }
		}
		.frame(width: 150)
		.onRightClick { value = defaultValue }
	}
}

// MARK: - Loop panel (A·B)

/// A/B loop points with nudge arrows (±0.05 s, disabled while unset); the
/// title doubles as the reset control (hover → "Reset").
private struct LoopPanel: View {
	@EnvironmentObject var audioPlayer: PlayerViewModel

	var body: some View {
		VStack(spacing: 4) {
			// Same affordance as the slider labels: the title turns into "Reset"
			// on hover; clicking clears both points.
			HoverActionLabel(title: "Loop Points") {
				audioPlayer.clearLoopPoints()
			}
			.help("Reset loop points")

			loopRows
		}
		.padding(.horizontal, 24)
		.padding(.vertical, 8)
		.background(RoundedRectangle(cornerRadius: Theme.panelCorner).fill(Theme.surface))
		.overlay(RoundedRectangle(cornerRadius: Theme.panelCorner).stroke(Theme.panelBorder))
	}

	@ViewBuilder
	private var loopRows: some View {
		loopRow(symbol: "a.circle", color: Theme.loopMarkerA, isSet: audioPlayer.loopStart.1 != nil, set: {
			audioPlayer.setLoopStart(time: audioPlayer.currentTime)
		}, clear: {
			audioPlayer.setLoopStart(time: nil)
		}, nudge: { delta in
			audioPlayer.nudgeLoopStart(by: delta)
		})
		loopRow(symbol: "b.circle", color: Theme.loopMarkerB, isSet: audioPlayer.loopEnd.1 != nil, set: {
			audioPlayer.setLoopEnd(time: audioPlayer.currentTime)
		}, clear: {
			audioPlayer.setLoopEnd(time: nil)
		}, nudge: { delta in
			audioPlayer.nudgeLoopEnd(by: delta)
		})
	}

	/// Per-click nudge step for the chevron buttons.
	private static let nudgeStep: TimeInterval = 0.05

	private func loopRow(symbol: String, color: Color, isSet: Bool, set: @escaping () -> Void, clear: @escaping () -> Void, nudge: @escaping (TimeInterval) -> Void) -> some View {
		HStack(spacing: 8) {
			Button { nudge(-Self.nudgeStep) } label: { Image(systemName: "chevron.backward.2") }
				.buttonStyle(.borderless)
				.hoverHighlight()
				.disabled(!isSet)
				.help("Nudge earlier by 0.05 s")

			Button(action: set) {
				Image(systemName: isSet ? "\(symbol).fill" : symbol)
					.font(.title3)
			}
			.buttonStyle(.borderless)
			.foregroundStyle(isSet ? color : Theme.textPrimary)
			.hoverHighlight()
			.onRightClick { if isSet { clear() } }
			.help("Set to the current time; right-click to clear")

			Button { nudge(Self.nudgeStep) } label: { Image(systemName: "chevron.forward.2") }
				.buttonStyle(.borderless)
				.hoverHighlight()
				.disabled(!isSet)
				.help("Nudge later by 0.05 s")
		}
	}
}
