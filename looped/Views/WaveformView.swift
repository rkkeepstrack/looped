//
//  ControlsView.swift
//  looped
//
//  Created by Raphael Kalinowsi on 30.10.25.
//

import SwiftUI
import DSWaveformImage
import DSWaveformImageViews
internal import AVFAudio

struct WaveformView: View {
	@EnvironmentObject var audioPlayer: AudioEngineController
	@EnvironmentObject var offsetCalculator: OffsetCalculator
	
	var body: some View {
		ZStack {
			if let url = audioPlayer.audioFile?.url {
				GeometryReader { geo in
					ZStack {
						
						
						DSWaveformImageViews.WaveformView(audioURL: url) { waveformShape in
							
							waveformShape.fill(
								LinearGradient(
									stops: [
										Gradient.Stop(color: .red, location: 0),
										Gradient.Stop(color: .red, location: offsetCalculator.calculateGradientWhileScrolling(progressInPercent: audioPlayer.getProgressInPercent())),
										Gradient.Stop(color: .blue, location: offsetCalculator.calculateGradientWhileScrolling(progressInPercent: audioPlayer.getProgressInPercent()) + 0.0001),
										Gradient.Stop(color: .blue, location: 1)
									],
									startPoint: .leading,
									endPoint: .trailing
								)
							)

								if(audioPlayer.loopStart.0 != nil) {
									ZStack {
										Rectangle().fill(.orange).frame(width: 1, height: geo.size.height)
										Text("A").offset(y: +100)
										// Text("Offset \(offsetCalculator.calculateOffsetForLoopPoint(time: audioPlayer.loopStart.0 ?? 0, duration: audioPlayer.getDuration() ?? 0))").offset(y: +150)
									}.offset(x: offsetCalculator.calculateOffsetForLoopPoint(time: audioPlayer.loopStart.0 ?? 0, duration: audioPlayer.getDuration() ?? 0))
								}
								
								if(audioPlayer.loopEnd.0 != nil) {
									ZStack{
										Rectangle().fill(.pink).frame(width: 1, height: geo.size.height)
										Text("B").offset(y: +100)
										// Text("Offset \(offsetCalculator.calculateOffsetForLoopPoint(time: audioPlayer.loopEnd.0 ?? 0, duration: audioPlayer.getDuration() ?? 0))").offset(y: +150)
									}.offset(x: offsetCalculator.calculateOffsetForLoopPoint(time: audioPlayer.loopEnd.0 ?? 0, duration: audioPlayer.getDuration() ?? 0))
								}
						}.offset(x: offsetCalculator.calculateOffsetForWaveform(progressInPercent: audioPlayer.getProgressInPercent()))
						
						Rectangle().fill(.yellow).frame(width: 1)
					}.onAppear {
						offsetCalculator.waveformWidth = geo.size.width
					}
				}
			} else {
				Text("No audio file loaded").frame(height: 120)
			}
			ScrollObserverView(
				offset: Binding(
					get: { offsetCalculator.currentScrollOffset },
					set: { offsetCalculator.currentScrollOffset = $0 }
				),
				onScrollChange: { _ in
					offsetCalculator.onScrollChange(progressInPercent: audioPlayer.getProgressInPercent(), currentTime: audioPlayer.currentTime)
				},
				onScrollEnd: {
					audioPlayer.jumpTo(time: offsetCalculator.calculateScrolledTimestamp(offset: offsetCalculator.currentScrollOffset, duration: audioPlayer.getDuration()))
					offsetCalculator.currentScrollOffset = 0
					offsetCalculator.isScrolling = false
				}
			)
		}
	}
}
