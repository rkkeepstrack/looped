//
//  AudioEngineController.swift
//  looped
//
//  Created by Raphael Kalinowski on 28.09.25.
//

import AVFoundation
internal import Combine
import Foundation
import SwiftUI

class AudioEngineController: ObservableObject {
	@Published var waveform: Any? = nil

	enum AudioEngineControllerError: Error {
		case bufferCreationFailed
		case nameTooShort(nameLength: Int)
	}

	@Published var isPlaying = false
	@Published var rate: Float = 1.0
	@Published var timePitch = AVAudioUnitTimePitch()

	@Published var loopStart: (TimeInterval?, AVAudioFramePosition?) = (timeInterval: nil, frame: nil)
	@Published var loopEnd: (TimeInterval?, AVAudioFramePosition?) = (timeInterval: nil, frame: nil)

	@Published var currentTime: TimeInterval = 0
	@Published var currentFileName: String?
	@Published var audioFile: AVAudioFile?
	@Published var rawSamples: [Float] = []

	var pausedTime: TimeInterval = 0.0

	private let engine = AVAudioEngine()
	private let player = AVAudioPlayerNode()
	private var lastPausedTime: TimeInterval = 0
	private var timeUpdateTimer: Timer?
	private var fullBuffer: AVAudioPCMBuffer?
	/// Whether the player currently has audio scheduled (file, segment, or loop
	/// buffer). Tracked explicitly because `player.lastRenderTime` is an unreliable
	/// "is something scheduled" signal.
	private var isScheduled: Bool = false
	/// The sliced [A, B] region scheduled with `.loops` while looping.
	private var loopBuffer: AVAudioPCMBuffer?
	private var isLooping: Bool = false

	@Published var duration: TimeInterval?

	init() {
		engine.attach(player)
		engine.attach(timePitch)
		engine.connect(player, to: timePitch, format: nil)
		engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
		do { try engine.start() } catch { print("Engine failed: \(error)") }
	}

	// MARK: - File Loading

	func openFile() async {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [UTType.wav, UTType.mp3, UTType.aiff]
		panel.allowsMultipleSelection = false
		if panel.runModal() == .OK, let url = panel.url {
			do {
				try await load(url: url)
			} catch { print("Could not load file: \(error)") }
		}
	}

	func load(url: URL) async throws {
		let file = try AVAudioFile(forReading: url)
		audioFile = file
		let format = file.processingFormat
		currentFileName = url.lastPathComponent

		// Reconnect the graph at the file's sample rate. `scheduleFile`/`Segment`
		// sample-rate-convert automatically, but `scheduleBuffer` (used for looping)
		// plays raw samples at the node's output rate — so if the connection format
		// (defaulted to hardware rate in `init`) differs from the file, the loop
		// buffer plays at the wrong pitch. Matching the format keeps both paths in sync.
		player.stop()
		isScheduled = false
		engine.connect(player, to: timePitch, format: format)
		engine.connect(timePitch, to: engine.mainMixerNode, format: format)

		// Read file into single buffer
		let capacity = AVAudioFrameCount(file.length) // file.length is AVAudioFramePosition (Int64)
		guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
			throw AudioEngineControllerError.bufferCreationFailed
		}
		try file.read(into: buffer, frameCount: capacity)
		buffer.frameLength = capacity // <‑‑ VERY IMPORTANT
		fullBuffer = buffer
		await loadDuration()
	}

	// MARK: - Playback

	func togglePlayPause() {
		guard audioFile != nil else { return }
		if isPlaying == false {
			play()
		} else {
			pause()
		}
	}

	private func play() {
		if !isScheduled {
			if isLooping, let loopBuffer {
				player.scheduleBuffer(loopBuffer, at: nil, options: [.loops], completionHandler: nil)
				isScheduled = true
			} else if let file = audioFile {
				player.scheduleFile(file, at: nil)
				isScheduled = true
			}
		}

		player.play()
		isPlaying = true
		startUpdatingCurrentTime()
	}

	private func pause() {
		player.pause()
		isPlaying = false
		stopUpdatingCurrentTime()
	}

	func stop() {
		player.stop()
		stopUpdatingCurrentTime()
		isScheduled = false
		lastPausedTime = 0
		currentTime = 0
		isPlaying = false
	}

	func updateRate() {
		timePitch.rate = rate
	}

	func updateVolume(volume: Float) {
		player.volume = volume
	}

	// MARK: - Timers

	func startUpdatingCurrentTime() {
		timeUpdateTimer?.invalidate()
		let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
			guard let self = self else { return }
			currentTime = self.getCurrentTime() ?? lastPausedTime

			// Looping is handled seamlessly by the `.loops` buffer, so the file
			// never "ends" while a loop is active.
			if !self.isLooping, reachedEndOfFile() {
				self.stop()
			}
		}
		// Add in `.common` modes so the waveform keeps updating during AppKit event
		// tracking (button clicks, scrolling). A `scheduledTimer` uses `.default`
		// mode only, which is paused while tracking — that froze the UI on any click.
		RunLoop.main.add(timer, forMode: .common)
		timeUpdateTimer = timer
	}

	func stopUpdatingCurrentTime() {
		timeUpdateTimer?.invalidate()
		timeUpdateTimer = nil
	}

	private func getCurrentTime() -> TimeInterval? {
		guard let nodeTime = player.lastRenderTime,
		      let playerTime = player.playerTime(forNodeTime: nodeTime) else { return nil }
		let rateAdjustedTime = Double(playerTime.sampleTime) / (playerTime.sampleRate * Double(timePitch.rate))

		// While looping, the render clock keeps counting across loop iterations;
		// fold it back into the [A, B] window so the reported time stays in range.
		if isLooping, let start = loopStart.0, let end = loopEnd.0, end > start {
			let loopLength = end - start
			return start + rateAdjustedTime.truncatingRemainder(dividingBy: loopLength)
		}

		return lastPausedTime + rateAdjustedTime
	}

	// MARK: - Jump

	func jumpTo(time: TimeInterval) {
		guard let file = audioFile else { return }

		// A manual seek leaves loop mode; markers stay set so the loop can be
		// re-armed, but playback becomes linear again.
		if isLooping {
			isLooping = false
			loopBuffer = nil
		}

		var wasPlaying = false

		if isPlaying {
			wasPlaying = true
			player.stop()
			stopUpdatingCurrentTime()
		}
		// Calculate start frame from time

		let startFrame = AVAudioFramePosition(time * file.processingFormat.sampleRate)
		let frameCount = AVAudioFrameCount(file.length - startFrame)

		player.scheduleSegment(
			file,
			startingFrame: startFrame,
			frameCount: frameCount,
			at: nil, // play as soon as possible
			completionHandler: nil
		)
		isScheduled = true

		lastPausedTime = time
		currentTime = time

		if wasPlaying {
			startUpdatingCurrentTime()
			player.play()
		}
	}

	// MARK: Looping

	func setLoopStart(time: TimeInterval?) {
		loopStart = (time, framePosition(for: time))
		refreshLoop()
	}

	func setLoopEnd(time: TimeInterval?) {
		loopEnd = (time, framePosition(for: time))
		refreshLoop()
	}

	func framePosition(for time: TimeInterval?) -> AVAudioFramePosition? {
		guard let file = audioFile, let t = time else { return nil }

		return AVAudioFramePosition(t * file.processingFormat.sampleRate)
	}

	/// Arms the loop when both points form a valid [A, B) range, otherwise
	/// disarms it. Called whenever a loop point changes.
	private func refreshLoop() {
		if let startFrame = loopStart.1, let endFrame = loopEnd.1, startFrame < endFrame {
			activateLoop()
		} else if isLooping {
			deactivateLoop()
		}
	}

	/// Slices the [A, B) region out of `fullBuffer` and schedules it with
	/// `.loops`, so the audio graph loops it seamlessly (sample-accurate, no poll).
	private func activateLoop() {
		guard let startFrame = loopStart.1, let endFrame = loopEnd.1, startFrame < endFrame,
		      let buffer = makeLoopBuffer(startFrame: startFrame, endFrame: endFrame)
		else { return }

		let wasPlaying = isPlaying
		loopBuffer = buffer
		isLooping = true

		player.stop()
		stopUpdatingCurrentTime()
		player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
		isScheduled = true

		lastPausedTime = loopStart.0 ?? 0
		currentTime = loopStart.0 ?? 0

		if wasPlaying {
			player.play()
			startUpdatingCurrentTime()
		}
	}

	/// Leaves loop mode and restores normal full-file playback from the current
	/// position, preserving play/pause state.
	private func deactivateLoop() {
		guard isLooping else { return }
		isLooping = false
		loopBuffer = nil
		// jumpTo reschedules the full file from `currentTime` and keeps play state.
		jumpTo(time: currentTime)
	}

	/// Copies frames [startFrame, endFrame) from `fullBuffer` into a new buffer and
	/// crossfades the seam so it loops without a click or pitch artifact.
	private func makeLoopBuffer(startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition) -> AVAudioPCMBuffer? {
		guard let fullBuffer else { return nil }

		let totalFrames = AVAudioFramePosition(fullBuffer.frameLength)
		let start = max(0, min(startFrame, totalFrames))
		let end = max(start, min(endFrame, totalFrames))
		let frameCount = AVAudioFrameCount(end - start)

		guard frameCount > 0,
		      let out = AVAudioPCMBuffer(pcmFormat: fullBuffer.format, frameCapacity: frameCount),
		      let src = fullBuffer.floatChannelData,
		      let dst = out.floatChannelData
		else { return nil }

		out.frameLength = frameCount
		let channelCount = Int(fullBuffer.format.channelCount)
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

	// MARK: Load Duration

	func loadDuration() async {
		guard let url = audioFile?.url else { return }
		let asset = AVURLAsset(url: url)
		do {
			let duration = try await asset.load(.duration)
			self.duration = CMTimeGetSeconds(duration)
		} catch {
			print("Failed to load duration: \(error)")
		}
	}

	func reachedEndOfFile() -> Bool {
		guard let duration else { return false }
		return currentTime >= duration
	}

	// MARK: Getters

	func getProgressInPercent() -> Double {
		guard let duration = getDuration(), duration > 0 else { return 0 }

		return currentTime / duration
	}

	func getDuration() -> TimeInterval? {
		return duration ?? nil
	}
}
