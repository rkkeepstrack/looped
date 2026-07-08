//
//  AudioFileService.swift
//  looped
//
//  File handling: decodes an audio file at a URL into a `LoadedAudio`. Pure and
//  URL-based (no file picker, no UI) so the same entry point serves the open
//  panel today and drag-and-drop later. `async` so the decode runs off the main
//  thread when awaited from the (main-actor) view-model.
//

import AVFoundation

protocol AudioFileService: Sendable {
	func load(url: URL) async throws -> LoadedAudio
}

enum AudioFileServiceError: Error, LocalizedError {
	case bufferCreationFailed
	case tooLong(maxMinutes: Int)

	var errorDescription: String? {
		switch self {
		case .bufferCreationFailed: "Couldn't read that audio file."
		case let .tooLong(maxMinutes): "That track is longer than \(maxMinutes) minutes."
		}
	}
}

struct DefaultAudioFileService: AudioFileService {
	/// Maximum supported track length; longer files are rejected.
	static let maxDurationMinutes = 20

	func load(url: URL) async throws -> LoadedAudio {
		let file = try AVAudioFile(forReading: url)
		let format = file.processingFormat

		let duration = format.sampleRate > 0 ? Double(file.length) / format.sampleRate : 0
		guard duration <= Double(Self.maxDurationMinutes) * 60 else {
			throw AudioFileServiceError.tooLong(maxMinutes: Self.maxDurationMinutes)
		}

		let capacity = AVAudioFrameCount(file.length)
		guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
			throw AudioFileServiceError.bufferCreationFailed
		}
		try file.read(into: buffer, frameCount: capacity)
		buffer.frameLength = capacity

		return LoadedAudio(url: url, file: file, buffer: buffer, format: format, duration: duration)
	}
}
