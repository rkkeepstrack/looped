//
//  SyncWaveformCanvas.swift
//  looped
//
//  A `WaveformLiveCanvas` equivalent that draws **synchronously** (`rendersAsynchronously:
//  false`). The windowed renderer re-slices the visible chunk almost every refresh tick and
//  leans on a compensating `.offset` to keep the motion smooth; DSWaveformImage's async canvas
//  presents its redraw a frame late, so the fresh slice lags the offset and the seam shimmers
//  at the reslice cadence (bug-fixes.md #5). Drawing on the render pass commits the slice and
//  the offset together, killing the flicker. Same `WaveformImageDrawer` call as the library
//  view; only the presentation timing differs. Shared by the main waveform and the overview
//  strip.
//

import DSWaveformImage
import SwiftUI

struct SyncWaveformCanvas: View {
	let samples: [Float]
	let configuration: Waveform.Configuration
	var renderer: WaveformRenderer = LinearWaveformRenderer()

	@StateObject private var drawer = WaveformImageDrawer()

	var body: some View {
		Canvas(rendersAsynchronously: false) { context, size in
			context.withCGContext { cgContext in
				drawer.draw(waveform: samples, on: cgContext, with: configuration.with(size: size), renderer: renderer)
			}
		}
	}
}
