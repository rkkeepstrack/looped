//
//  LibraryStore.swift
//  looped
//
//  Library persistence: the track list (with per-track parameters) and the
//  last selection survive relaunch. JSON at Application Support/looped/
//  library.json; the list is tiny, so a full rewrite per save is fine.
//

import Foundation

/// What survives a relaunch.
struct LibrarySnapshot: Equatable {
	var tracks: [Track]
	var currentTrackID: UUID?
}

protocol LibraryStore {
	/// The persisted library, or nil when nothing was saved yet (or the file is
	/// unreadable). Tracks whose files no longer exist are dropped silently.
	func load() -> LibrarySnapshot?
	func save(_ snapshot: LibrarySnapshot)
}

final class JSONLibraryStore: LibraryStore {
	private let fileURL: URL

	/// URLs are stored as plain paths — the `just bundle` app has no
	/// entitlements and no signing, so it isn't sandboxed and plain paths stay
	/// readable across launches. If the app is ever sandboxed/notarized for
	/// distribution, revisit with `url.bookmarkData(options: .withSecurityScope)`
	/// + the app-scope bookmark entitlement.
	init(directory: URL? = nil) {
		let directory = directory ?? FileManager.default
			.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("looped")
		fileURL = directory.appendingPathComponent("library.json")
	}

	func load() -> LibrarySnapshot? {
		guard let data = try? Data(contentsOf: fileURL),
		      let stored = try? JSONDecoder().decode(StoredLibrary.self, from: data)
		else { return nil }

		let tracks = stored.tracks
			.filter { FileManager.default.fileExists(atPath: $0.path) }
			.map { record in
				Track(
					id: record.id,
					url: URL(fileURLWithPath: record.path),
					title: record.title,
					duration: record.duration,
					parameters: record.parameters
				)
			}
		let ids = Set(tracks.map(\.id))
		return LibrarySnapshot(
			tracks: tracks,
			currentTrackID: stored.currentTrackID.flatMap { ids.contains($0) ? $0 : nil }
		)
	}

	func save(_ snapshot: LibrarySnapshot) {
		let stored = StoredLibrary(
			tracks: snapshot.tracks.map { track in
				StoredTrack(
					id: track.id,
					path: track.url.path,
					title: track.title,
					duration: track.duration,
					parameters: track.parameters
				)
			},
			currentTrackID: snapshot.currentTrackID
		)
		guard let data = try? JSONEncoder().encode(stored) else { return }
		try? FileManager.default.createDirectory(
			at: fileURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try? data.write(to: fileURL, options: .atomic)
	}
}

// MARK: - On-disk shape

private struct StoredLibrary: Codable {
	var tracks: [StoredTrack]
	var currentTrackID: UUID?
}

private struct StoredTrack: Codable {
	var id: UUID
	var path: String
	var title: String
	var duration: TimeInterval?
	var parameters: TrackParameters
}
