//
//  LoopingService.swift
//  looped
//
//  Pure loop DSP: slices an [A, B) region out of a source buffer and crossfades
//  the seam so it loops without a click or pitch artifact. Produces a buffer;
//  scheduling it is the caller's job (PlayerViewModel → PlaybackService), which
//  keeps this service free of engine/UI dependencies and trivially testable.
//

import AVFoundation

protocol LoopingService: Sendable {
	/// Returns a loop-ready copy of frames [startFrame, endFrame) from `source`,
	/// with a crossfaded seam, or `nil` if the range is invalid.
	func makeLoopBuffer(from source: AVAudioPCMBuffer, startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition) -> AVAudioPCMBuffer?
}

struct DefaultLoopingService: LoopingService {
	func makeLoopBuffer(from source: AVAudioPCMBuffer, startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition) -> AVAudioPCMBuffer? {
		let totalFrames = AVAudioFramePosition(source.frameLength)
		let start = max(0, min(startFrame, totalFrames))
		let end = max(start, min(endFrame, totalFrames))
		let frameCount = AVAudioFrameCount(end - start)

		guard frameCount > 0,
		      let out = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: frameCount),
		      let src = source.floatChannelData,
		      let dst = out.floatChannelData
		else { return nil }

		out.frameLength = frameCount
		let channelCount = Int(source.format.channelCount)
		let byteCount = Int(frameCount) * MemoryLayout<Float>.size
		for channel in 0 ..< channelCount {
			memcpy(dst[channel], src[channel] + Int(start), byteCount)
		}

		crossfadeSeam(out, src: src, endFrame: Int(end), totalFrames: Int(totalFrames), channelCount: channelCount)
		return out
	}

	/// Makes the `.loops` wrap (buffer end → buffer start) sample-continuous.
	///
	/// A hard cut at the loop point is a discontinuity that `AVAudioUnitTimePitch`
	/// turns into an audible pitch/warble artifact (worse the more it stretches).
	/// We blend the audio that *naturally follows* the loop end (`[end, end+fade)`)
	/// into the loop head with an equal-power ramp, so `buffer[0]` starts at
	/// `original[end]` — continuous with the buffer's last frame (`original[end-1]`)
	/// — then eases back to the true loop content over the fade.
	private func crossfadeSeam(_ buffer: AVAudioPCMBuffer, src: UnsafePointer<UnsafeMutablePointer<Float>>, endFrame: Int, totalFrames: Int, channelCount: Int) {
		guard let dst = buffer.floatChannelData else { return }

		let sampleRate = buffer.format.sampleRate
		let loopFrames = Int(buffer.frameLength)
		// ~12 ms, but never more than a quarter of the loop or the tail available
		// after `end` (the crossfade reads `fade` frames past the loop end).
		let available = totalFrames - endFrame
		let fade = min(Int(0.012 * sampleRate), loopFrames / 4, available)
		guard fade > 0 else { return }

		for channel in 0 ..< channelCount {
			let source = src[channel]
			let out = dst[channel]
			for i in 0 ..< fade {
				let t = Double(i) / Double(fade)
				let headWeight = sin(t * .pi / 2) // 0 → 1
				let postWeight = cos(t * .pi / 2) // 1 → 0
				let post = Double(source[endFrame + i]) // original[end + i]
				let head = Double(out[i]) // loop head (== original[start + i])
				out[i] = Float(post * postWeight + head * headWeight)
			}
		}
	}
}
