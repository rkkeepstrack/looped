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
	/// Warm yellow marking a control's active/engaged state (playthrough-mode
	/// icon; plan 07's sync-link icon) — distinct from the accent orange so it
	/// reads as state, not selection.
	static let controlActive = Color(red: 1.0, green: 0.78, blue: 0.25) // #FFC740
	static let textPrimary = Color(red: 0.96, green: 0.96, blue: 0.96)
	static let textSecondary = Color(red: 0.60, green: 0.60, blue: 0.64)

	// MARK: Waveform

	/// Already-played portion of the waveform (left of the center iterator).
	static let waveformPlayed = accent
	static let waveformUpcoming = Color(red: 0.28, green: 0.28, blue: 0.31)
	/// Translucent fill shading the A–B loop region (matches the markers' blue).
	static let loopRegion = loopMarkerA.opacity(0.12)
	/// Loop markers: cool blues so they stand apart from the played-orange
	/// waveform; A lighter, B deeper, so the two also differ from each other.
	static let loopMarkerA = Color(red: 0.42, green: 0.72, blue: 0.95) // light sky blue
	static let loopMarkerB = Color(red: 0.30, green: 0.55, blue: 0.90) // deeper blue
	/// Fixed center playhead line.
	static let iterator = Color.white.opacity(0.85)
	/// Scrub highlight — subtle light blue (the cool counterpart to the warm
	/// played-orange), drawn between the played edge and the scrub cursor.
	static let waveformScrub = Color(red: 0.45, green: 0.68, blue: 0.90).opacity(0.75)
	/// Horizontal midline of the main waveform (the mirror axis the stripes
	/// reflect around) — subtle, always visible.
	static let waveformCenterline = Color(white: 0.5).opacity(0.25)
	/// Translucent light-gray wash over the waveform while a file drag hovers
	/// the waveform drop zone (drop → load immediately).
	static let waveformDropHighlight = Color(white: 0.85).opacity(0.18)

	// MARK: Overview strip (minimap)

	/// Fixed height of the full-track overview strip under the main waveform.
	static let overviewHeight: CGFloat = 48
	/// Played tint on the overview strip — much subtler than the main waveform's
	/// full-accent orange, which reads harsh at strip size.
	static let overviewPlayed = accentDim.opacity(0.45)
	/// The visible-window highlight box on the overview strip.
	static let overviewBoxFill = Color(white: 0.85).opacity(0.12)
	static let overviewBoxStroke = Color(white: 0.85).opacity(0.45)

	// MARK: Metrics

	/// Default sidebar width; the user can drag the divider between
	/// `sidebarMinWidth` and `sidebarMaxWidth` (persisted via @AppStorage).
	static let sidebarWidth: CGFloat = 220
	static let sidebarMinWidth: CGFloat = 160
	static let sidebarMaxWidth: CGFloat = 420
	/// Fixed sidebar track-row height — uniform rows keep the hand-rolled
	/// reorder/drop index math trivial (`RowInsertion`).
	static let trackRowHeight: CGFloat = 28
	/// The reorder/drop insertion line in the track list: dimmed text color,
	/// quieter than the accent.
	static let insertionLine = textPrimary.opacity(0.6)
	static let panelCorner: CGFloat = 12
	static let panelBorder = Color.white.opacity(0.08)
	/// Background wash for hovered borderless buttons (`hoverHighlight()`).
	static let hoverWash = Color.white.opacity(0.12)
	/// Toast cards cap their width so aggregated messages wrap instead of
	/// spanning the window.
	static let toastMaxWidth: CGFloat = 380

	// MARK: Animation

	/// Sidebar open/close timing. Shared by the layout animation and the matching
	/// window during which the waveform's render width is frozen (so they align).
	static let sidebarAnimationDuration: Double = 0.28
	static let sidebarAnimation: Animation = .easeInOut(duration: sidebarAnimationDuration)
}
