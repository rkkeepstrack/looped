//
//  WaveformView.swift
//  looped
//
//  Created by Raphael Kalinowsi on 30.10.25.
//

import AppKit
internal import AVFAudio
import DSWaveformImage
import DSWaveformImageViews
import SwiftUI

struct WaveformDisplayView: View {
	@EnvironmentObject var audioPlayer: AudioEngineController
	@EnvironmentObject var offsetCalculator: OffsetCalculator

	/// Bar thickness of the striped waveform; the stripe geometry is baked into
	/// the WaveformShape path, so the stroke width must match the config.
	private let barWidth: CGFloat = 2

	/// Noise-floor cutoff (dB) for waveform analysis. The analyzer maps
	/// `cutoff … 0 dB` across the full height, so a higher (less negative) floor
	/// compresses the visible range and makes peaks stand out — quiet passages
	/// drop to the baseline instead of everything looking evened-out. Tune to
	/// taste: −50 = flat/full range, −30 = punchy peaks.
	private let waveformNoiseFloor: Float = -35

	var body: some View {
		ZStack {
			if let url = audioPlayer.audioFile?.url {
				GeometryReader { geo in
					let viewportWidth = geo.size.width
					let height = geo.size.height
					// The whole song is rendered `zoom` × wider than the viewport so
					// it pans faster. `contentWidth` is that full rendered width.
					let contentWidth = viewportWidth * offsetCalculator.zoom

					ZStack {
						// Panning layer: the waveform + loop markers slide horizontally
						// so the "now" position sits under the fixed center iterator.
						waveformLayer(url: url, contentWidth: contentWidth, height: height)
							.frame(width: contentWidth, height: height, alignment: .leading)
							.offset(x: offsetCalculator.calculateOffsetForWaveform(
								progressInPercent: audioPlayer.getProgressInPercent()
							))

						// Fixed center iterator (playhead).
						Rectangle()
							.fill(Theme.iterator)
							.frame(width: 2)
					}
					.clipped()
					.onAppear { offsetCalculator.waveformWidth = viewportWidth }
					.onChange(of: viewportWidth) { _, newWidth in
						offsetCalculator.waveformWidth = newWidth
					}
				}
			} else {
				Text("No audio file loaded")
					.foregroundStyle(Theme.textSecondary)
					.frame(maxWidth: .infinity, minHeight: 120)
			}

			// Transparent overlay capturing scroll / drag to scrub the timeline.
			ScrollObserverView(
				offset: Binding(
					get: { offsetCalculator.currentScrollOffset },
					set: { offsetCalculator.currentScrollOffset = $0 }
				),
				onScrollChange: { _ in
					offsetCalculator.onScrollChange(
						progressInPercent: audioPlayer.getProgressInPercent(),
						currentTime: audioPlayer.currentTime
					)
				},
				onScrollEnd: {
					audioPlayer.jumpTo(time: offsetCalculator.calculateScrolledTimestamp(
						offset: offsetCalculator.currentScrollOffset,
						duration: audioPlayer.getDuration()
					))
					offsetCalculator.currentScrollOffset = 0
					offsetCalculator.isScrolling = false
				}
			)
		}
	}

	// MARK: - Panning layer

	@ViewBuilder
	private func waveformLayer(url: URL, contentWidth: CGFloat, height: CGFloat) -> some View {
		let progress = audioPlayer.getProgressInPercent()
		let playedWidth = max(0, min(contentWidth, CGFloat(progress) * contentWidth))
		let duration = audioPlayer.getDuration() ?? 0
		let loopA = duration > 0 ? audioPlayer.loopStart.0 : nil
		let loopB = duration > 0 ? audioPlayer.loopEnd.0 : nil

		ZStack(alignment: .leading) {
			// Shaded A–B loop region (only when both points are set, B after A).
			if let a = loopA, let b = loopB, b > a {
				let ax = offsetCalculator.calculateOffsetForLoopPoint(time: a, duration: duration)
				let bx = offsetCalculator.calculateOffsetForLoopPoint(time: b, duration: duration)
				Rectangle()
					.fill(Theme.loopRegion)
					.frame(width: max(0, bx - ax), height: height)
					.offset(x: ax)
			}

			// Striped waveform, drawn as two cached layers: a static "upcoming"
			// base and a "played" highlight revealed by an animating mask. Each
			// layer is Equatable on (url, width, color) so SwiftUI does NOT
			// re-stroke the (expensive, ~thousands of bars) path on every playhead
			// tick — only the cheap mask rectangle changes.
			StripedWaveform(url: url, contentWidth: contentWidth, color: Theme.waveformUpcoming, barWidth: barWidth, noiseFloor: waveformNoiseFloor)
				.equatable()
			StripedWaveform(url: url, contentWidth: contentWidth, color: Theme.waveformPlayed, barWidth: barWidth, noiseFloor: waveformNoiseFloor)
				.equatable()
				.mask(alignment: .leading) {
					Rectangle().frame(width: playedWidth)
				}

			// A / B loop markers.
			if let a = loopA {
				loopMarker(
					label: "A",
					color: Theme.loopMarkerA,
					x: offsetCalculator.calculateOffsetForLoopPoint(time: a, duration: duration),
					height: height
				)
			}
			if let b = loopB {
				loopMarker(
					label: "B",
					color: Theme.loopMarkerB,
					x: offsetCalculator.calculateOffsetForLoopPoint(time: b, duration: duration),
					height: height
				)
			}
		}
	}

	// MARK: - Loop marker

	/// A thin full-height line with a small labeled flag at the top, anchored to
	/// its song position (so it pans with the waveform).
	private func loopMarker(label: String, color: Color, x: CGFloat, height: CGFloat) -> some View {
		ZStack(alignment: .top) {
			Rectangle()
				.fill(color)
				.frame(width: 1.5, height: height)
			Text(label)
				.font(.caption2.weight(.bold))
				.foregroundStyle(Color.black)
				.padding(.horizontal, 5)
				.padding(.vertical, 1)
				.background(color, in: Capsule())
		}
		.frame(width: 1.5, height: height, alignment: .top)
		.offset(x: x - 0.75)
	}
}

// MARK: - Cached striped waveform layer

/// A single-color striped waveform for `url`. Runs its own `WaveformAnalyzer`
/// (so the noise floor is configurable, unlike DSWaveformImage's convenience
/// `WaveformView`) and renders the result via `WaveformShape`.
///
/// Conforms to `Equatable` (on url / width / color / floor) and is used via
/// `.equatable()` so SwiftUI reuses its rendered output while the playhead moves
/// — the striped path is only rebuilt when the audio, zoom width, color, or
/// floor actually change. Analysis is async and only re-runs when the key changes.
private struct StripedWaveform: View, Equatable {
	let url: URL
	let contentWidth: CGFloat
	let color: Color
	let barWidth: CGFloat
	let noiseFloor: Float

	/// ~2 samples per point (matches `scale` below) — the stripe renderer needs
	/// `width * scale` samples for the bars to space correctly.
	private let scale: CGFloat = 2

	@State private var samples: [Float] = []

	var body: some View {
		WaveformShape(samples: samples, configuration: configuration)
			.stroke(color, style: StrokeStyle(lineWidth: barWidth, lineCap: .round))
			.drawingGroup() // rasterize the striped path once; cheap to composite/mask
			.task(id: analysisKey) { await analyze() }
	}

	private var analysisKey: String {
		"\(url.absoluteString)|\(Int(contentWidth))|\(noiseFloor)"
	}

	private func analyze() async {
		guard contentWidth > 0 else { return }
		var analyzer = WaveformAnalyzer()
		analyzer.noiseFloorDecibelCutoff = noiseFloor
		let count = max(1, Int(contentWidth * scale))
		guard let result = try? await analyzer.samples(fromAudioAt: url, count: count) else { return }
		samples = result
	}

	private var configuration: Waveform.Configuration {
		Waveform.Configuration(
			style: .striped(.init(color: .gray, width: barWidth, spacing: 2, lineCap: .round)),
			scale: scale,
			verticalScalingFactor: 0.9,
			shouldAntialias: true
		)
	}

	// Explicit: @State storage isn't Equatable, and equality must ignore the
	// loaded samples anyway (they're derived from these inputs).
	static func == (lhs: StripedWaveform, rhs: StripedWaveform) -> Bool {
		lhs.url == rhs.url
			&& lhs.contentWidth == rhs.contentWidth
			&& lhs.color == rhs.color
			&& lhs.barWidth == rhs.barWidth
			&& lhs.noiseFloor == rhs.noiseFloor
	}
}
