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
//  Main-actor-bound: all published state and intents run on the main actor,
//  which also makes the in-flight guards (`playInFlight`, `hasRestored`)
//  race-free without check-and-set choreography.
//

import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
	// MARK: Published state

	@Published private(set) var tracks: [Track] = []
	@Published var currentTrackID: UUID?
	/// Single-click row selection — purely visual until a double-click loads;
	/// the delete keys act on it. Distinct from `currentTrackID` (the *loaded* track).
	@Published var selectedTrackID: UUID?

	// MARK: Wiring (set at the composition root)

	// Per-track parameter bridge to PlayerViewModel (kept callbacks so this VM
	// never references the player VM): on a track switch the outgoing track's
	// slider state is captured and the incoming track's state applied.
	var captureParameters: (() -> TrackParameters)?
	var applyParameters: ((TrackParameters) -> Void)?

	/// The playback store — the library↔playback bridge; both this VM and
	/// PlayerViewModel depend on it, neither references the other.
	private let player: PlaybackCoordinator
	/// Provider→URL resolution + folder expansion for the drop intents.
	private let dropped: DroppedFileService
	/// Persistence: the list + selection survive relaunch.
	private let store: LibraryStore

	/// Guards against overlapping play requests (a double-click fires two row
	/// taps): while one load is in flight, further taps are dropped.
	private var playInFlight = false
	private var hasRestored = false
	private var terminationObserver: NSObjectProtocol?

	init(player: PlaybackCoordinator, dropped: DroppedFileService, store: LibraryStore) {
		self.player = player
		self.dropped = dropped
		self.store = store

		// Slider tweaks are only stashed on a track switch — capture the last
		// track's values (and everything else) once more on quit.
		terminationObserver = NotificationCenter.default.addObserver(
			forName: NSApplication.willTerminateNotification, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.stashCurrentParameters()
				self?.persist()
			}
		}
	}

	deinit {
		if let terminationObserver {
			NotificationCenter.default.removeObserver(terminationObserver)
		}
	}

	// MARK: - Persistence

	/// Repopulate the library from the store (missing files were already
	/// dropped there) and reload the last current track — no autoplay. Latched
	/// to run once — the hosting `.task` re-fires when the window is recreated.
	func restore() async {
		guard !hasRestored else { return }
		hasRestored = true
		guard let snapshot = store.load(), !snapshot.tracks.isEmpty else { return }
		tracks = snapshot.tracks
		if let id = snapshot.currentTrackID,
		   let track = tracks.first(where: { $0.id == id })
		{
			await load(track)
		}
	}

	/// Write the current state through the store; the file is tiny, a
	/// synchronous full rewrite is fine.
	private func persist() {
		store.save(LibrarySnapshot(tracks: tracks, currentTrackID: currentTrackID))
	}

	/// Copy the player's live slider state into the current track's row, so a
	/// track switch (or quit) keeps the values.
	private func stashCurrentParameters() {
		guard let capture = captureParameters,
		      let index = tracks.firstIndex(where: { $0.id == currentTrackID })
		else { return }
		tracks[index].parameters = capture()
	}

	// MARK: - Import & intake

	/// What a completed intake loads into the player (never with autoplay).
	private enum FollowUp {
		/// The first track when the library started empty — the import/drop
		/// convention: something shows in the waveform, nothing plays.
		case firstIfLibraryWasEmpty
		/// The first of these URLs now present in the library (whether it was
		/// just added or already there) — open-and-load / waveform drop.
		case firstMatching([URL])
	}

	/// Multi-select open panel → intake.
	func openFiles() async {
		await intake(urls: presentOpenPanel(forFolders: false), then: .firstIfLibraryWasEmpty)
	}

	/// The transport's open button / File ▸ Open… (⌘O): add, then load the
	/// first chosen track (already-present tracks aren't duplicated).
	func openFilesAndLoad() async {
		let urls = presentOpenPanel(forFolders: false)
		await intake(urls: urls, then: .firstMatching(urls))
	}

	/// The sidebar's "Import Folder" button: choose directories, expand to the
	/// supported audio files inside.
	func openFolder() async {
		await intake(urls: await expand(presentOpenPanel(forFolders: true)), then: .firstIfLibraryWasEmpty)
	}

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

	/// Library-zone drop intake (`index` = the insertion gap under the drop line).
	func addDropped(urls: [URL], at index: Int? = nil) async {
		await intake(urls: await expand(urls), at: index, then: .firstIfLibraryWasEmpty)
	}

	/// Waveform-zone drop intake: only the *first* supported dropped file is
	/// added (deduped) and loaded.
	func loadDropped(urls: [URL]) async {
		guard let first = await expand(urls).first(where: { Track.isSupported(url: $0) })
		else { return }
		await intake(urls: [first], then: .firstMatching([first]))
	}

	/// The single intake path behind every import/drop variant: `add` (dedupe,
	/// filter, metadata, insert), then the variant's follow-up load.
	private func intake(urls: [URL], at index: Int? = nil, then followUp: FollowUp) async {
		guard !urls.isEmpty else { return }
		let wasEmpty = tracks.isEmpty
		await add(urls: urls, at: index)
		switch followUp {
		case .firstIfLibraryWasEmpty:
			if wasEmpty, let first = tracks.first {
				await load(first)
			}
		case let .firstMatching(candidates):
			let chosen = Set(candidates.map { $0.standardizedFileURL })
			if let track = tracks.first(where: { chosen.contains($0.url.standardizedFileURL) }) {
				await load(track)
			}
		}
	}

	/// Dedupes by standardized URL, skips non-audio files silently, reads
	/// title + duration, then inserts at `index` (clamped) or appends when nil.
	func add(urls: [URL], at index: Int? = nil) async {
		var seen = Set(tracks.map { $0.url.standardizedFileURL })
		var added: [Track] = []
		for url in urls {
			let standardized = url.standardizedFileURL
			guard !seen.contains(standardized), Track.isSupported(url: url) else { continue }
			seen.insert(standardized)
			added.append(await makeTrack(url: url))
		}
		guard !added.isEmpty else { return }
		tracks.insert(contentsOf: added, at: min(max(index ?? tracks.count, 0), tracks.count))
		persist()
	}

	/// Reorder rows (the list's reorder drag). Offsets come straight from
	/// SwiftUI, so `Array.move` semantics apply.
	func move(fromOffsets: IndexSet, toOffset: Int) {
		tracks.move(fromOffsets: fromOffsets, toOffset: toOffset)
		persist()
	}

	private func presentOpenPanel(forFolders folders: Bool) -> [URL] {
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = true
		if folders {
			panel.canChooseDirectories = true
			panel.canChooseFiles = false
		} else {
			panel.allowedContentTypes = Track.supportedTypes
		}
		return panel.runModal() == .OK ? panel.urls : []
	}

	/// Folder expansion walks the filesystem recursively — keep it off the main
	/// actor so a big folder drop can't stall the UI.
	private func expand(_ urls: [URL]) async -> [URL] {
		let dropped = dropped
		return await Task.detached { dropped.expandingFolders(in: urls) }.value
	}

	// MARK: - Remove

	/// Remove a track from the library (⌫/⌦ on the selected row). Removing the
	/// currently loaded track unloads it (playback stops, the content view shows
	/// the empty state). Selection moves to the nearest neighbor so repeated
	/// deletes walk the list.
	func remove(id: UUID) {
		guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
		tracks.remove(at: index)
		if currentTrackID == id {
			currentTrackID = nil
			player.unload()
		}
		if selectedTrackID == id {
			selectedTrackID = tracks.isEmpty ? nil : tracks[min(index, tracks.count - 1)].id
		}
		persist()
	}

	/// ⌫/⌦: remove the selected row.
	func removeSelected() {
		guard let id = selectedTrackID else { return }
		remove(id: id)
	}

	// MARK: - Playback bridge

	/// Load the track into the player/waveform (no autoplay — the transport
	/// starts playback); marks it current only if the load succeeded (e.g. a
	/// >20-min file keeps the previous selection and shows loadError).
	@discardableResult
	func load(_ track: Track) async -> Bool {
		guard !playInFlight else { return false }
		playInFlight = true
		defer { playInFlight = false }

		stashCurrentParameters()
		guard await player.load(url: track.url) else { return false }
		// The row may have been removed (⌫) while the decode was in flight —
		// don't resurrect it as the current track.
		guard tracks.contains(where: { $0.id == track.id }) else {
			player.unload()
			return false
		}
		currentTrackID = track.id
		// Look the parameters up by id — the row may have been updated
		// (a stash) since the caller captured `track`.
		let parameters = tracks.first { $0.id == track.id }?.parameters ?? track.parameters
		applyParameters?(parameters)
		persist()
		return true
	}

	// MARK: - Next / previous / auto-advance

	// The *decisions* (ordering, clamping, the 3 s restart rule) live in
	// `TrackNavigation`; these intents only gather state and execute the move.

	/// Step to the next track in list order; clamped — a no-op on the last
	/// track. Preserves the play state (playing stays playing, paused stays paused).
	func next() async {
		await perform(TrackNavigation.next(in: tracks, after: currentTrackID))
	}

	/// Step back in list order — or restart the current material (> 3 s in, or
	/// already on the first track). Preserves the play state.
	func previous() async {
		await perform(TrackNavigation.previous(
			in: tracks,
			before: currentTrackID,
			currentTime: player.currentTime,
			isLoaded: player.currentURL != nil
		))
	}

	/// End-of-track auto-advance (wired to `PlaybackCoordinator.onTrackEnded`):
	/// play the next track; on the last track the transport just stays stopped.
	func trackEnded() async {
		guard case let .change(target)? = TrackNavigation.next(in: tracks, after: currentTrackID)
		else { return }
		if await load(target) {
			player.play()
		}
	}

	/// Execute a navigation move. A change carries the play state over: if
	/// audio was playing, the new track keeps playing; if paused, it loads paused.
	private func perform(_ move: TrackNavigation.Move?) async {
		switch move {
		case .restart:
			// Restarts the armed loop at A, or the track at 0.
			player.restart()
		case let .change(target):
			let wasPlaying = player.isPlaying
			if await load(target), wasPlaying {
				player.play()
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
