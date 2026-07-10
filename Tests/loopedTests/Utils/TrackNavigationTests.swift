//
//  TrackNavigationTests.swift
//  loopedTests
//
//  The library-transport policy, tested pure — no fixtures, no fakes: ordering,
//  clamping at the ends, and previous's restart-vs-step-back rule.
//

import Foundation
@testable import looped
import Testing

struct TrackNavigationTests {
	private let tracks: [Track] = (0 ..< 3).map { i in
		Track(id: UUID(), url: URL(fileURLWithPath: "/t\(i).wav"), title: "t\(i)", duration: 60)
	}

	private func change(_ move: TrackNavigation.Move?) -> Track? {
		if case let .change(track)? = move { return track }
		return nil
	}

	private func isRestart(_ move: TrackNavigation.Move?) -> Bool {
		if case .restart? = move { return true }
		return false
	}

	// MARK: - next

	@Test func nextReturnsTheFollowingTrack() {
		#expect(change(TrackNavigation.next(in: tracks, after: tracks[0].id))?.id == tracks[1].id)
		#expect(change(TrackNavigation.next(in: tracks, after: tracks[1].id))?.id == tracks[2].id)
	}

	@Test func nextClampsAtTheEnd() {
		#expect(TrackNavigation.next(in: tracks, after: tracks[2].id) == nil)
	}

	@Test func nextWithoutACurrentTrackIsNil() {
		#expect(TrackNavigation.next(in: tracks, after: nil) == nil)
		#expect(TrackNavigation.next(in: tracks, after: UUID()) == nil)
		#expect(TrackNavigation.next(in: [], after: nil) == nil)
	}

	// MARK: - previous

	@Test func previousStepsBackBelowTheThreshold() {
		let move = TrackNavigation.previous(in: tracks, before: tracks[1].id, currentTime: 2, isLoaded: true)
		#expect(change(move)?.id == tracks[0].id)
	}

	@Test func previousRestartsPastTheThreshold() {
		let move = TrackNavigation.previous(in: tracks, before: tracks[1].id, currentTime: 4, isLoaded: true)
		#expect(isRestart(move))
	}

	@Test func previousOnTheFirstTrackRestarts() {
		let move = TrackNavigation.previous(in: tracks, before: tracks[0].id, currentTime: 1, isLoaded: true)
		#expect(isRestart(move))
	}

	@Test func previousWithNothingLoadedIsNil() {
		#expect(TrackNavigation.previous(in: tracks, before: nil, currentTime: 0, isLoaded: false) == nil)
		#expect(TrackNavigation.previous(in: [], before: nil, currentTime: 0, isLoaded: false) == nil)
	}

	@Test func thresholdIsExclusive() {
		let atThreshold = TrackNavigation.previous(
			in: tracks,
			before: tracks[1].id,
			currentTime: TrackNavigation.previousRestartThreshold,
			isLoaded: true
		)
		#expect(change(atThreshold)?.id == tracks[0].id) // exactly 3 s still steps back
	}
}
