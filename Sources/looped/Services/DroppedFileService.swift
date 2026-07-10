//
//  DroppedFileService.swift
//  looped
//
//  Drag & drop file plumbing: resolving drag-pasteboard item providers into
//  URLs and expanding dropped folders into the supported audio files inside.
//  I/O only (FileManager + NSItemProvider) — no library state, no UI — so the
//  view-models stay pure intents and tests can fake the filesystem walk.
//

import Foundation
import UniformTypeIdentifiers

protocol DroppedFileService {
	/// Resolves dropped `.fileURL` item providers into URLs.
	func urls(from providers: [NSItemProvider]) async -> [URL]
	/// Recursively expands folder URLs into the supported audio files inside;
	/// plain file URLs pass through untouched.
	func expandingFolders(in urls: [URL]) -> [URL]
}

struct DefaultDroppedFileService: DroppedFileService {
	/// macOS delivers the `.fileURL` payload as `Data`; reconstruct with
	/// `URL(dataRepresentation:relativeTo:)`.
	func urls(from providers: [NSItemProvider]) async -> [URL] {
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

	/// Folder contents are filtered to `Track.isSupported` and sorted by path
	/// for a stable row order; the type filter for plain files stays in
	/// `LibraryViewModel.add(urls:)`.
	func expandingFolders(in urls: [URL]) -> [URL] {
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
}
