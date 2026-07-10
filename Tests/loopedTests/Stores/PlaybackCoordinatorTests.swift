//
//  PlaybackCoordinatorTests.swift
//  loopedTests
//
//  End-of-track detection: the timer body is exposed as `tick()`, so a test
//  drives the fake clock past the duration without spinning the run loop.
//

import Foundation
@testable import looped
import Testing

@MainActor
final class PlaybackCoordinatorTests {
	private let fake = FakePlaybackService()
	private let fixture: URL

	init() throws {
		fixture = try AudioFixture.tempSine(seconds: 1)
	}

	deinit {
		try? FileManager.default.removeItem(at: fixture)
	}

	private func loadedCoordinator() async -> PlaybackCoordinator {
		let transport = PlaybackCoordinator(playback: fake, files: DefaultAudioFileService())
		await transport.load(url: fixture)
		return transport
	}

	@Test func reachingTheEndStopsAndFiresOnTrackEnded() async {
		let transport = await loadedCoordinator()
		var endedCount = 0
		transport.onTrackEnded = { endedCount += 1 }
		transport.play()

		fake.fakeCurrentTime = 2 // past the 1 s duration
		transport.tick()

		#expect(!transport.isPlaying)
		#expect(transport.currentTime == 0) // stop() reset the clock
		#expect(fake.stopCount == 1)
		#expect(endedCount == 1)
	}

	@Test func midTrackTickDoesNotEnd() async {
		let transport = await loadedCoordinator()
		var endedCount = 0
		transport.onTrackEnded = { endedCount += 1 }
		transport.play()

		fake.fakeCurrentTime = 0.5
		transport.tick()

		#expect(transport.isPlaying)
		#expect(abs(transport.currentTime - 0.5) <= 1e-9)
		#expect(endedCount == 0)
	}

	@Test func anArmedLoopNeverEndsTheTrack() async {
		let transport = await loadedCoordinator()
		var endedCount = 0
		transport.onTrackEnded = { endedCount += 1 }
		transport.play()

		fake.isLooping = true
		fake.fakeCurrentTime = 2
		transport.tick()

		#expect(transport.isPlaying)
		#expect(endedCount == 0)
	}

	@Test func sourceChangeFiresOnSourceChangedAndResetsTransport() async {
		let transport = await loadedCoordinator()
		var sourceChanges = 0
		transport.onSourceChanged = { sourceChanges += 1 }
		transport.play()
		transport.currentTime = 0.5

		await transport.load(url: fixture)

		#expect(sourceChanges == 1)
		#expect(!transport.isPlaying)
		#expect(transport.currentTime == 0)
	}

	@Test func unloadStopsAndClearsTheSource() async {
		let transport = await loadedCoordinator()
		var sourceChanges = 0
		transport.onSourceChanged = { sourceChanges += 1 }
		transport.play()

		transport.unload()

		#expect(!transport.isPlaying)
		#expect(transport.currentURL == nil)
		#expect(transport.duration == nil)
		#expect(transport.currentTime == 0)
		#expect(fake.stopCount == 1)
		#expect(sourceChanges == 1)
	}

	@Test func unloadWithoutASourceIsANoOp() {
		let transport = PlaybackCoordinator(playback: fake, files: DefaultAudioFileService())
		var sourceChanges = 0
		transport.onSourceChanged = { sourceChanges += 1 }

		transport.unload()

		#expect(fake.stopCount == 0)
		#expect(sourceChanges == 0)
	}

	@Test func loadReturnsSuccess() async {
		let transport = PlaybackCoordinator(playback: fake, files: DefaultAudioFileService())
		#expect(await transport.load(url: fixture))

		let failing = PlaybackCoordinator(playback: fake, files: TooLongAudioFileService())
		#expect(!(await failing.load(url: fixture)))
		#expect(failing.loadError != nil)
	}
}
