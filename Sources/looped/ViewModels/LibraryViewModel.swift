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

	init(player: PlayerViewModel) {
		self.player = player
	}

	// MARK: - Import

	/// Multi-select open panel → `add(urls:)`. If the library was empty,
	/// auto-play the first added track.
	func openFiles() async {
		let urls: [URL] = await MainActor.run {
			let panel = NSOpenPanel()
			panel.allowedContentTypes = [UTType.wav, UTType.mp3, UTType.aiff]
			panel.allowsMultipleSelection = true
			return panel.runModal() == .OK ? panel.urls : []
		}
		guard !urls.isEmpty else { return }

		let wasEmpty = await MainActor.run { tracks.isEmpty }
		await add(urls: urls)
		if wasEmpty, let first = await MainActor.run(body: { tracks.first }) {
			await play(first)
		}
	}

	/// The single intake path (the open panel now; drag & drop later): dedupes
	/// by standardized URL, skips non-audio files silently, reads title +
	/// duration off-main, then publishes the appended rows on main.
	func add(urls: [URL]) async {
		var seen = await MainActor.run { Set(tracks.map { $0.url.standardizedFileURL }) }
		var added: [Track] = []
		for url in urls {
			let standardized = url.standardizedFileURL
			guard !seen.contains(standardized),
			      UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true
			else { continue }
			seen.insert(standardized)
			added.append(await makeTrack(url: url))
		}
		guard !added.isEmpty else { return }
		await MainActor.run { tracks.append(contentsOf: added) }
	}

	// MARK: - Playback bridge

	/// Load + start the track; marks it current only if the load succeeded
	/// (e.g. a >20-min file keeps the previous selection and shows loadError).
	func play(_ track: Track) async {
		await player.load(url: track.url)
		await MainActor.run {
			guard player.loadError == nil else { return }
			currentTrackID = track.id
			if !player.isPlaying {
				player.togglePlayPause()
			}
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
