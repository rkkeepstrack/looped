//
//  PlayerViewModel.swift
//  looped
//
//  The presentation layer for playback (MVVM view-model / "Angular component"
//  role): a thin projection over PlaybackCoordinator (source + transport +
//  clock) that adds the playback *parameters* — loop points, rate/pitch/volume
//  — and turns view intents into calls on the store and the injected services.
//  Holds no audio graph and no view layout.
//

import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

final class PlayerViewModel: ObservableObject {
	// MARK: Published state (what the views bind to)

	@Published var rate: Float = 1.0
	/// Transposition in semitones (−12…+12), independent of tempo.
	@Published var pitchSemitones: Float = 0
	/// Synced ("varispeed") mode: one control moves tempo + pitch together via a
	/// plain resampler — artifact-free, like tape speed. When off, `rate` and
	/// `pitchSemitones` drive the time-pitch unit independently.
	@Published var syncPitchAndRate = false
	@Published var volume: Float = 1.0
	@Published var loopStart: (TimeInterval?, AVAudioFramePosition?) = (nil, nil)
	@Published var loopEnd: (TimeInterval?, AVAudioFramePosition?) = (nil, nil)
	/// What happens at end of track. Persisted app-wide in UserDefaults
	/// (per-track parameters go to the library store instead).
	@Published var playthroughMode: PlaythroughMode = .advance {
		didSet { defaults.set(playthroughMode.rawValue, forKey: Self.playthroughModeKey) }
	}

	// MARK: Transport projection (state lives in the coordinator)

	var isPlaying: Bool {
		transport.isPlaying
	}

	var duration: TimeInterval? {
		transport.duration
	}

	var audioURL: URL? {
		transport.currentURL
	}

	var currentFileName: String? {
		transport.currentURL?.lastPathComponent
	}

	/// True while a file decode is in flight — the waveform shows a spinner.
	var isLoadingTrack: Bool {
		transport.isLoadingTrack
	}

	var currentTime: TimeInterval {
		get { transport.currentTime }
		set { transport.currentTime = newValue }
	}

	// MARK: Wiring (set at the composition root)

	/// Fired when the track ends in advance mode — the library plays the next
	/// track. Kept a callback so this VM never references the library VM.
	var onAdvanceToNextTrack: (() -> Void)?

	// MARK: Injected store + services

	private let transport: PlaybackCoordinator
	private let playback: PlaybackService
	private let looping: LoopingService
	private let defaults: UserDefaults

	private static let playthroughModeKey = "playthroughMode"

	private var transportChanges: AnyCancellable?

	init(
		transport: PlaybackCoordinator,
		playback: PlaybackService,
		looping: LoopingService,
		defaults: UserDefaults = .standard
	) {
		self.transport = transport
		self.playback = playback
		self.looping = looping
		self.defaults = defaults

		if let raw = defaults.string(forKey: Self.playthroughModeKey),
		   let mode = PlaythroughMode(rawValue: raw)
		{
			playthroughMode = mode
		}

		// Re-publish the store's changes so views bound to this VM refresh.
		transportChanges = transport.objectWillChange.sink { [weak self] in
			self?.objectWillChange.send()
		}
		// Loop points are per-track: reset them whenever the source changes.
		transport.onSourceChanged = { [weak self] in
			self?.loopStart = (nil, nil)
			self?.loopEnd = (nil, nil)
		}
		// End-of-track policy (the playthrough mode) is an intent-layer decision,
		// so the coordinator's callback lands here, not in the library VM.
		transport.onTrackEnded = { [weak self] in
			self?.trackEnded()
		}
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
		// A failed load already surfaced as a toast; nothing to do here.
		_ = await transport.load(url: url)
	}

	// MARK: - Transport

	func togglePlayPause() {
		isPlaying ? transport.pause() : transport.play()
	}

	/// The play button: resumes when paused; when already playing, restarts the
	/// current material (an armed loop back to A, otherwise the track from 0).
	func play() {
		isPlaying ? transport.restart() : transport.play()
	}

	/// The pause button: pauses at the current time; a no-op while paused.
	func pause() {
		guard isPlaying else { return }
		transport.pause()
	}

	func stop() {
		transport.stop()
	}

	func cyclePlaythroughMode() {
		playthroughMode = playthroughMode.next
	}

	/// End-of-track policy (wired to `PlaybackCoordinator.onTrackEnded`). The
	/// coordinator has already stopped — playhead at 0 — so stop mode is done,
	/// loop mode just plays again, and advance mode defers to the library.
	/// Never fires while an A/B loop is armed (a looping track doesn't "end").
	func trackEnded() {
		switch playthroughMode {
		case .loop:
			transport.play()
		case .advance:
			onAdvanceToNextTrack?()
		case .stop:
			break
		}
	}

	/// Seek to `time`; returns `true` if it actually seeked. While a loop is
	/// armed, seeks within [A, B] move the loop phase and anything outside is
	/// refused (scrub stays in the loop); without a loop, out-of-bounds times
	/// are refused. On `false` the caller eases the waveform back.
	func jumpTo(time: TimeInterval) -> Bool {
		if playback.isLooping {
			guard let a = loopStart.0, let b = loopEnd.0, time >= a, time <= b else { return false }
			playback.seekInLoop(to: time)
			transport.currentTime = time
			return true
		}
		guard time >= 0, let duration, time <= duration else { return false }
		transport.seek(to: time)
		return true
	}

	func updateRate() {
		applyPitchAndRate()
	}

	func updatePitch() {
		applyPitchAndRate()
	}

	func updateSync(_ enabled: Bool) {
		syncPitchAndRate = enabled
		applyPitchAndRate()
	}

	/// Push the full pitch/rate state to the engine. Neutralize the inactive unit
	/// *before* raising the active one so mode switches never double-shift.
	private func applyPitchAndRate() {
		if syncPitchAndRate {
			playback.setRate(1)
			playback.setPitch(0)
			playback.setVarispeed(rate)
		} else {
			playback.setVarispeed(1)
			playback.setRate(rate)
			playback.setPitch(pitchSemitones * 100)
		}
	}

	func updateVolume() {
		playback.setVolume(volume)
	}

	// MARK: - Per-track parameters

	/// The slider state as a value — the library stashes it per track on a
	/// switch and applies the incoming track's values (wired at the
	/// composition root). Setting pushes the full state to the engine.
	var currentParameters: TrackParameters {
		get {
			TrackParameters(
				rate: rate,
				pitchSemitones: pitchSemitones,
				volume: volume,
				syncPitchAndRate: syncPitchAndRate
			)
		}
		set {
			rate = newValue.rate
			pitchSemitones = newValue.pitchSemitones
			volume = newValue.volume
			syncPitchAndRate = newValue.syncPitchAndRate
			applyPitchAndRate()
			playback.setVolume(volume)
		}
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

	/// Keyboard toggle ("A"): set the A point to the current time, or clear it
	/// when already set (the same semantics as click / right-click).
	func toggleLoopStart() {
		setLoopStart(time: loopStart.1 == nil ? currentTime : nil)
	}

	/// Keyboard toggle ("B") — see `toggleLoopStart`.
	func toggleLoopEnd() {
		setLoopEnd(time: loopEnd.1 == nil ? currentTime : nil)
	}

	/// Clear both loop points ("R" / the panel label's reset), in one pass —
	/// one disarm, one publish per point.
	func clearLoopPoints() {
		loopStart = (nil, nil)
		loopEnd = (nil, nil)
		refreshLoop()
	}

	/// Smallest allowed A–B gap. The crossfade self-limits below this, but a
	/// sub-perceptual loop is useless — keep nudges from collapsing the range.
	static let minLoopGap: TimeInterval = 0.05

	/// Shift the A point by `delta`, clamped to `[0, B − minLoopGap]` (or the file
	/// end when B is unset). No-op when A isn't set. Re-arms via `setLoopStart`,
	/// which reschedules from scratch — playback restarts at A (smooth keep-position
	/// nudging would need `scheduleLoop` to take a start offset; out of scope).
	func nudgeLoopStart(by delta: TimeInterval) {
		guard let time = loopStart.0, let duration else { return }
		let upper = loopEnd.0.map { $0 - Self.minLoopGap } ?? duration
		setLoopStart(time: min(max(0, time + delta), max(0, upper)))
	}

	/// Shift the B point by `delta`, clamped to `[A + minLoopGap, duration]`
	/// (lower bound 0 when A is unset). No-op when B isn't set.
	func nudgeLoopEnd(by delta: TimeInterval) {
		guard let time = loopEnd.0, let duration else { return }
		let lower = loopStart.0.map { $0 + Self.minLoopGap } ?? 0
		setLoopEnd(time: max(min(duration, time + delta), min(duration, lower)))
	}

	private func framePosition(for time: TimeInterval?) -> AVAudioFramePosition? {
		guard let loaded = transport.loaded, let time else { return nil }
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
		guard let loaded = transport.loaded,
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

	/// Uncached read of the playback clock, for per-display-frame rendering
	/// (`TimelineView`) — doesn't invalidate observers.
	func livePlaybackTime() -> TimeInterval {
		transport.livePlaybackTime()
	}

	// MARK: - Derived

	func getProgressInPercent() -> Double {
		guard let duration, duration > 0 else { return 0 }
		return currentTime / duration
	}

	func getDuration() -> TimeInterval? {
		duration
	}
}
