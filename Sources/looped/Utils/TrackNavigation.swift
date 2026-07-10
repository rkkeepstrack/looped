//
//  TrackNavigation.swift
//  looped
//
//  Pure decision logic for the library-order transport: which track (if any) a
//  next/previous intent targets, and when previous restarts instead. Mirrors
//  the RowInsertion pattern — the policy is synchronous and unit-testable;
//  LibraryViewModel only executes the returned move (load/play choreography).
//

import Foundation

enum TrackNavigation {
	/// What a transport intent should do; nil means nothing to do.
	enum Move {
		case restart
		case change(Track)
	}

	/// Past this point, previous restarts the current track instead of
	/// stepping back (standard player convention).
	static let previousRestartThreshold: TimeInterval = 3

	/// The next track in list order; nil at the end (no wrap) or when nothing
	/// is current.
	static func next(in tracks: [Track], after id: UUID?) -> Move? {
		adjacent(in: tracks, of: id, offset: 1).map(Move.change)
	}

	/// Previous intent: restart past the threshold, otherwise step back in
	/// list order; on the first track restart again (when anything is loaded).
	static func previous(
		in tracks: [Track],
		before id: UUID?,
		currentTime: TimeInterval,
		isLoaded: Bool
	) -> Move? {
		if isLoaded, currentTime > previousRestartThreshold { return .restart }
		if let target = adjacent(in: tracks, of: id, offset: -1) { return .change(target) }
		return isLoaded ? .restart : nil
	}

	private static func adjacent(in tracks: [Track], of id: UUID?, offset: Int) -> Track? {
		guard let index = tracks.firstIndex(where: { $0.id == id }) else { return nil }
		return tracks.indices.contains(index + offset) ? tracks[index + offset] : nil
	}
}
