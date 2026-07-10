//
//  LibraryViewModel.swift
//  looped
//
//  The track library: holds the sidebar's track list, owns the import panel
//  (import is library UI, not playback), and bridges row taps / next-previous /
//  auto-advance to playback via PlaybackCoordinator. Metadata for the list
//  comes from AVURLAsset (cheap container read) — the full decode still
//  happens per play via AudioFileService, so the 20-min limit / loadError
//  path applies on play.
//

import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

final class LibraryViewModel: ObservableObject {
	// MARK: Published state

	@Published private(set) var tracks: [Track] = []
	@Published var currentTrackID: UUID?

	/// The playback store — the library↔playback bridge; both this VM and
	/// PlayerViewModel depend on it, neither references the other.
	private let player: PlaybackCoordinator
	/// Provider→URL resolution + folder expansion for the drop intents.
	private let dropped: DroppedFileService

	/// Guards against overlapping play requests (a double-click fires two row
	/// taps): while one load is in flight, further taps are dropped. Main-actor
	/// mutated, so the check-and-set is race-free.
	private var playInFlight = false

	init(player: PlaybackCoordinator, dropped: DroppedFileService) {
		self.player = player
		self.dropped = dropped
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
		// Capture an immutable copy: referencing the mutated var from the
		// concurrently-executing closure is an error in Swift 6 mode.
		let newTracks = added
		await MainActor.run {
			if let index {
				tracks.insert(contentsOf: newTracks, at: min(max(index, 0), tracks.count))
			} else {
				tracks.append(contentsOf: newTracks)
			}
		}
	}

	/// Reorder rows (the List's `.onMove` drag). Offsets come straight from
	/// SwiftUI, so `Array.move` semantics apply.
	@MainActor func move(fromOffsets: IndexSet, toOffset: Int) {
		tracks.move(fromOffsets: fromOffsets, toOffset: toOffset)
	}

	// MARK: - Drag & drop intake

	/// Library-zone drop (the sidebar list / empty state): resolve the drag's
	/// item providers, then insert at the drop gap. Views hand the providers
	/// straight over — the NSItemProvider plumbing stays out of the view layer.
	func handleLibraryDrop(providers: [NSItemProvider], at index: Int? = nil) async {
		await addDropped(urls: dropped.urls(from: providers), at: index)
	}

	/// Waveform-zone drop: resolve providers, then load the first supported
	/// file immediately.
	func handleWaveformDrop(providers: [NSItemProvider]) async {
		await loadDropped(urls: dropped.urls(from: providers))
	}

	/// Library-zone drop intake: expands folders into the supported audio files
	/// inside, then feeds the regular `add(urls:at:)` path (`index` = the
	/// insertion gap under the drop line). Mirrors `openFiles()`: when the
	/// library was empty, the first added track is loaded (no autoplay).
	/// This type isn't main-actor-bound, so the folder walk runs off-main.
	func addDropped(urls: [URL], at index: Int? = nil) async {
		let expanded = dropped.expandingFolders(in: urls)
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
		let expanded = dropped.expandingFolders(in: urls)
		guard let first = expanded.first(where: { Track.isSupported(url: $0) }) else { return }

		await add(urls: [first])
		let standardized = first.standardizedFileURL
		let track = await MainActor.run {
			tracks.first { $0.url.standardizedFileURL == standardized }
		}
		if let track { await load(track) }
	}

	// MARK: - Playback bridge

	/// Load the track into the player/waveform (no autoplay — the transport
	/// starts playback); marks it current only if the load succeeded (e.g. a
	/// >20-min file keeps the previous selection and shows loadError).
	@discardableResult
	func load(_ track: Track) async -> Bool {
		let alreadyInFlight = await MainActor.run { () -> Bool in
			if playInFlight { return true }
			playInFlight = true
			return false
		}
		guard !alreadyInFlight else { return false }

		let loadedOK = await player.load(url: track.url)
		await MainActor.run {
			playInFlight = false
			if loadedOK { currentTrackID = track.id }
		}
		return loadedOK
	}

	// MARK: - Next / previous / auto-advance

	// The *decisions* (ordering, clamping, the 3 s restart rule) live in
	// `TrackNavigation`; these intents only gather state and execute the move.

	/// Step to the next track in list order; clamped — a no-op on the last
	/// track. Preserves the play state (playing stays playing, paused stays paused).
	func next() async {
		let move = await MainActor.run { TrackNavigation.next(in: tracks, after: currentTrackID) }
		await perform(move)
	}

	/// Step back in list order — or restart the current material (> 3 s in, or
	/// already on the first track). Preserves the play state.
	func previous() async {
		let move = await MainActor.run {
			TrackNavigation.previous(
				in: tracks,
				before: currentTrackID,
				currentTime: player.currentTime,
				isLoaded: player.currentURL != nil
			)
		}
		await perform(move)
	}

	/// End-of-track auto-advance (wired to `PlaybackCoordinator.onTrackEnded`):
	/// play the next track; on the last track the transport just stays stopped.
	func trackEnded() async {
		guard case let .change(target)? = await MainActor.run(body: {
			TrackNavigation.next(in: tracks, after: currentTrackID)
		}) else { return }
		if await load(target) {
			await MainActor.run { player.play() }
		}
	}

	/// Execute a navigation move. A change carries the play state over: if
	/// audio was playing, the new track keeps playing; if paused, it loads paused.
	private func perform(_ move: TrackNavigation.Move?) async {
		switch move {
		case .restart:
			// Restarts the armed loop at A, or the track at 0.
			await MainActor.run { player.restart() }
		case let .change(target):
			let wasPlaying = await MainActor.run { player.isPlaying }
			if await load(target), wasPlaying {
				await MainActor.run { player.play() }
			}
		case nil:
			break
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
