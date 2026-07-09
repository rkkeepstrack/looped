//
//  DroppedFileServiceTests.swift
//  loopedTests
//
//  Folder expansion over a real temp directory tree. Provider→URL resolution
//  (NSItemProvider) stays a manual check — it needs a live drag pasteboard.
//

import Foundation
@testable import looped
import Testing

struct DroppedFileServiceTests {
	private let service = DefaultDroppedFileService()

	/// Builds a fixture tree: root/{a.wav, notes.txt, nested/{b.wav, cover.png}}.
	/// Files only need to exist — expansion filters by extension, not content.
	private func makeFixtureTree() throws -> (root: URL, wavA: URL, wavB: URL) {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("looped-tree-\(UUID().uuidString)")
		let nested = root.appendingPathComponent("nested")
		try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
		let wavA = root.appendingPathComponent("a.wav")
		let wavB = nested.appendingPathComponent("b.wav")
		try Data().write(to: wavA)
		try Data().write(to: wavB)
		try "not audio".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
		try Data().write(to: nested.appendingPathComponent("cover.png"))
		return (root, wavA, wavB)
	}

	@Test func expandingFoldersRecursesAndFiltersToSupportedAudio() throws {
		let (root, wavA, wavB) = try makeFixtureTree()

		let expanded = service.expandingFolders(in: [root])

		#expect(Set(expanded.map(\.lastPathComponent)) == Set([wavA, wavB].map(\.lastPathComponent)))
	}

	@Test func expandingFoldersPassesPlainFilesThrough() throws {
		let wav = try AudioFixture.tempSine(seconds: 1)
		let text = FileManager.default.temporaryDirectory
			.appendingPathComponent("looped-fixture-\(UUID().uuidString).txt")
		try "not audio".write(to: text, atomically: true, encoding: .utf8)

		// Plain files aren't filtered here — add(urls:) applies the predicate.
		#expect(service.expandingFolders(in: [wav, text]) == [wav, text])
	}
}
