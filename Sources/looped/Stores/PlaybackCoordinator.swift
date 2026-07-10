//
//  PlaybackCoordinator.swift
//  looped
//
//  UI-free playback-coordination store: owns the current source ("what is
//  loaded") and the transport ("is it playing, where is the clock"), plus the
//  end-of-track detection that drives auto-advance. Both PlayerViewModel (a
//  thin projection for the views) and LibraryViewModel (track selection and
//  auto-advance) depend on it — this replaces the old bidirectional VM→VM
//  bridge.
//

import AVFoundation
import Combine

final class PlaybackCoordinator: ObservableObject {
	// MARK: Published transport state

	@Published private(set) var isPlaying = false
	/// Settable by PlayerViewModel (loop arming jumps the clock to A).
	@Published var currentTime: TimeInterval = 0
	@Published private(set) var duration: TimeInterval?
	@Published private(set) var currentURL: URL?
	/// Non-nil when the last load failed (e.g. file too long).
	@Published private(set) var loadError: String?
	/// True while a file decode is in flight — the waveform shows a spinner.
	@Published private(set) var isLoadingTrack = false

	/// The decoded source — PlayerViewModel slices loop buffers out of it.
	private(set) var loaded: LoadedAudio?

	// MARK: Wiring (set at the composition root)

	/// Fired when linear playback reaches the end of the track, after the
	/// transport stopped. Never fires while a loop is armed — a looping track
	/// doesn't "end". Drives the library's auto-advance.
	var onTrackEnded: (() -> Void)?
	/// Fired after a new source is applied — PlayerViewModel resets its
	/// per-track state (loop points).
	var onSourceChanged: (() -> Void)?

	// MARK: Injected services

	private let playback: PlaybackService
	private let files: AudioFileService

	private var timer: Timer?

	init(playback: PlaybackService, files: AudioFileService) {
		self.playback = playback
		self.files = files
	}

	// MARK: - Loading

	/// Decode `url` and make it the current source; returns whether the load
	/// succeeded (callers like the library only move their selection on success).
	@discardableResult
	func load(url: URL) async -> Bool {
		await MainActor.run { self.isLoadingTrack = true }
		do {
			let loaded = try await files.load(url: url)
			await MainActor.run {
				self.loadError = nil
				self.apply(loaded)
				self.isLoadingTrack = false
			}
			return true
		} catch {
			let message = (error as? LocalizedError)?.errorDescription ?? "Could not load file."
			await MainActor.run {
				self.loadError = message
				self.isLoadingTrack = false
			}
			return false
		}
	}

	/// The track-change reset choreography: rewire the engine, reset the
	/// transport, then let dependents reset their per-track state.
	private func apply(_ loaded: LoadedAudio) {
		self.loaded = loaded
		playback.setSource(file: loaded.file, format: loaded.format)

		currentURL = loaded.url
		duration = loaded.duration
		currentTime = 0
		isPlaying = false
		stopTimer()
		onSourceChanged?()
	}

	// MARK: - Transport

	func play() {
		guard loaded != nil else { return }
		playback.play()
		isPlaying = true
		startTimer()
	}

	func pause() {
		playback.pause()
		isPlaying = false
		stopTimer()
	}

	func stop() {
		playback.stop()
		isPlaying = false
		currentTime = 0
		stopTimer()
	}

	/// Unclamped, unguarded seek — bounds/loop policy lives in PlayerViewModel.
	func seek(to time: TimeInterval) {
		playback.seek(to: time)
		currentTime = time
	}

	/// Restart the current material: an armed loop jumps back to its A point
	/// (and keeps looping), otherwise the track restarts from 0. Preserves the
	/// play state. Drives the previous button's restart behavior.
	func restart() {
		if playback.isLooping {
			playback.restartLoop()
			currentTime = playback.currentTime()
		} else {
			seek(to: 0)
		}
	}

	/// Uncached read of the playback clock, for per-display-frame rendering
	/// (`TimelineView`). Unlike `currentTime` (published on the 0.03 s timer for
	/// labels), this doesn't invalidate observers.
	func livePlaybackTime() -> TimeInterval {
		isPlaying ? playback.currentTime() : currentTime
	}

	// MARK: - Timer

	/// One clock refresh + end-of-track check. Called by the timer; internal so
	/// tests can drive end-of-track without spinning the run loop.
	func tick() {
		currentTime = playback.currentTime()
		// Looping never "ends"; only end at the end of linear playback.
		if !playback.isLooping, let duration, currentTime >= duration {
			stop()
			onTrackEnded?()
		}
	}

	private func startTimer() {
		stopTimer()
		let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
			self?.tick()
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
