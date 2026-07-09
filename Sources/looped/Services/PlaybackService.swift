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
	/// Seek to `time` in the full file (clamped to bounds); preserves play state.
	func seek(to time: TimeInterval)
	/// Schedule a pre-sliced loop buffer to repeat seamlessly (`.loops`).
	func scheduleLoop(_ buffer: AVAudioPCMBuffer, startTime: TimeInterval, length: TimeInterval)
	/// Leave loop mode and resume normal full-file playback from `time`.
	func clearLoop(resumeAt time: TimeInterval)
	var isLooping: Bool { get }
	/// Current playback position in the source timeline (folded into [A, B] while looping).
	func currentTime() -> TimeInterval
	/// Tempo without transposition (time-pitch unit; artifacts at extremes).
	func setRate(_ rate: Float)
	/// Transposition in cents without tempo change (time-pitch unit).
	func setPitch(_ cents: Float)
	/// Tape-style speed: tempo + pitch together via plain resampling (varispeed
	/// unit; artifact-free) — used by the synced pitch/rate mode.
	func setVarispeed(_ rate: Float)
	func setVolume(_ volume: Float)
}

final class AVPlaybackService: PlaybackService {
	private let engine = AVAudioEngine()
	private let player = AVAudioPlayerNode()
	private let timePitch = AVAudioUnitTimePitch()
	private let varispeed = AVAudioUnitVarispeed()

	private var file: AVAudioFile?
	private var isScheduled = false
	private var lastPausedTime: TimeInterval = 0

	/// Low-passed (elapsed − wall-clock) offset; see `currentTime()`.
	private var smoothedClockOffset: Double?

	private var loopBuffer: AVAudioPCMBuffer?
	private(set) var isLooping = false
	private var loopStartTime: TimeInterval = 0
	private var loopLength: TimeInterval = 0

	init() {
		engine.attach(player)
		engine.attach(timePitch)
		engine.attach(varispeed)
		connectGraph(format: nil)
		do { try engine.start() } catch { print("Engine failed: \(error)") }
	}

	/// `player → timePitch → varispeed → mainMixer`. Both effect units stay in the
	/// graph permanently; the inactive one is kept neutral (rate 1 / pitch 0).
	private func connectGraph(format: AVAudioFormat?) {
		engine.connect(player, to: timePitch, format: format)
		engine.connect(timePitch, to: varispeed, format: format)
		engine.connect(varispeed, to: engine.mainMixerNode, format: format)
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
		// Rewiring a *running* engine races the render thread (loading a second
		// track crashed here) — stop it around the reconnect.
		engine.stop()
		connectGraph(format: format)
		engine.prepare()
		do { try engine.start() } catch { print("Engine failed: \(error)") }
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

		let sampleRate = file.processingFormat.sampleRate
		let totalFrames = file.length
		// Clamp to the file bounds so an out-of-range scrub can't schedule a
		// negative/overflowing segment (which crashes the player node).
		let clampedTime = min(max(0, time), Double(totalFrames) / sampleRate)
		let startFrame = min(max(0, AVAudioFramePosition(clampedTime * sampleRate)), max(0, totalFrames - 1))
		let frameCount = AVAudioFrameCount(totalFrames - startFrame)
		guard frameCount > 0 else { return }

		let wasPlaying = player.isPlaying
		player.stop()

		player.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil, completionHandler: nil)
		isScheduled = true
		lastPausedTime = clampedTime

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

		// The player node sits *upstream* of the time-pitch unit, so its sample clock
		// already counts source frames — at rate 2× it advances 2 s per wall second.
		// No rate division: that made `currentTime` drift at any rate ≠ 1× and broke
		// the loop fold (bug-fixes.md #2).
		var elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
		// Source frames are consumed at the *product* of the two effect rates
		// (harness-verified: clock advance per wall second == timePitch × varispeed).
		let rate = Double(timePitch.rate) * Double(varispeed.rate)
		// `lastRenderTime` only advances once per render buffer (~6–12 ms), which makes
		// the clock step in quanta and the waveform pan judder. While playing, project
		// onto the wall clock: the render timestamp's host time is the buffer's future
		// *presentation* time, so `now - rendered` (negative, ≈ the output lead) shifts
		// the sample position to what's audible now — and varies smoothly between
		// render cycles. The render timestamps themselves jitter by up to a buffer, so
		// low-pass the (elapsed − now·rate) offset (rate-scaled so it's stationary at
		// any playback rate); a jump > 50 ms (seek, resume, rate change) snaps.
		if player.isPlaying, nodeTime.isHostTimeValid {
			let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
			let rendered = AVAudioTime.seconds(forHostTime: nodeTime.hostTime)
			elapsed += min(max(-0.25, now - rendered), 0.25) * rate

			let offset = elapsed - now * rate
			if let smoothed = smoothedClockOffset, abs(offset - smoothed) < 0.05 {
				smoothedClockOffset = smoothed + 0.1 * (offset - smoothed)
			} else {
				smoothedClockOffset = offset
			}
			elapsed = now * rate + smoothedClockOffset!
		}
		// The presentation lead can push a just-started clock slightly negative.
		elapsed = max(0, elapsed)

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

	func setPitch(_ cents: Float) {
		timePitch.pitch = cents
	}

	func setVarispeed(_ rate: Float) {
		varispeed.rate = rate
	}

	func setVolume(_ volume: Float) {
		player.volume = volume
	}
}
