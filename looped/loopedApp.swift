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
	@StateObject private var offsetCalculator = OffsetCalculator()

	var body: some Scene {
		WindowGroup {
			ContentView().environmentObject(audioEngineController).environmentObject(offsetCalculator)
		}
	}
}
