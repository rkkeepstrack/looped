//
//  AudioEngineController.swift
//  looped
//
//  Created by Raphael Kalinowski on 28.09.25.
//

import Foundation
import AVFoundation
import SwiftUI
internal import Combine

import Foundation
import AVFoundation
import SwiftUI

class AudioEngineController: ObservableObject {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()
    var audioFile: AVAudioFile?
    private var segmentStartTime: TimeInterval = 0
    
    @Published var isPlaying = false
    @Published var rate: Float = 1.0

    @Published var loopStart: TimeInterval = 0
    @Published var loopEnd: TimeInterval = 0
    @Published var currentTime: TimeInterval = 0
    @Published var currentFileName: String?
    
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
                currentFileName = url.lastPathComponent
                stop()
                await loadDuration()
            } catch { print("Could not load file: \(error)") }
        }
    }

    // MARK: - Playback
    func togglePlayPause() {
        guard audioFile != nil else { return }
        if isPlaying {
            segmentStartTime = currentTime
            player.pause()
            isPlaying = false
            stopUpdatingCurrentTime()
        } else {
            player.play()
            isPlaying = true
            startUpdatingCurrentTime()
        }
    }

    func stop() {
        player.stop()
		stopUpdatingCurrentTime()
        segmentStartTime = 0
		currentTime = 0
        isPlaying = false
    }

    func updateRate() {
        timePitch.rate = rate
    }

    // MARK: - Timers
    func startUpdatingCurrentTime() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            currentTime = self.getCurrentTime() ?? segmentStartTime
			
			if(reachedEndOfFile()) {
				self.stop()
			}
        }
    }
    func stopUpdatingCurrentTime() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }

    func getCurrentTime() -> TimeInterval? {
        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return nil }
        let currentSegmentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
        return segmentStartTime + currentSegmentTime
    }

    // MARK: - Jump
    func jumpTo(time: TimeInterval) {
        guard let file = audioFile else { return }

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
                segmentStartTime = time
                currentTime = time
            } catch {
                print("Error reading buffer: \(error)")
            }
        }
    }
    
    // MARK: - Duration Loader
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


    // MARK: - Waveform Generation
    func generateWaveformSamples(width: Int) -> [CGFloat] {
        guard let file = audioFile else { return [] }
        let frameCount = Int(file.length)
        let downSample = max(frameCount / width, 1)
        var samples: [CGFloat] = []
        file.framePosition = 0
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frameCount))!
        try? file.read(into: buffer)
        if let channelData = buffer.floatChannelData?[0] {
            for i in stride(from: 0, to: frameCount, by: downSample) {
                let end = min(i + downSample, frameCount)
                let slice = Array(UnsafeBufferPointer(start: channelData + i, count: end - i))
                let maxSample = slice.map { abs($0) }.max() ?? 0
                samples.append(CGFloat(maxSample))
            }

        }
        return samples
    }
}
