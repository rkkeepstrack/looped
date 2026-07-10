//
//  PlayerViewModelTests.swift
//  loopedTests
//
//  Automates the transport / looping / loading rows of TESTING.md at the view-model
//  layer: a spy PlaybackService records the intents, a real decode gives a genuine
//  LoadedAudio, and a real LoopingService produces the loop buffer. What stays
//  manual (audio quality, timer-driven clock, visuals) is noted in TESTING.md.
//
//  A `final class` suite (not a struct) so `deinit` can clean up the temp fixture,
//  the way XCTest's tearDown did. Swift Testing makes a fresh instance per test.
//

import AVFoundation
@testable import looped
import Testing

@MainActor
final class PlayerViewModelTests {
	private let fake = FakePlaybackService()
	private let fixture: URL

	init() throws {
		fixture = try AudioFixture.tempSine(seconds: 1)
	}

	deinit {
		try? FileManager.default.removeItem(at: fixture)
	}

	/// The coordinator behind the last-made view-model — end-of-track tests
	/// drive its `tick()` directly.
	private var transport: PlaybackCoordinator?

	/// Ephemeral, per-instance UserDefaults so the playthrough-mode persistence
	/// never touches (or reads) the test host's real defaults.
	private let defaults = UserDefaults(suiteName: "loopedTests-\(UUID().uuidString)")!

	private let toasts = ToastCenter()

	private func makeViewModel(files: AudioFileService = DefaultAudioFileService()) -> PlayerViewModel {
		let transport = PlaybackCoordinator(playback: fake, files: files, toasts: toasts)
		self.transport = transport
		return PlayerViewModel(transport: transport, playback: fake, looping: DefaultLoopingService(), defaults: defaults)
	}

	/// A view-model with the spy player and a really-decoded 1 s track loaded.
	private func loadedViewModel() async -> PlayerViewModel {
		let vm = makeViewModel()
		await vm.load(url: fixture)
		return vm
	}

	// MARK: - Loading

	@Test func loadPopulatesStateAndPointsThePlayerAtTheFile() async {
		let vm = await loadedViewModel()

		#expect(toasts.toasts.isEmpty)
		#expect(vm.currentFileName == fixture.lastPathComponent)
		#expect(vm.audioURL == fixture)
		#expect(abs((vm.duration ?? 0) - 1.0) <= 0.05)
		#expect(fake.setSourceCount == 1)
		#expect(!vm.isPlaying)
	}

	@Test func loadingTooLongFileSurfacesAToast() async {
		let vm = makeViewModel(files: TooLongAudioFileService())
		await vm.load(url: fixture)

		#expect(toasts.toasts.first?.messages == ["“\(fixture.lastPathComponent)” is longer than 20 minutes."])
		#expect(vm.currentFileName == nil) // nothing loaded
		#expect(fake.setSourceCount == 0)
	}

	@Test func reloadResetsLoopPointsAndTime() async throws {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.1)
		vm.setLoopEnd(time: 0.5)
		vm.currentTime = 0.4

		let second = try AudioFixture.tempSine(seconds: 1, sampleRate: 16000)
		defer { try? FileManager.default.removeItem(at: second) }
		await vm.load(url: second)

		#expect(vm.loopStart.0 == nil)
		#expect(vm.loopEnd.0 == nil)
		#expect(vm.currentTime == 0)
	}

	// MARK: - Transport

	@Test func togglePlayPause() async {
		let vm = await loadedViewModel()

		vm.togglePlayPause()
		#expect(vm.isPlaying)
		#expect(fake.playCount == 1)

		vm.togglePlayPause()
		#expect(!vm.isPlaying)
		#expect(fake.pauseCount == 1)
	}

	@Test func togglePlayPauseDoesNothingWithoutALoadedFile() {
		let vm = makeViewModel()
		vm.togglePlayPause()
		#expect(!vm.isPlaying)
		#expect(fake.playCount == 0)
	}

	@Test func playResumesWhenPausedAndPauseStopsPlayback() async {
		let vm = await loadedViewModel()

		vm.play()
		#expect(vm.isPlaying)
		#expect(fake.playCount == 1)

		vm.pause()
		#expect(!vm.isPlaying)
		#expect(fake.pauseCount == 1)
	}

	@Test func playWhilePlayingRestartsFromTheStart() async {
		let vm = await loadedViewModel()
		vm.play()
		vm.currentTime = 0.6

		vm.play()
		#expect(vm.isPlaying)
		#expect(fake.lastSeek == 0)
		#expect(vm.currentTime == 0)
		#expect(fake.pauseCount == 0) // restarted, never paused
	}

	@Test func playWhilePlayingWithAnArmedLoopRestartsAtA() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.2)
		vm.setLoopEnd(time: 0.8)
		vm.play()

		vm.play()
		#expect(fake.restartLoopCount == 1)
		#expect(fake.seekCount == 0) // loop restart, not a plain seek
		#expect(abs(vm.currentTime - 0.2) <= 1e-9)
		#expect(vm.isPlaying)
	}

	@Test func pauseWhilePausedIsANoOp() async {
		let vm = await loadedViewModel()
		vm.pause()
		#expect(fake.pauseCount == 0)
	}

	@Test func stopResetsToStart() async {
		let vm = await loadedViewModel()
		vm.togglePlayPause()
		vm.currentTime = 0.6

		vm.stop()
		#expect(!vm.isPlaying)
		#expect(vm.currentTime == 0)
		#expect(fake.stopCount == 1)
	}

	// MARK: - Playthrough modes (end of track)

	@Test func playthroughModePersistsAcrossViewModelInstances() {
		let vm = makeViewModel()
		vm.playthroughMode = .loop

		#expect(makeViewModel().playthroughMode == .loop)
	}

	@Test func currentParametersRoundTripAndDriveTheEngine() {
		let vm = makeViewModel()
		let parameters = TrackParameters(rate: 1.5, pitchSemitones: -3, volume: 0.6, syncPitchAndRate: false)

		vm.currentParameters = parameters

		#expect(vm.currentParameters == parameters)
		#expect(fake.lastRate == 1.5)
		#expect(fake.lastPitchCents == -300)
		#expect(fake.lastVolume == 0.6)
	}

	@Test func applyingSyncedParametersDrivesTheVarispeedUnit() {
		let vm = makeViewModel()

		vm.currentParameters = TrackParameters(rate: 2, pitchSemitones: 0, volume: 1, syncPitchAndRate: true)

		#expect(fake.lastVarispeed == 2)
		#expect(fake.lastRate == 1) // time-pitch unit neutralized
		#expect(fake.lastPitchCents == 0)
	}

	/// Run the clock past the end and tick the coordinator — the end-of-track
	/// path the 0.03 s timer would drive.
	private func reachEndOfTrack() {
		fake.fakeCurrentTime = 2 // past the 1 s fixture
		transport?.tick()
	}

	@Test func modeCyclesAdvanceStopLoop() async {
		let vm = await loadedViewModel()
		#expect(vm.playthroughMode == .advance) // the default

		vm.cyclePlaythroughMode()
		#expect(vm.playthroughMode == .stop)
		vm.cyclePlaythroughMode()
		#expect(vm.playthroughMode == .loop)
		vm.cyclePlaythroughMode()
		#expect(vm.playthroughMode == .advance)
	}

	@Test func stopModeEndsAtTheStart() async {
		let vm = await loadedViewModel()
		vm.playthroughMode = .stop
		vm.togglePlayPause()

		reachEndOfTrack()
		#expect(!vm.isPlaying)
		#expect(vm.currentTime == 0)
		#expect(fake.playCount == 1) // no replay
	}

	@Test func loopModeRestartsTheTrack() async {
		let vm = await loadedViewModel()
		vm.playthroughMode = .loop
		vm.togglePlayPause()

		reachEndOfTrack()
		#expect(vm.isPlaying)
		#expect(fake.stopCount == 1) // the end-of-track stop reset the playhead…
		#expect(fake.playCount == 2) // …and playback restarted from 0
	}

	@Test func advanceModeAsksTheLibraryForTheNextTrack() async {
		let vm = await loadedViewModel()
		vm.playthroughMode = .advance
		var advanced = false
		vm.onAdvanceToNextTrack = { advanced = true }
		vm.togglePlayPause()

		reachEndOfTrack()
		#expect(advanced)
		#expect(!vm.isPlaying) // the library drives what happens next
	}

	// MARK: - Seeking (jumpTo)

	@Test func jumpToSeeksWhenInBounds() async {
		let vm = await loadedViewModel()
		#expect(vm.jumpTo(time: 0.5))
		#expect(abs((fake.lastSeek ?? -1) - 0.5) <= 1e-9)
		#expect(abs(vm.currentTime - 0.5) <= 1e-9)
	}

	@Test func jumpToIgnoresOutOfBounds() async {
		let vm = await loadedViewModel()
		#expect(!vm.jumpTo(time: 99)) // past the end
		#expect(!vm.jumpTo(time: -1)) // before the start
		#expect(fake.seekCount == 0)
	}

	@Test func jumpToInsideAnArmedLoopMovesTheLoopPhase() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.1)
		vm.setLoopEnd(time: 0.5)
		#expect(fake.isLooping)

		#expect(vm.jumpTo(time: 0.3))
		#expect(fake.seekInLoopCount == 1)
		#expect(abs((fake.lastSeekInLoop ?? -1) - 0.3) <= 1e-9)
		#expect(abs(vm.currentTime - 0.3) <= 1e-9)
		#expect(fake.seekCount == 0) // never a plain full-file seek
	}

	@Test func jumpToOutsideAnArmedLoopIsRefused() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.1)
		vm.setLoopEnd(time: 0.5)

		// Scrubbing outside [A, B] must be a no-op (stays in the loop).
		#expect(!vm.jumpTo(time: 0.7))
		#expect(!vm.jumpTo(time: 0.05))
		#expect(fake.seekInLoopCount == 0)
		#expect(fake.seekCount == 0)
	}

	// MARK: - Looping

	@Test func validRangeArmsTheLoop() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.2)
		vm.setLoopEnd(time: 0.8)

		#expect(fake.isLooping)
		#expect(fake.scheduleLoopCount == 1)
		#expect(abs((fake.lastLoopStart ?? -1) - 0.2) <= 1e-9)
		#expect(abs((fake.lastLoopLength ?? -1) - 0.6) <= 1e-9)
		#expect(abs(vm.currentTime - 0.2) <= 1e-9) // jumps to A
	}

	@Test func invertedRangeDoesNotArm() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.8)
		vm.setLoopEnd(time: 0.2) // B < A
		#expect(!fake.isLooping)
		#expect(fake.scheduleLoopCount == 0)
	}

	@Test func clearingAPointDisarmsTheLoop() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.2)
		vm.setLoopEnd(time: 0.8)
		#expect(fake.isLooping)

		vm.setLoopStart(time: nil)
		#expect(!fake.isLooping)
		#expect(fake.clearLoopCount == 1)
	}

	// MARK: - Loop point toggles (keyboard a/b/r)

	@Test func toggleSetsThePointAtTheCurrentTimeAndClearsOnRepeat() async {
		let vm = await loadedViewModel()
		vm.currentTime = 0.3

		vm.toggleLoopStart()
		#expect(abs((vm.loopStart.0 ?? -1) - 0.3) <= 1e-9)

		vm.toggleLoopStart()
		#expect(vm.loopStart.0 == nil)
	}

	@Test func clearLoopPointsDisarmsAndClearsBoth() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.2)
		vm.setLoopEnd(time: 0.8)
		#expect(fake.isLooping)

		vm.clearLoopPoints()
		#expect(vm.loopStart.0 == nil)
		#expect(vm.loopEnd.0 == nil)
		#expect(!fake.isLooping)
	}

	// MARK: - Loop nudging

	@Test func nudgeShiftsThePointAndRearms() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.2)
		vm.setLoopEnd(time: 0.8)
		#expect(fake.scheduleLoopCount == 1)

		vm.nudgeLoopStart(by: 0.05)
		#expect(abs((vm.loopStart.0 ?? -1) - 0.25) <= 1e-9)
		#expect(fake.scheduleLoopCount == 2)

		vm.nudgeLoopEnd(by: -0.1)
		#expect(abs((vm.loopEnd.0 ?? -1) - 0.7) <= 1e-9)
		#expect(fake.scheduleLoopCount == 3)
	}

	@Test func nudgeClampsToFileBounds() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.02)
		vm.setLoopEnd(time: 0.9)

		vm.nudgeLoopStart(by: -0.5)
		#expect(vm.loopStart.0 == 0)

		vm.nudgeLoopEnd(by: 5)
		#expect(abs((vm.loopEnd.0 ?? -1) - (vm.duration ?? -1)) <= 1e-9)
	}

	@Test func nudgeKeepsTheMinimumGap() async throws {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.4)
		vm.setLoopEnd(time: 0.5)

		vm.nudgeLoopStart(by: 0.5) // would cross B
		#expect(abs((vm.loopStart.0 ?? -1) - (0.5 - PlayerViewModel.minLoopGap)) <= 1e-9)

		vm.nudgeLoopEnd(by: -0.5) // would cross A
		#expect(try abs((vm.loopEnd.0 ?? -1) - (#require(vm.loopStart.0) + PlayerViewModel.minLoopGap)) <= 1e-9)
		#expect(fake.isLooping) // still a valid range, still armed
	}

	@Test func nudgeIsANoOpWhenThePointIsUnset() async {
		let vm = await loadedViewModel()
		vm.nudgeLoopStart(by: 0.05)
		vm.nudgeLoopEnd(by: 0.05)
		#expect(vm.loopStart.0 == nil)
		#expect(vm.loopEnd.0 == nil)
		#expect(fake.scheduleLoopCount == 0)
	}

	@Test func nudgeClampsAgainstTheOnlySetBoundUsingTheFile() async {
		let vm = await loadedViewModel()
		vm.setLoopStart(time: 0.9) // B unset → upper bound is the file end
		vm.nudgeLoopStart(by: 5)
		#expect(abs((vm.loopStart.0 ?? -1) - (vm.duration ?? -1)) <= 1e-9)

		vm.setLoopStart(time: nil)
		vm.setLoopEnd(time: 0.1) // A unset → lower bound is 0
		vm.nudgeLoopEnd(by: -5)
		#expect(vm.loopEnd.0 == 0)
	}

	// MARK: - Parameters

	@Test func rateAndVolumeReachThePlayer() async {
		let vm = await loadedViewModel()
		vm.rate = 1.5
		vm.updateRate()
		vm.volume = 0.25
		vm.updateVolume()

		#expect(abs((fake.lastRate ?? -1) - 1.5) <= 1e-6)
		#expect(abs((fake.lastVolume ?? -1) - 0.25) <= 1e-6)
	}

	@Test func independentModeDrivesTimePitchAndNeutralizesVarispeed() async {
		let vm = await loadedViewModel()
		vm.rate = 1.5
		vm.pitchSemitones = -3
		vm.updatePitch()

		#expect(fake.lastVarispeed == 1)
		#expect(fake.lastRate == 1.5)
		#expect(fake.lastPitchCents == -300)
	}

	@Test func syncModeDrivesVarispeedAndNeutralizesTimePitch() async {
		let vm = await loadedViewModel()
		vm.rate = 0.75
		vm.pitchSemitones = 5
		vm.updateSync(true)

		#expect(fake.lastRate == 1)
		#expect(fake.lastPitchCents == 0)
		#expect(fake.lastVarispeed == 0.75)

		// Rate edits while synced keep flowing to the varispeed unit only.
		vm.rate = 1.25
		vm.updateRate()
		#expect(fake.lastVarispeed == 1.25)
		#expect(fake.lastRate == 1)

		// Leaving sync restores the independent values.
		vm.updateSync(false)
		#expect(fake.lastVarispeed == 1)
		#expect(fake.lastRate == 1.25)
		#expect(fake.lastPitchCents == 500)
	}

	// MARK: - Derived

	@Test func progressInPercent() async {
		let vm = await loadedViewModel()
		vm.currentTime = 0.25
		#expect(abs(vm.getProgressInPercent() - 0.25) <= 0.02)
	}
}
