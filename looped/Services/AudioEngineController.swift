//
//  AudioEngineController.swift
//  looped
//
//  Created by Raphael Kalinowski on 28.09.25.
//

import AVFoundation
import Foundation
import SwiftUI
internal import Combine

import AVFoundation
import Foundation
import SwiftUI



class AudioEngineController: ObservableObject {
	
	enum AudioEngineControllerError: Error {
		case bufferCreationFailed
		case nameTooShort(nameLength: Int)
	}
	
	@Published public var isPlaying = false
	@Published public var rate: Float = 1.0
	@Published public var timePitch = AVAudioUnitTimePitch()
	
	@Published public var loopStart: (TimeInterval?,AVAudioFramePosition?) = (timeInterval: nil, frame: nil)
	@Published public var loopEnd: (TimeInterval?, AVAudioFramePosition?) = (timeInterval: nil, frame: nil)
	
	@Published public var currentTime: TimeInterval = 0
	@Published public var currentFileName: String?
	@Published public var audioFile: AVAudioFile?
	@Published public var rawSamples: [Float] = []
	
	var pausedTime: TimeInterval = 0.0
	
	private let engine = AVAudioEngine()
	private let player = AVAudioPlayerNode()
	private var lastPausedTime: TimeInterval = 0
	private var loopTimer: Timer?
	private var timeUpdateTimer: Timer?
	private var fullBuffer: AVAudioPCMBuffer?
	private var isLooping: Bool = false
	
	@Published var duration: TimeInterval?
	
	init() {
		engine.attach(player)
		engine.attach(timePitch)
		engine.connect(player, to: timePitch, format: nil)
		engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
		do { try engine.start() } catch { print("Engine failed: \(error)") }
	}
	
	// MARK: - File Loading
	
	func openFile() async {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [UTType.wav, UTType.mp3, UTType.aiff]
		panel.allowsMultipleSelection = false
		if panel.runModal() == .OK, let url = panel.url {
			do {
				try await load(url: url)
			} catch { print("Could not load file: \(error)") }
		}
	}
	
	func load(url: URL) async throws {
		let file = try AVAudioFile(forReading: url)
		self.audioFile = file
		let format = file.processingFormat
		currentFileName = url.lastPathComponent
		
		// Read file into single buffer
		let capacity = AVAudioFrameCount(file.length)   // file.length is AVAudioFramePosition (Int64)
		guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
			throw AudioEngineControllerError.bufferCreationFailed
		}
		try file.read(into: buffer, frameCount: capacity)
		buffer.frameLength = capacity          // <‑‑ VERY IMPORTANT
		self.fullBuffer = buffer
		await loadDuration()
	}
	
	// MARK: - Playback
	
	func togglePlayPause() -> Void {
		guard audioFile != nil else { return }
		if isPlaying == false {
			self.play()
		} else {
			self.pause()
		}
	}
	
	private func play() {
		if player.lastRenderTime == nil { // means nothing is scheduled
			if let file = audioFile {
				player.scheduleFile(file, at: nil)
			}
		}
		
		player.play()
		isPlaying = true
		startUpdatingCurrentTime()
	}
	
	private func pause() {
		
		player.pause()
		isPlaying = false
		stopUpdatingCurrentTime()
	}
	
	func stop() {
		player.stop()
		stopUpdatingCurrentTime()
		lastPausedTime = 0
		currentTime = 0
		isPlaying = false
	}
	
	func updateRate() {
		timePitch.rate = rate
	}
	
	func updateVolume(volume: Float) {
		player.volume = volume
	}
	
	// MARK: - Timers
	
	func startUpdatingCurrentTime() {
		timeUpdateTimer?.invalidate()
		timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
			guard let self = self else { return }
			currentTime = self.getCurrentTime() ?? lastPausedTime
			
			if reachedEndOfFile() {
				self.stop()
			}
		}
	}
	
	func stopUpdatingCurrentTime() {
		timeUpdateTimer?.invalidate()
		timeUpdateTimer = nil
	}
	
	private func getCurrentTime() -> TimeInterval? {
		guard let nodeTime = player.lastRenderTime,
				let playerTime = player.playerTime(forNodeTime: nodeTime) else { return nil }
		let rateAdjustedTime = Double(playerTime.sampleTime) / (playerTime.sampleRate * Double(timePitch.rate))
		return lastPausedTime + rateAdjustedTime
	}
	
	// MARK: - Jump
	
	func jumpToWithBuffer(time: TimeInterval) {
		guard let file = audioFile else { return }
		
		var wasPlaying = false
		
		if isPlaying {
			wasPlaying = true
			player.stop()
			self.stopUpdatingCurrentTime()
		}
		// Calculate start frame from time
		let startFrame = AVAudioFramePosition(time * file.processingFormat.sampleRate)
		let frameCount = AVAudioFrameCount(file.length - startFrame)
		
		// Make sure the offset is valid
		guard frameCount > 0 else { return }
		
		// Set position in audioFile
		file.framePosition = startFrame
		
		// Create a new buffer from that offset
		let format = file.processingFormat
		if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) {
			do {
				try file.read(into: buffer, frameCount: frameCount)
				// Schedule the buffer
				player.scheduleBuffer(buffer, at: nil, options: .interrupts) {
					// optional: callback when finished
				}
				lastPausedTime = time
				currentTime = time
			} catch {
				print("Error reading buffer: \(error)")
			}
		}
		if wasPlaying {
			self.startUpdatingCurrentTime()
			player.play()
		}
	}
	func jumpTo(time: TimeInterval) {
		guard let file = audioFile else { return }
		
		var wasPlaying = false
		
		if isPlaying {
			wasPlaying = true
			player.stop()
			self.stopUpdatingCurrentTime()
		}
		// Calculate start frame from time
		let startFrame = AVAudioFramePosition(time * file.processingFormat.sampleRate)
		let frameCount = AVAudioFrameCount(file.length - startFrame)
		
		
		player.scheduleSegment(
			file,
			startingFrame: startFrame,
			frameCount: frameCount,
			at: nil,               // play as soon as possible
			completionHandler: nil
		)
		
		lastPausedTime = time
		currentTime = time
		
		if wasPlaying {
			self.startUpdatingCurrentTime()
			player.play()
		}
	}
	
	// MARK: Looping
	
	func setLoopStart(time: TimeInterval?) {
		loopStart = (time, framePosition(for: time))
		setLoop()
	}
	
	func setLoopEnd(time: TimeInterval?) {
		loopEnd = (time, framePosition(for: time))
		setLoop()
	}
	
	func framePosition(for time: TimeInterval?) -> AVAudioFramePosition? {
		guard let file = audioFile, let t = time else { return nil }
		
		return AVAudioFramePosition(t * file.processingFormat.sampleRate)
		
		
	}
		// TODO: doesnt work
	func setLoop() {
		guard let file = audioFile, let start = framePosition(for: loopStart.0), let end = framePosition(for: loopEnd.0), start > end else {
			isLooping = false
			return }
		
		isLooping = true
		
		let frameCount = AVAudioFrameCount(file.length - start)
		
		player.scheduleSegment(
			file,
			startingFrame: start,
			frameCount: frameCount,
			at: nil,               // play as soon as possible
			completionHandler: { [weak self] in
				// When the segment ends, re‑schedule it **if we’re still looping**.
				guard let self = self, self.isLooping, let file = audioFile, let start = framePosition(for: loopStart.0), let end = framePosition(for: loopEnd.0), start > end else { return }
				player.scheduleSegment(			 file,
														 startingFrame: start,
														 frameCount: frameCount,
														 at: nil,completionHandler: nil )
			})
		
	}
	
	
	
	// MARK: Load Duration
	
	func loadDuration() async {
		guard let url = audioFile?.url else { return }
		let asset = AVURLAsset(url: url)
		do {
			let duration = try await asset.load(.duration)
			self.duration = CMTimeGetSeconds(duration)
		} catch {
			print("Failed to load duration: \(error)")
		}
	}
	
	func reachedEndOfFile() -> Bool {
		guard let duration else { return false }
		return currentTime >= duration
	}
	
	
	// MARK: Getters
	
	func getProgressInPercent() -> Double {
		guard let duration = getDuration(), duration > 0 else { return 0 }
		
		return currentTime / duration
	}
	
	func getDuration() -> TimeInterval? {
		return duration ?? nil
	}
}
