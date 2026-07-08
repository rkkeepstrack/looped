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

enum AudioFileServiceError: Error {
	case bufferCreationFailed
}

struct DefaultAudioFileService: AudioFileService {
	func load(url: URL) async throws -> LoadedAudio {
		let file = try AVAudioFile(forReading: url)
		let format = file.processingFormat

		let capacity = AVAudioFrameCount(file.length)
		guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
			throw AudioFileServiceError.bufferCreationFailed
		}
		try file.read(into: buffer, frameCount: capacity)
		buffer.frameLength = capacity

		let duration = format.sampleRate > 0 ? Double(file.length) / format.sampleRate : 0
		return LoadedAudio(url: url, file: file, buffer: buffer, format: format, duration: duration)
	}
}
