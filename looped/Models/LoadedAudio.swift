//
//  LoadedAudio.swift
//  looped
//
//  The decoded result of loading an audio file: the file handle (for scheduling
//  playback/segments), the full PCM buffer (for slicing loop regions), and
//  derived metadata. Produced by `AudioFileService`, held by `PlayerViewModel`.
//

import AVFoundation

struct LoadedAudio {
	let url: URL
	let file: AVAudioFile
	let buffer: AVAudioPCMBuffer
	let format: AVAudioFormat
	let duration: TimeInterval
}
