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
		return (LibraryViewModel(player: player), player, playback)
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
