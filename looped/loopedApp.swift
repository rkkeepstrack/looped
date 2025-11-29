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
			GeometryReader { g in
				ContentView().environmentObject(audioEngineController).environmentObject(offsetCalculator)
			}.frame(minWidth: 1024, maxWidth: .infinity, minHeight: 800, maxHeight: .infinity)
				.padding(.horizontal, 20)
				.cornerRadius(12)
				.shadow(radius: 5)
		}
	}
}
