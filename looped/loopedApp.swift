//
//  loopedApp.swift
//  looped
//
//  Created by Raphael Kalinowsi on 28.09.25.
//

import SwiftUI

@main
struct loopedApp: App {
	@StateObject private var audioEngineController = AudioEngineController()

	var body: some Scene {
		WindowGroup {
			ContentView(audioPlayer: audioEngineController)
		}
	}
}
