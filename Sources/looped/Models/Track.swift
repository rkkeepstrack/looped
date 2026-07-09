//
//  Track.swift
//  looped
//
//  A library entry: just the URL plus display metadata. Decoding the audio
//  happens per play (AudioFileService), not per library add.
//

import Foundation

struct Track: Identifiable, Equatable {
	let id: UUID
	let url: URL
	let title: String
	/// Container-reported duration for the list row; nil when unreadable.
	let duration: TimeInterval?
}
