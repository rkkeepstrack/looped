//
//  HoverActionLabel.swift
//  looped
//
//  A caption label that reveals an action on hover ("Reset" by default) and
//  runs it on click — the shared affordance of the slider labels and the loop
//  panel title.
//

import SwiftUI

struct HoverActionLabel: View {
	let title: String
	var hoverTitle = "Reset"
	/// When non-nil, shown instead of title/hover text, highlighted — e.g. the
	/// live value while a slider is dragged.
	var overrideText: String?
	let action: () -> Void

	@State private var isHovering = false

	var body: some View {
		Text(overrideText ?? (isHovering ? hoverTitle : title))
			.font(.caption)
			.foregroundStyle(overrideText != nil || isHovering ? Theme.textPrimary : Theme.textSecondary)
			.monospacedDigit()
			.contentShape(Rectangle())
			.onHover { isHovering = $0 }
			.onTapGesture(perform: action)
	}
}
