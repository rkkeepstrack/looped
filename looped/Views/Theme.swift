//
//  Theme.swift
//  looped
//
//  Shared design tokens (colors, metrics). Introduced for the waveform redesign
//  (plans/01); expanded by the full UI redesign (plans/03). Keep presentation
//  constants here rather than scattered literals across views.
//

import SwiftUI

enum Theme {
	// MARK: Palette — warm orange on black

	static let background = Color(red: 0.055, green: 0.055, blue: 0.063) // #0E0E10
	static let surface = Color(red: 0.105, green: 0.105, blue: 0.118) // #1B1B1E
	static let accent = Color(red: 1.0, green: 0.478, blue: 0.102) // #FF7A1A
	static let accentDim = Color(red: 0.72, green: 0.34, blue: 0.07)
	static let textPrimary = Color(red: 0.96, green: 0.96, blue: 0.96)
	static let textSecondary = Color(red: 0.60, green: 0.60, blue: 0.64)

	// MARK: Waveform

	/// Already-played portion of the waveform (left of the center iterator).
	static let waveformPlayed = accent
	/// Upcoming portion of the waveform.
	static let waveformUpcoming = Color(red: 0.28, green: 0.28, blue: 0.31)
	/// Translucent fill shading the A–B loop region.
	static let loopRegion = accent.opacity(0.15)
	static let loopMarkerA = accent
	static let loopMarkerB = Color(red: 1.0, green: 0.66, blue: 0.30) // lighter amber
	/// Fixed center playhead line.
	static let iterator = Color.white.opacity(0.85)
}
