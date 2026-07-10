//
//  TrackParameters.swift
//  looped
//
//  Per-track slider state (the bottom bar). Each track remembers its own
//  values: a track switch stashes the outgoing track's parameters and applies
//  the incoming ones; persisted per track in the library store.
//

struct TrackParameters: Codable, Equatable {
	var rate: Float = 1
	/// Transposition in semitones (−12…+12), independent of tempo.
	var pitchSemitones: Float = 0
	var volume: Float = 1
	/// Synced ("varispeed") mode: tempo + pitch move together.
	var syncPitchAndRate = false
}
