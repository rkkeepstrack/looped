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

	@Published public var isPlaying = false
	@Published public var rate: Float = 1.0
	@Published public var timePitch = AVAudioUnitTimePitch()

	@Published public var loopStart: TimeInterval = 0
	@Published public var loopEnd: TimeInterval = 0
	@Published public var currentTime: TimeInterval = 0
	@Published public var currentFileName: String?
	@Published public var audioFile: AVAudioFile?
	var pausedTime: TimeInterval = 0.0

	private let engine = AVAudioEngine()
	private let player = AVAudioPlayerNode()
	private var lastPausedTime: TimeInterval = 0
	private var loopTimer: Timer?
	private var timeUpdateTimer: Timer?

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
				audioFile = try AVAudioFile(forReading: url)
				if let audioFile {
					currentFileName = url.lastPathComponent
					await loadDuration()
					await player.scheduleFile(audioFile, at: nil)
				}

			} catch { print("Could not load file: \(error)") }
		}
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
		return currentTime / (getDuration() ?? 1)
	}

	func getDuration() -> TimeInterval? {
		return duration ?? nil
	}
}
