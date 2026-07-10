//
//  Track.swift
//  looped
//
//  A library entry: just the URL plus display metadata. Decoding the audio
//  happens per play (AudioFileService), not per library add.
//

import Foundation
import UniformTypeIdentifiers

struct Track: Identifiable, Equatable {
	let id: UUID
	let url: URL
	let title: String
	/// Container-reported duration for the list row; nil when unreadable.
	let duration: TimeInterval?

	/// The audio types the app accepts — the single predicate shared by the
	/// open panel, `LibraryViewModel.add(urls:)`, and drag & drop.
	static let supportedTypes: [UTType] = [.wav, .mp3, .aiff]

	/// Whether the file's extension maps to a supported audio type.
	static func isSupported(url: URL) -> Bool {
		guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
		return supportedTypes.contains { type.conforms(to: $0) }
	}
}
