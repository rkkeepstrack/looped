//
//  LibraryStoreTests.swift
//  loopedTests
//
//  JSONLibraryStore behavior over a temp directory: round-trip, the
//  missing-file filter, and the empty/corrupt cases.
//

import Foundation
@testable import looped
import Testing

struct LibraryStoreTests {
	private func tempStore() throws -> (store: JSONLibraryStore, directory: URL) {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("looped-store-\(UUID().uuidString)")
		return (JSONLibraryStore(directory: directory), directory)
	}

	private func existingFile(in directory: URL, name: String) throws -> URL {
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let url = directory.appendingPathComponent(name)
		try Data().write(to: url)
		return url
	}

	@Test func roundTripsTracksSelectionAndParameters() throws {
		let (store, directory) = try tempStore()
		let url = try existingFile(in: directory, name: "song.wav")
		var track = Track(id: UUID(), url: url, title: "Song", duration: 12)
		track.parameters = TrackParameters(rate: 1.5, pitchSemitones: -2, volume: 0.7, syncPitchAndRate: true)
		let snapshot = LibrarySnapshot(tracks: [track], currentTrackID: track.id)

		store.save(snapshot)
		let loaded = try #require(store.load())

		#expect(loaded == snapshot)
	}

	@Test func loadDropsTracksWhoseFilesAreGone() throws {
		let (store, directory) = try tempStore()
		let existing = try existingFile(in: directory, name: "keep.wav")
		let kept = Track(id: UUID(), url: existing, title: "keep", duration: 1)
		let missing = Track(
			id: UUID(),
			url: directory.appendingPathComponent("deleted.wav"),
			title: "gone",
			duration: 1
		)

		store.save(LibrarySnapshot(tracks: [missing, kept], currentTrackID: missing.id))
		let loaded = try #require(store.load())

		#expect(loaded.tracks == [kept])
		// The selection pointed at the dropped track → cleared, not dangling.
		#expect(loaded.currentTrackID == nil)
	}

	@Test func loadReturnsNilWhenNothingWasSaved() throws {
		let (store, _) = try tempStore()
		#expect(store.load() == nil)
	}

	@Test func loadReturnsNilOnACorruptFile() throws {
		let (store, directory) = try tempStore()
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try Data("not json".utf8).write(to: directory.appendingPathComponent("library.json"))

		#expect(store.load() == nil)
	}
}
