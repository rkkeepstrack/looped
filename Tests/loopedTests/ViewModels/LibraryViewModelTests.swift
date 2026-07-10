//
//  LibraryViewModelTests.swift
//  loopedTests
//
//  Library behavior: add/dedupe/filter over real temp WAV fixtures, and the
//  play bridge (sets currentTrackID, drives the player) via FakePlaybackService.
//

import AVFoundation
import Foundation
@testable import looped
import Testing

@MainActor
struct LibraryViewModelTests {
	private func makeSUT(
		files: AudioFileService = DefaultAudioFileService(),
		store: FakeLibraryStore = FakeLibraryStore(),
		toasts: ToastCenter = ToastCenter()
	)
		-> (library: LibraryViewModel, player: PlaybackCoordinator, playback: FakePlaybackService)
	{
		let playback = FakePlaybackService()
		let player = PlaybackCoordinator(playback: playback, files: files, toasts: toasts)
		let library = LibraryViewModel(
			player: player,
			dropped: DefaultDroppedFileService(),
			store: store,
			toasts: toasts
		)
		return (library, player, playback)
	}

	/// A library with `count` one-second tracks added and the first one loaded.
	private func loadedSUT(count: Int) async throws
		-> (library: LibraryViewModel, player: PlaybackCoordinator, playback: FakePlaybackService)
	{
		let sut = makeSUT()
		let urls = try (0 ..< count).map { _ in try AudioFixture.tempSine(seconds: 1) }
		_ = await sut.library.add(urls: urls)
		let first = try #require(sut.library.tracks.first)
		_ = await sut.library.load(first)
		return sut
	}

	// MARK: - add

	@Test func addAppendsTracksWithTitleAndDuration() async throws {
		let (library, _, _) = makeSUT()
		let url = try AudioFixture.tempSine(seconds: 2)

		_ = await library.add(urls: [url])

		#expect(library.tracks.count == 1)
		let track = try #require(library.tracks.first)
		#expect(track.title == url.deletingPathExtension().lastPathComponent)
		let duration = try #require(track.duration)
		#expect(abs(duration - 2) < 0.1)
	}

	@Test func addDedupesByStandardizedURL() async throws {
		let (library, _, _) = makeSUT()
		let url = try AudioFixture.tempSine(seconds: 1)

		_ = await library.add(urls: [url, url])
		_ = await library.add(urls: [url])

		#expect(library.tracks.count == 1)
	}

	@Test func addSkipsNonAudioFiles() async throws {
		let (library, _, _) = makeSUT()
		let text = FileManager.default.temporaryDirectory
			.appendingPathComponent("looped-fixture-\(UUID().uuidString).txt")
		try "not audio".write(to: text, atomically: true, encoding: .utf8)
		let wav = try AudioFixture.tempSine(seconds: 1)

		_ = await library.add(urls: [text, wav])

		#expect(library.tracks.map(\.url) == [wav])
	}

	// MARK: - Drag & drop intake

	@Test func addDroppedExpandsFoldersIntoTheLibrary() async throws {
		let (library, _, _) = makeSUT()
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("looped-tree-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		let inside = root.appendingPathComponent("song.wav")
		try FileManager.default.copyItem(at: AudioFixture.tempSine(seconds: 1), to: inside)

		await library.addDropped(urls: [root])

		// Enumeration resolves /var → /private/var; compare resolved paths.
		#expect(library.tracks.map { $0.url.resolvingSymlinksInPath() } == [inside.resolvingSymlinksInPath()])
		// Library was empty → the first track is loaded (but not played).
		#expect(library.currentTrackID == library.tracks.first?.id)
	}

	// MARK: - Intake toasts

	/// A throwaway non-audio file for skip/aggregation tests.
	private func tempTextFile() throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("looped-fixture-\(UUID().uuidString).txt")
		try "not audio".write(to: url, atomically: true, encoding: .utf8)
		return url
	}

	@Test func mixedDropAddsGoodFilesAndAggregatesSkipsIntoOneToast() async throws {
		let toasts = ToastCenter()
		let (library, _, _) = makeSUT(toasts: toasts)
		let text1 = try tempTextFile()
		let text2 = try tempTextFile()
		let wav = try AudioFixture.tempSine(seconds: 1)

		await library.addDropped(urls: [text1, wav, text2])

		#expect(library.tracks.map(\.url) == [wav])
		#expect(toasts.toasts.count == 1) // one toast per action, not per file
		let message = try #require(toasts.toasts.first?.messages.first)
		#expect(message.contains(text1.lastPathComponent))
		#expect(message.contains(text2.lastPathComponent))
	}

	@Test func duplicateImportsStaySilent() async throws {
		let toasts = ToastCenter()
		let (library, _, _) = makeSUT(toasts: toasts)
		let wav = try AudioFixture.tempSine(seconds: 1)
		await library.addDropped(urls: [wav])

		await library.addDropped(urls: [wav]) // re-adding is a no-op, not an error

		#expect(library.tracks.count == 1)
		#expect(toasts.toasts.isEmpty)
	}

	@Test func dropYieldingNothingUsableSaysSo() async throws {
		let toasts = ToastCenter()
		let (library, _, _) = makeSUT(toasts: toasts)
		let emptyFolder = FileManager.default.temporaryDirectory
			.appendingPathComponent("looped-empty-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)

		await library.addDropped(urls: [emptyFolder])

		#expect(library.tracks.isEmpty)
		#expect(toasts.toasts.map(\.messages) == [["Nothing to add — no supported audio files found."]])
	}

	@Test func unreadableDropItemsAreReported() async {
		let toasts = ToastCenter()
		let (library, _, _) = makeSUT(toasts: toasts)

		await library.addDropped(urls: [], unreadableCount: 2)

		#expect(library.tracks.isEmpty)
		#expect(toasts.toasts.map(\.messages) == [["2 dropped items couldn't be read."]])
	}

	@Test func waveformDropWithNoSupportedFileReportsNothingUsable() async throws {
		let toasts = ToastCenter()
		let (library, _, _) = makeSUT(toasts: toasts)
		let text = try tempTextFile()

		await library.loadDropped(urls: [text])

		#expect(library.tracks.isEmpty)
		#expect(library.currentTrackID == nil)
		#expect(toasts.toasts.map(\.messages) == [["Nothing to add — no supported audio files found."]])
	}

	// MARK: - insert / move / waveform drop

	@Test func addAtIndexInsertsBetweenExistingRows() async throws {
		let (library, _, _) = makeSUT()
		let first = try AudioFixture.tempSine(seconds: 1)
		let second = try AudioFixture.tempSine(seconds: 1)
		_ = await library.add(urls: [first, second])
		let inserted = try AudioFixture.tempSine(seconds: 1)

		_ = await library.add(urls: [inserted], at: 1)

		#expect(library.tracks.map(\.url) == [first, inserted, second])
	}

	@Test func addClampsAnOutOfRangeInsertionIndex() async throws {
		let (library, _, _) = makeSUT()
		let existing = try AudioFixture.tempSine(seconds: 1)
		_ = await library.add(urls: [existing])
		let appended = try AudioFixture.tempSine(seconds: 1)

		_ = await library.add(urls: [appended], at: 99)

		#expect(library.tracks.map(\.url) == [existing, appended])
	}

	@Test func moveReordersTracks() async throws {
		let (library, _, _) = makeSUT()
		let a = try AudioFixture.tempSine(seconds: 1)
		let b = try AudioFixture.tempSine(seconds: 1)
		let c = try AudioFixture.tempSine(seconds: 1)
		_ = await library.add(urls: [a, b, c])

		library.move(fromOffsets: [0], toOffset: 3)

		#expect(library.tracks.map(\.url) == [b, c, a])
	}

	@Test func loadDroppedAddsAndLoadsTheFirstSupportedFile() async throws {
		let (library, player, playback) = makeSUT()
		let text = FileManager.default.temporaryDirectory
			.appendingPathComponent("looped-fixture-\(UUID().uuidString).txt")
		try "not audio".write(to: text, atomically: true, encoding: .utf8)
		let wav = try AudioFixture.tempSine(seconds: 1)

		await library.loadDropped(urls: [text, wav])

		#expect(library.tracks.map(\.url) == [wav])
		#expect(library.currentTrackID == library.tracks.first?.id)
		#expect(player.currentURL == wav)
		#expect(playback.setSourceCount == 1)
	}

	@Test func loadDroppedReusesAnExistingLibraryEntry() async throws {
		let (library, _, _) = makeSUT()
		let wav = try AudioFixture.tempSine(seconds: 1)
		_ = await library.add(urls: [wav])
		let existing = try #require(library.tracks.first)

		await library.loadDropped(urls: [wav])

		#expect(library.tracks.count == 1)
		#expect(library.currentTrackID == existing.id)
	}

	// MARK: - load

	@Test func loadSetsCurrentTrackWithoutStartingPlayback() async throws {
		let (library, player, playback) = makeSUT()
		let url = try AudioFixture.tempSine(seconds: 1)
		_ = await library.add(urls: [url])
		let track = try #require(library.tracks.first)

		_ = await library.load(track)

		#expect(library.currentTrackID == track.id)
		#expect(player.currentURL == url)
		#expect(!player.isPlaying)
		#expect(playback.setSourceCount == 1)
		#expect(playback.playCount == 0)
	}

	@Test func overlappingLoadRequestsAreDroppedNotInterleaved() async throws {
		// A double-click fires two row taps; the second must be dropped while the
		// first load is in flight (interleaved setSource calls crashed the engine).
		let (library, _, playback) = makeSUT(files: SlowAudioFileService(delay: .milliseconds(80)))
		let url = try AudioFixture.tempSine(seconds: 1)
		_ = await library.add(urls: [url])
		let track = try #require(library.tracks.first)

		let first = Task { _ = await library.load(track) }
		try await Task.sleep(for: .milliseconds(20))
		let second = Task { _ = await library.load(track) }
		await first.value
		await second.value

		#expect(playback.setSourceCount == 1)
		#expect(library.currentTrackID == track.id)
	}

	@Test func failedLoadKeepsCurrentTrackUnsetAndShowsAToast() async throws {
		let toasts = ToastCenter()
		let (library, _, _) = makeSUT(files: TooLongAudioFileService(), toasts: toasts)
		let track = try Track(id: UUID(), url: AudioFixture.tempSine(seconds: 1), title: "t", duration: 1)

		let loaded = await library.load(track)

		#expect(!loaded)
		#expect(library.currentTrackID == nil)
		#expect(toasts.toasts.count == 1)
		#expect(toasts.toasts.first?.messages.first?.contains(track.url.lastPathComponent) == true)
	}

	@Test func loadPublishesTheLoadingFlagWhileInFlight() async throws {
		let (library, player, _) = makeSUT(files: SlowAudioFileService(delay: .milliseconds(80)))
		let url = try AudioFixture.tempSine(seconds: 1)
		_ = await library.add(urls: [url])
		let track = try #require(library.tracks.first)

		let load = Task { _ = await library.load(track) }
		// Poll instead of a fixed sleep — a fixed delay races the load task's
		// start (and its 80ms fake decode) on slow CI runners.
		for _ in 0 ..< 200 where !player.isLoadingTrack {
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(player.isLoadingTrack)
		await load.value
		#expect(!player.isLoadingTrack)
	}

	// MARK: - Remove

	@Test func removeDropsTheRowAndMovesSelectionToTheNextNeighbor() async throws {
		let (library, _, _) = try await loadedSUT(count: 3)
		let removed = library.tracks[1]
		library.selectedTrackID = removed.id

		library.remove(id: removed.id)

		#expect(library.tracks.count == 2)
		#expect(!library.tracks.contains(removed))
		#expect(library.selectedTrackID == library.tracks[1].id) // the old index, now the next row
	}

	@Test func removingTheLastRowSelectsTheNewLastRow() async throws {
		let (library, _, _) = try await loadedSUT(count: 2)
		library.selectedTrackID = library.tracks[1].id

		library.remove(id: library.tracks[1].id)

		#expect(library.selectedTrackID == library.tracks[0].id)
	}

	@Test func removingTheCurrentTrackUnloadsAndStopsPlayback() async throws {
		let (library, player, playback) = try await loadedSUT(count: 2)
		player.play()
		let current = try #require(library.tracks.first(where: { $0.id == library.currentTrackID }))

		library.remove(id: current.id)

		#expect(library.currentTrackID == nil)
		#expect(player.currentURL == nil)
		#expect(!player.isPlaying)
		#expect(playback.stopCount == 1)
	}

	@Test func removingANonCurrentTrackKeepsPlayback() async throws {
		let (library, player, playback) = try await loadedSUT(count: 2)
		player.play()

		library.remove(id: library.tracks[1].id)

		#expect(library.currentTrackID == library.tracks[0].id)
		#expect(player.isPlaying)
		#expect(playback.stopCount == 0)
	}

	@Test func removingTheOnlyTrackClearsTheSelection() async throws {
		let (library, _, _) = try await loadedSUT(count: 1)
		library.selectedTrackID = library.tracks[0].id

		library.remove(id: library.tracks[0].id)

		#expect(library.tracks.isEmpty)
		#expect(library.selectedTrackID == nil)
	}

	@Test func removeSelectedWithoutASelectionIsANoOp() async throws {
		let (library, _, _) = try await loadedSUT(count: 2)

		library.removeSelected()

		#expect(library.tracks.count == 2)
	}

	@Test func removingATrackWhileItsLoadIsInFlightDoesNotResurrectIt() async throws {
		// ⌫ during the decode of a double-clicked row: the finishing load must
		// not mark the removed track current (or leave its source playing).
		let (library, player, _) = makeSUT(files: SlowAudioFileService(delay: .milliseconds(80)))
		_ = try await library.add(urls: [AudioFixture.tempSine(seconds: 1)])
		let track = try #require(library.tracks.first)

		let load = Task { _ = await library.load(track) }
		try await Task.sleep(for: .milliseconds(20))
		library.remove(id: track.id)
		await load.value

		#expect(library.currentTrackID == nil)
		#expect(player.currentURL == nil)
	}

	@Test func removePersistsTheLibrary() async throws {
		let store = FakeLibraryStore()
		let (library, _, _) = makeSUT(store: store)
		let a = try AudioFixture.tempSine(seconds: 1)
		let b = try AudioFixture.tempSine(seconds: 1)
		_ = await library.add(urls: [a, b])

		try library.remove(id: #require(library.tracks.first).id)

		#expect(store.saved?.tracks.map(\.url) == [b])
	}

	// MARK: - Next / previous

	@Test func nextMovesToTheFollowingTrackWithoutPlaying() async throws {
		let (library, player, playback) = try await loadedSUT(count: 3)

		await library.next()

		#expect(library.currentTrackID == library.tracks[1].id)
		#expect(player.currentURL == library.tracks[1].url)
		#expect(playback.playCount == 0) // was paused → stays paused
	}

	@Test func nextClampsAtTheLastTrack() async throws {
		let (library, _, playback) = try await loadedSUT(count: 2)
		await library.next()
		#expect(library.currentTrackID == library.tracks[1].id)
		let sourcesSoFar = playback.setSourceCount

		await library.next() // already on the last track → no-op

		#expect(library.currentTrackID == library.tracks[1].id)
		#expect(playback.setSourceCount == sourcesSoFar)
	}

	@Test func nextPreservesThePlayState() async throws {
		let (library, player, playback) = try await loadedSUT(count: 2)
		player.play()

		await library.next()

		#expect(player.isPlaying)
		#expect(playback.playCount == 2) // initial play + resumed on the new track
	}

	@Test func previousStepsBackEarlyInTheTrack() async throws {
		let (library, _, playback) = try await loadedSUT(count: 3)
		await library.next()
		#expect(library.currentTrackID == library.tracks[1].id)

		await library.previous() // clock at 0 (< 3 s) → step back

		#expect(library.currentTrackID == library.tracks[0].id)
		#expect(playback.seekCount == 0)
	}

	@Test func previousRestartsWhenPastTheThreshold() async throws {
		let (library, player, playback) = try await loadedSUT(count: 3)
		await library.next()
		player.currentTime = 4 // past the 3 s restart threshold
		playback.fakeCurrentTime = 4

		await library.previous()

		#expect(library.currentTrackID == library.tracks[1].id) // stayed put
		#expect(playback.lastSeek == 0)
	}

	@Test func previousOnTheFirstTrackRestartsIt() async throws {
		let (library, _, playback) = try await loadedSUT(count: 2)

		await library.previous() // no earlier track → restart

		#expect(library.currentTrackID == library.tracks[0].id)
		#expect(playback.lastSeek == 0)
	}

	@Test func previousStepsBackAfterALoadResetTheClock() async throws {
		// Playing track 1 past 3 s, then double-click loads track 2: the load
		// resets the clock, so previous steps back (no spurious restart).
		let (library, player, playback) = try await loadedSUT(count: 3)
		player.play()
		playback.fakeCurrentTime = 10
		player.tick()

		_ = await library.load(library.tracks[1])

		await library.previous()
		#expect(library.currentTrackID == library.tracks[0].id)
	}

	@Test func previousRestartsAnArmedLoopAtItsAPoint() async throws {
		// Last track, > 3 s in, loop armed: previous restarts the loop at A —
		// it never falls through to a dead track-restart while looping.
		let (library, player, playback) = try await loadedSUT(count: 2)
		await library.next()
		try playback.scheduleLoop(loopBuffer(), startTime: 4, length: 2) // A = 4 s
		player.currentTime = 5

		await library.previous()

		#expect(library.currentTrackID == library.tracks[1].id) // stayed put
		#expect(playback.restartLoopCount == 1)
		#expect(playback.isLooping)
		#expect(player.currentTime == 4) // back at A
	}

	private func loopBuffer() throws -> AVAudioPCMBuffer {
		let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
		return try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
	}

	// MARK: - Persistence

	@Test func restorePopulatesTheLibraryAndReloadsTheCurrentTrack() async throws {
		let store = FakeLibraryStore()
		let url = try AudioFixture.tempSine(seconds: 1)
		var track = Track(id: UUID(), url: url, title: "t", duration: 1)
		track.parameters = TrackParameters(rate: 2, pitchSemitones: 3, volume: 0.5, syncPitchAndRate: true)
		store.snapshot = LibrarySnapshot(tracks: [track], currentTrackID: track.id)
		let (library, player, playback) = makeSUT(store: store)
		var applied: TrackParameters?
		library.applyParameters = { applied = $0 }

		await library.restore()

		#expect(library.tracks == [track])
		#expect(library.currentTrackID == track.id)
		#expect(player.currentURL == url)
		#expect(!player.isPlaying) // no autoplay on restore
		#expect(playback.playCount == 0)
		#expect(applied == track.parameters)
	}

	@Test func restoreRunsOnlyOnce() async throws {
		let store = FakeLibraryStore()
		let url = try AudioFixture.tempSine(seconds: 1)
		let track = Track(id: UUID(), url: url, title: "t", duration: 1)
		store.snapshot = LibrarySnapshot(tracks: [track], currentTrackID: nil)
		let (library, _, _) = makeSUT(store: store)

		await library.restore()
		store.snapshot = LibrarySnapshot(tracks: [], currentTrackID: nil)
		await library.restore() // window recreated → .task fires again

		#expect(library.tracks == [track]) // not clobbered by the second restore
	}

	@Test func mutationsSaveTheLibrary() async throws {
		let store = FakeLibraryStore()
		let (library, _, _) = makeSUT(store: store)
		let a = try AudioFixture.tempSine(seconds: 1)
		let b = try AudioFixture.tempSine(seconds: 1)

		_ = await library.add(urls: [a, b])
		#expect(store.saved?.tracks.map(\.url) == [a, b])

		library.move(fromOffsets: [0], toOffset: 2)
		#expect(store.saved?.tracks.map(\.url) == [b, a])
	}

	@Test func loadSavesTheNewSelection() async throws {
		let store = FakeLibraryStore()
		let (library, _, _) = makeSUT(store: store)
		_ = try await library.add(urls: [AudioFixture.tempSine(seconds: 1)])
		let track = try #require(library.tracks.first)

		_ = await library.load(track)

		#expect(store.saved?.currentTrackID == track.id)
	}

	@Test func switchingTracksStashesTheOutgoingParametersAndAppliesTheIncoming() async throws {
		let store = FakeLibraryStore()
		let (library, _, _) = makeSUT(store: store)
		let tweaked = TrackParameters(rate: 1.5, pitchSemitones: -2, volume: 0.8, syncPitchAndRate: false)
		var live = TrackParameters()
		library.captureParameters = { live }
		library.applyParameters = { live = $0 }
		_ = try await library.add(urls: [AudioFixture.tempSine(seconds: 1), AudioFixture.tempSine(seconds: 1)])
		_ = await library.load(library.tracks[0])

		live = tweaked // the user moves sliders on track 0…
		_ = await library.load(library.tracks[1]) // …then switches away

		#expect(library.tracks[0].parameters == tweaked) // stashed
		#expect(live == TrackParameters()) // track 1 starts at defaults
		#expect(store.saved?.tracks.first?.parameters == tweaked) // persisted

		_ = await library.load(library.tracks[0]) // and back
		#expect(live == tweaked) // restored
	}

	// MARK: - Auto-advance

	@Test func trackEndedPlaysTheNextTrack() async throws {
		let (library, player, playback) = try await loadedSUT(count: 2)

		await library.trackEnded()

		#expect(library.currentTrackID == library.tracks[1].id)
		#expect(player.isPlaying)
		#expect(playback.playCount == 1)
	}

	@Test func trackEndedOnTheLastTrackDoesNothing() async throws {
		let (library, player, playback) = try await loadedSUT(count: 1)

		await library.trackEnded()

		#expect(library.currentTrackID == library.tracks[0].id)
		#expect(!player.isPlaying)
		#expect(playback.playCount == 0)
	}

	@Test func endOfTrackAutoAdvancesThroughTheWiring() async throws {
		// The full loop in advance mode: coordinator tick past duration →
		// (PlayerViewModel's branching, stubbed here) → library.trackEnded() →
		// next track loads and plays.
		let (library, player, playback) = try await loadedSUT(count: 2)
		player.onTrackEnded = { Task { await library.trackEnded() } }
		player.play()
		playback.fakeCurrentTime = 2
		player.tick()
		// Back to 0 — the next track starts at the top. Leaving the fake clock
		// past the fixture's duration lets the live 0.03s timer (running since
		// play()) end the *advanced-to* track too and stop playback again.
		playback.fakeCurrentTime = 0
		// Let the wired Task run to completion. Wait on isPlaying — the *last*
		// effect of the chain; currentTrackID flips inside load(), before play().
		for _ in 0 ..< 200 where !player.isPlaying {
			try await Task.sleep(for: .milliseconds(10))
		}

		#expect(library.currentTrackID == library.tracks[1].id)
		#expect(player.isPlaying)
	}
}
