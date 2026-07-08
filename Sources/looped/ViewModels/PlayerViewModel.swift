//
//  PlayerViewModel.swift
//  looped
//
//  The presentation layer for playback (MVVM view-model / "Angular component"
//  role): owns the @Published UI state and the refresh timer, and turns view
//  intents into calls on the injected services. Holds no audio graph and no view
//  layout — it coordinates PlaybackService, AudioFileService, and LoopingService.
//

import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

final class PlayerViewModel: ObservableObject {
	// MARK: Published state (what the views bind to)

	@Published var isPlaying = false
	@Published var currentTime: TimeInterval = 0
	@Published var duration: TimeInterval?
	@Published var rate: Float = 1.0
	@Published var loopStart: (TimeInterval?, AVAudioFramePosition?) = (nil, nil)
	@Published var loopEnd: (TimeInterval?, AVAudioFramePosition?) = (nil, nil)
	@Published var currentFileName: String?
	@Published var audioURL: URL?
	/// Non-nil when the last load failed (e.g. file too long); shown in the header.
	@Published var loadError: String?

	// MARK: Injected services

	private let playback: PlaybackService
	private let files: AudioFileService
	private let looping: LoopingService

	private var loaded: LoadedAudio?
	private var timer: Timer?

	init(playback: PlaybackService, files: AudioFileService, looping: LoopingService) {
		self.playback = playback
		self.files = files
		self.looping = looping
	}

	// MARK: - Loading

	func openFile() async {
		let url: URL? = await MainActor.run {
			let panel = NSOpenPanel()
			panel.allowedContentTypes = [UTType.wav, UTType.mp3, UTType.aiff]
			panel.allowsMultipleSelection = false
			return panel.runModal() == .OK ? panel.url : nil
		}
		guard let url else { return }
		await load(url: url)
	}

	func load(url: URL) async {
		do {
			let loaded = try await files.load(url: url)
			await MainActor.run {
				self.loadError = nil
				self.apply(loaded)
			}
		} catch {
			let message = (error as? LocalizedError)?.errorDescription ?? "Could not load file."
			await MainActor.run { self.loadError = message }
		}
	}

	private func apply(_ loaded: LoadedAudio) {
		self.loaded = loaded
		playback.setSource(file: loaded.file, format: loaded.format)

		currentFileName = loaded.url.lastPathComponent
		audioURL = loaded.url
		duration = loaded.duration
		currentTime = 0
		isPlaying = false
		loopStart = (nil, nil)
		loopEnd = (nil, nil)
		stopTimer()
	}

	// MARK: - Transport

	func togglePlayPause() {
		guard loaded != nil else { return }
		if isPlaying {
			playback.pause()
			isPlaying = false
			stopTimer()
		} else {
			playback.play()
			isPlaying = true
			startTimer()
		}
	}

	func stop() {
		playback.stop()
		isPlaying = false
		currentTime = 0
		stopTimer()
	}

	/// Seek to `time`; returns `true` if it actually seeked. Returns `false` (a no-op)
	/// while a loop is armed (scrub stays in the loop) or when `time` is out of
	/// bounds (playback continues as before) — the caller then eases the waveform back.
	@discardableResult
	func jumpTo(time: TimeInterval) -> Bool {
		guard !playback.isLooping else { return false }
		guard time >= 0, let duration, time <= duration else { return false }
		playback.seek(to: time)
		currentTime = time
		return true
	}

	func updateRate() {
		playback.setRate(rate)
	}

	func updateVolume(volume: Float) {
		playback.setVolume(volume)
	}

	// MARK: - Looping

	func setLoopStart(time: TimeInterval?) {
		loopStart = (time, framePosition(for: time))
		refreshLoop()
	}

	func setLoopEnd(time: TimeInterval?) {
		loopEnd = (time, framePosition(for: time))
		refreshLoop()
	}

	private func framePosition(for time: TimeInterval?) -> AVAudioFramePosition? {
		guard let loaded, let time else { return nil }
		return AVAudioFramePosition(time * loaded.format.sampleRate)
	}

	/// Arms the loop when both points form a valid [A, B) range, otherwise disarms.
	private func refreshLoop() {
		if let startFrame = loopStart.1, let endFrame = loopEnd.1, startFrame < endFrame {
			activateLoop(startFrame: startFrame, endFrame: endFrame)
		} else if playback.isLooping {
			deactivateLoop()
		}
	}

	private func activateLoop(startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition) {
		guard let loaded,
		      let buffer = looping.makeLoopBuffer(from: loaded.buffer, startFrame: startFrame, endFrame: endFrame)
		else { return }

		let startTime = loopStart.0 ?? 0
		let length = (loopEnd.0 ?? 0) - startTime
		playback.scheduleLoop(buffer, startTime: startTime, length: length)
		currentTime = startTime
	}

	private func deactivateLoop() {
		playback.clearLoop(resumeAt: currentTime)
	}

	// MARK: - Derived

	func getProgressInPercent() -> Double {
		guard let duration, duration > 0 else { return 0 }
		return currentTime / duration
	}

	func getDuration() -> TimeInterval? {
		duration
	}

	// MARK: - Timer

	private func startTimer() {
		stopTimer()
		let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
			guard let self else { return }
			currentTime = playback.currentTime()
			// Looping never "ends"; only stop at the end of linear playback.
			if !playback.isLooping, let duration, currentTime >= duration {
				stop()
			}
		}
		// `.common` so the waveform keeps updating during AppKit event tracking
		// (button clicks, scrolling) — `.default`-mode timers pause while tracking.
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer
	}

	private func stopTimer() {
		timer?.invalidate()
		timer = nil
	}
}
