//
//  PlaybackService.swift
//  looped
//
//  The audio "player": owns the AVAudioEngine graph
//  (AVAudioPlayerNode → AVAudioUnitTimePitch → mainMixerNode) and the transport
//  (play/pause/stop/seek), loop scheduling, and the playback clock. No SwiftUI,
//  no @Published — it's a plain service the view-model drives and can be mocked.
//

import AVFoundation

protocol PlaybackService: AnyObject {
	/// Point the engine at a freshly loaded track (reconnects at its sample rate).
	func setSource(file: AVAudioFile, format: AVAudioFormat)
	func play()
	func pause()
	func stop()
	/// Seek to `time` in the full file; exits loop mode; preserves play state.
	func seek(to time: TimeInterval)
	/// Schedule a pre-sliced loop buffer to repeat seamlessly (`.loops`).
	func scheduleLoop(_ buffer: AVAudioPCMBuffer, startTime: TimeInterval, length: TimeInterval)
	/// Leave loop mode and resume normal full-file playback from `time`.
	func clearLoop(resumeAt time: TimeInterval)
	var isLooping: Bool { get }
	/// Current playback position in the source timeline (folded into [A, B] while looping).
	func currentTime() -> TimeInterval
	func setRate(_ rate: Float)
	func setVolume(_ volume: Float)
}

final class AVPlaybackService: PlaybackService {
	private let engine = AVAudioEngine()
	private let player = AVAudioPlayerNode()
	private let timePitch = AVAudioUnitTimePitch()

	private var file: AVAudioFile?
	private var isScheduled = false
	private var lastPausedTime: TimeInterval = 0

	private var loopBuffer: AVAudioPCMBuffer?
	private(set) var isLooping = false
	private var loopStartTime: TimeInterval = 0
	private var loopLength: TimeInterval = 0

	init() {
		engine.attach(player)
		engine.attach(timePitch)
		engine.connect(player, to: timePitch, format: nil)
		engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
		do { try engine.start() } catch { print("Engine failed: \(error)") }
	}

	// MARK: - Source

	func setSource(file: AVAudioFile, format: AVAudioFormat) {
		player.stop()
		isScheduled = false
		isLooping = false
		loopBuffer = nil
		lastPausedTime = 0
		self.file = file

		// Reconnect at the file's sample rate. `scheduleFile`/`Segment` sample-rate
		// convert automatically, but `scheduleBuffer` (looping) plays raw at the
		// node's output rate — matching the format keeps both paths in tune.
		engine.connect(player, to: timePitch, format: format)
		engine.connect(timePitch, to: engine.mainMixerNode, format: format)
	}

	// MARK: - Transport

	func play() {
		if !isScheduled {
			if isLooping, let loopBuffer {
				player.scheduleBuffer(loopBuffer, at: nil, options: [.loops], completionHandler: nil)
				isScheduled = true
			} else if let file {
				player.scheduleFile(file, at: nil)
				isScheduled = true
			}
		}
		player.play()
	}

	func pause() {
		player.pause()
	}

	func stop() {
		player.stop()
		isScheduled = false
		lastPausedTime = 0
	}

	func seek(to time: TimeInterval) {
		guard let file else { return }

		// A manual seek leaves loop mode; playback becomes linear again.
		isLooping = false
		loopBuffer = nil

		let wasPlaying = player.isPlaying
		if wasPlaying { player.stop() }

		let startFrame = AVAudioFramePosition(time * file.processingFormat.sampleRate)
		let frameCount = AVAudioFrameCount(max(0, file.length - startFrame))
		player.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil, completionHandler: nil)
		isScheduled = true
		lastPausedTime = time

		if wasPlaying { player.play() }
	}

	// MARK: - Looping

	func scheduleLoop(_ buffer: AVAudioPCMBuffer, startTime: TimeInterval, length: TimeInterval) {
		let wasPlaying = player.isPlaying
		loopBuffer = buffer
		isLooping = true
		loopStartTime = startTime
		loopLength = length

		player.stop()
		player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
		isScheduled = true
		lastPausedTime = startTime

		if wasPlaying { player.play() }
	}

	func clearLoop(resumeAt time: TimeInterval) {
		guard isLooping else { return }
		isLooping = false
		loopBuffer = nil
		seek(to: time)
	}

	// MARK: - Clock

	func currentTime() -> TimeInterval {
		guard let nodeTime = player.lastRenderTime,
		      let playerTime = player.playerTime(forNodeTime: nodeTime)
		else { return lastPausedTime }

		let elapsed = Double(playerTime.sampleTime) / (playerTime.sampleRate * Double(timePitch.rate))

		// While looping, the render clock keeps counting across iterations; fold it
		// back into the [A, B] window so the reported time stays in range.
		if isLooping, loopLength > 0 {
			return loopStartTime + elapsed.truncatingRemainder(dividingBy: loopLength)
		}
		return lastPausedTime + elapsed
	}

	// MARK: - Parameters

	func setRate(_ rate: Float) {
		timePitch.rate = rate
	}

	func setVolume(_ volume: Float) {
		player.volume = volume
	}
}
