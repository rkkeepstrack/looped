//
//  LibraryViewModelTests.swift
//  loopedTests
//
//  Library behavior: add/dedupe/filter over real temp WAV fixtures, and the
//  play bridge (sets currentTrackID, drives the player) via FakePlaybackService.
//

import Foundation
@testable import looped
import Testing

@MainActor
struct LibraryViewModelTests {
	private func makeSUT(files: AudioFileService = DefaultAudioFileService())
		-> (library: LibraryViewModel, player: PlayerViewModel, playback: FakePlaybackService)
	{
		let playback = FakePlaybackService()
		let player = PlayerViewModel(playback: playback, files: files, looping: DefaultLoopingService())
		let library = LibraryViewModel(player: player, dropped: DefaultDroppedFileService())
		return (library, player, playback)
	}

	// MARK: - add

	@Test func addAppendsTracksWithTitleAndDuration() async throws {
		let (library, _, _) = makeSUT()
		let url = try AudioFixture.tempSine(seconds: 2)

		await library.add(urls: [url])

		#expect(library.tracks.count == 1)
		let track = try #require(library.tracks.first)
		#expect(track.title == url.deletingPathExtension().lastPathComponent)
		let duration = try #require(track.duration)
		#expect(abs(duration - 2) < 0.1)
	}

	@Test func addDedupesByStandardizedURL() async throws {
		let (library, _, _) = makeSUT()
		let url = try AudioFixture.tempSine(seconds: 1)

		await library.add(urls: [url, url])
		await library.add(urls: [url])

		#expect(library.tracks.count == 1)
	}

	@Test func addSkipsNonAudioFiles() async throws {
		let (library, _, _) = makeSUT()
		let text = FileManager.default.temporaryDirectory
			.appendingPathComponent("looped-fixture-\(UUID().uuidString).txt")
		try "not audio".write(to: text, atomically: true, encoding: .utf8)
		let wav = try AudioFixture.tempSine(seconds: 1)

		await library.add(urls: [text, wav])

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

	// MARK: - insert / move / waveform drop

	@Test func addAtIndexInsertsBetweenExistingRows() async throws {
		let (library, _, _) = makeSUT()
		let first = try AudioFixture.tempSine(seconds: 1)
		let second = try AudioFixture.tempSine(seconds: 1)
		await library.add(urls: [first, second])
		let inserted = try AudioFixture.tempSine(seconds: 1)

		await library.add(urls: [inserted], at: 1)

		#expect(library.tracks.map(\.url) == [first, inserted, second])
	}

	@Test func addClampsAnOutOfRangeInsertionIndex() async throws {
		let (library, _, _) = makeSUT()
		let existing = try AudioFixture.tempSine(seconds: 1)
		await library.add(urls: [existing])
		let appended = try AudioFixture.tempSine(seconds: 1)

		await library.add(urls: [appended], at: 99)

		#expect(library.tracks.map(\.url) == [existing, appended])
	}

	@Test func moveReordersTracks() async throws {
		let (library, _, _) = makeSUT()
		let a = try AudioFixture.tempSine(seconds: 1)
		let b = try AudioFixture.tempSine(seconds: 1)
		let c = try AudioFixture.tempSine(seconds: 1)
		await library.add(urls: [a, b, c])

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
		#expect(player.audioURL == wav)
		#expect(playback.setSourceCount == 1)
	}

	@Test func loadDroppedReusesAnExistingLibraryEntry() async throws {
		let (library, _, _) = makeSUT()
		let wav = try AudioFixture.tempSine(seconds: 1)
		await library.add(urls: [wav])
		let existing = try #require(library.tracks.first)

		await library.loadDropped(urls: [wav])

		#expect(library.tracks.count == 1)
		#expect(library.currentTrackID == existing.id)
	}

	// MARK: - load

	@Test func loadSetsCurrentTrackWithoutStartingPlayback() async throws {
		let (library, player, playback) = makeSUT()
		let url = try AudioFixture.tempSine(seconds: 1)
		await library.add(urls: [url])
		let track = try #require(library.tracks.first)

		await library.load(track)

		#expect(library.currentTrackID == track.id)
		#expect(player.audioURL == url)
		#expect(!player.isPlaying)
		#expect(playback.setSourceCount == 1)
		#expect(playback.playCount == 0)
	}

	@Test func overlappingLoadRequestsAreDroppedNotInterleaved() async throws {
		// A double-click fires two row taps; the second must be dropped while the
		// first load is in flight (interleaved setSource calls crashed the engine).
		let (library, _, playback) = makeSUT(files: SlowAudioFileService(delay: .milliseconds(80)))
		let url = try AudioFixture.tempSine(seconds: 1)
		await library.add(urls: [url])
		let track = try #require(library.tracks.first)

		let first = Task { await library.load(track) }
		try await Task.sleep(for: .milliseconds(20))
		let second = Task { await library.load(track) }
		await first.value
		await second.value

		#expect(playback.setSourceCount == 1)
		#expect(library.currentTrackID == track.id)
	}

	@Test func failedLoadKeepsCurrentTrackUnset() async throws {
		let (library, player, _) = makeSUT(files: TooLongAudioFileService())
		let track = try Track(id: UUID(), url: AudioFixture.tempSine(seconds: 1), title: "t", duration: 1)

		await library.load(track)

		#expect(library.currentTrackID == nil)
		#expect(player.loadError != nil)
	}

	@Test func loadPublishesTheLoadingFlagWhileInFlight() async throws {
		let (library, player, _) = makeSUT(files: SlowAudioFileService(delay: .milliseconds(80)))
		let url = try AudioFixture.tempSine(seconds: 1)
		await library.add(urls: [url])
		let track = try #require(library.tracks.first)

		let load = Task { await library.load(track) }
		try await Task.sleep(for: .milliseconds(20))
		#expect(player.isLoadingTrack)
		await load.value
		#expect(!player.isLoadingTrack)
	}
}
