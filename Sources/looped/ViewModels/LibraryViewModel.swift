//
//  LibraryViewModel.swift
//  looped
//
//  The track library: holds the sidebar's track list, owns the import panel
//  (import is library UI, not playback), and bridges row taps to playback by
//  delegating to PlayerViewModel. Metadata for the list comes from AVURLAsset
//  (cheap container read) — the full decode still happens per play via
//  AudioFileService, so the 20-min limit / loadError path applies on play.
//

import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

final class LibraryViewModel: ObservableObject {
	// MARK: Published state

	@Published private(set) var tracks: [Track] = []
	@Published var currentTrackID: UUID?

	/// View-model → view-model is deliberate here: this is the bridge between
	/// the library and playback; the services underneath stay UI-free.
	private let player: PlayerViewModel

	/// Guards against overlapping play requests (a double-click fires two row
	/// taps): while one load is in flight, further taps are dropped. Main-actor
	/// mutated, so the check-and-set is race-free.
	private var playInFlight = false

	init(player: PlayerViewModel) {
		self.player = player
	}

	// MARK: - Import

	/// Multi-select open panel → `add(urls:)`. If the library was empty,
	/// auto-load the first added track (into the waveform; playback stays paused).
	func openFiles() async {
		let urls: [URL] = await MainActor.run {
			let panel = NSOpenPanel()
			panel.allowedContentTypes = Track.supportedTypes
			panel.allowsMultipleSelection = true
			return panel.runModal() == .OK ? panel.urls : []
		}
		guard !urls.isEmpty else { return }

		let wasEmpty = await MainActor.run { tracks.isEmpty }
		await add(urls: urls)
		if wasEmpty, let first = await MainActor.run(body: { tracks.first }) {
			await load(first)
		}
	}

	/// The single intake path (open panel + drag & drop): dedupes by
	/// standardized URL, skips non-audio files silently, reads title + duration
	/// off-main, then publishes the new rows on main — inserted at `index`
	/// (clamped; e.g. a drop between two rows) or appended when nil.
	func add(urls: [URL], at index: Int? = nil) async {
		var seen = await MainActor.run { Set(tracks.map { $0.url.standardizedFileURL }) }
		var added: [Track] = []
		for url in urls {
			let standardized = url.standardizedFileURL
			guard !seen.contains(standardized), Track.isSupported(url: url) else { continue }
			seen.insert(standardized)
			added.append(await makeTrack(url: url))
		}
		guard !added.isEmpty else { return }
		await MainActor.run {
			if let index {
				tracks.insert(contentsOf: added, at: min(max(index, 0), tracks.count))
			} else {
				tracks.append(contentsOf: added)
			}
		}
	}

	/// Reorder rows (the List's `.onMove` drag). Offsets come straight from
	/// SwiftUI, so `Array.move` semantics apply.
	@MainActor func move(fromOffsets: IndexSet, toOffset: Int) {
		tracks.move(fromOffsets: fromOffsets, toOffset: toOffset)
	}

	// MARK: - Drag & drop intake

	/// Library-zone drop intake: expands folders into the supported audio files
	/// inside, then feeds the regular `add(urls:at:)` path (`index` = the List
	/// insertion point under the drop line). Mirrors `openFiles()`: when the
	/// library was empty, the first added track is loaded (no autoplay).
	/// This type isn't main-actor-bound, so the folder walk runs off-main.
	func addDropped(urls: [URL], at index: Int? = nil) async {
		let expanded = Self.expandingFolders(in: urls)
		guard !expanded.isEmpty else { return }

		let wasEmpty = await MainActor.run { tracks.isEmpty }
		await add(urls: expanded, at: index)
		if wasEmpty, let first = await MainActor.run(body: { tracks.first }) {
			await load(first)
		}
	}

	/// Waveform-zone drop intake: the first supported dropped file is added to
	/// the library (deduped — an already-present track isn't duplicated) and
	/// loaded immediately.
	func loadDropped(urls: [URL]) async {
		let expanded = Self.expandingFolders(in: urls)
		guard let first = expanded.first(where: { Track.isSupported(url: $0) }) else { return }

		await add(urls: [first])
		let standardized = first.standardizedFileURL
		let track = await MainActor.run {
			tracks.first { $0.url.standardizedFileURL == standardized }
		}
		if let track { await load(track) }
	}

	/// Recursively expands folder URLs into the supported audio files inside
	/// (sorted by path for a stable row order); plain file URLs pass through
	/// untouched — `add(urls:)` applies the type filter to those.
	static func expandingFolders(in urls: [URL]) -> [URL] {
		var expanded: [URL] = []
		for url in urls {
			guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
				expanded.append(url)
				continue
			}
			let enumerator = FileManager.default.enumerator(
				at: url,
				includingPropertiesForKeys: [.isRegularFileKey]
			)
			var found: [URL] = []
			while let file = enumerator?.nextObject() as? URL {
				guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
				      Track.isSupported(url: file)
				else { continue }
				found.append(file)
			}
			expanded.append(contentsOf: found.sorted { $0.path < $1.path })
		}
		return expanded
	}

	/// Resolves dropped `.fileURL` item providers into URLs. macOS delivers the
	/// payload as `Data`; reconstruct with `URL(dataRepresentation:relativeTo:)`.
	static func urls(from providers: [NSItemProvider]) async -> [URL] {
		var urls: [URL] = []
		for provider in providers
			where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
		{
			let url: URL? = await withCheckedContinuation { continuation in
				provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
					switch item {
					case let data as Data:
						continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
					case let url as URL:
						continuation.resume(returning: url)
					default:
						continuation.resume(returning: nil)
					}
				}
			}
			if let url { urls.append(url) }
		}
		return urls
	}

	// MARK: - Playback bridge

	/// Load the track into the player/waveform (no autoplay — the transport
	/// starts playback); marks it current only if the load succeeded (e.g. a
	/// >20-min file keeps the previous selection and shows loadError).
	func load(_ track: Track) async {
		let alreadyInFlight = await MainActor.run { () -> Bool in
			if playInFlight { return true }
			playInFlight = true
			return false
		}
		guard !alreadyInFlight else { return }

		await player.load(url: track.url)
		await MainActor.run {
			playInFlight = false
			guard player.loadError == nil else { return }
			currentTrackID = track.id
		}
	}

	// MARK: - Metadata

	private func makeTrack(url: URL) async -> Track {
		let asset = AVURLAsset(url: url)

		var duration: TimeInterval?
		if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
			duration = seconds
		}

		var title = url.deletingPathExtension().lastPathComponent
		if let items = try? await asset.load(.commonMetadata),
		   let item = items.first(where: { $0.commonKey == .commonKeyTitle }),
		   let value = try? await item.load(.stringValue), !value.isEmpty
		{
			title = value
		}

		return Track(id: UUID(), url: url, title: title, duration: duration)
	}
}
