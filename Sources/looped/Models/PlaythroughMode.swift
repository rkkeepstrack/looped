//
//  PlaythroughMode.swift
//  looped
//
//  What happens when the current track reaches its end (independent of the
//  A/B loop-point feature — an armed loop never lets the track "end").
//

enum PlaythroughMode: CaseIterable {
	/// Restart this track from the beginning and keep playing.
	case loop
	/// Play the next track in library order (stops after the last one).
	case advance
	/// Stop playback; the playhead resets to the start.
	case stop

	/// The mode after this one in the cycle (wraps around) — drives the
	/// single cycling mode button.
	var next: PlaythroughMode {
		let all = Self.allCases
		let index = all.firstIndex(of: self)!
		return all[(index + 1) % all.count]
	}
}
