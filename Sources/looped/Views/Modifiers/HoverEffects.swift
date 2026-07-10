//
//  HoverEffects.swift
//  looped
//
//  Hover feedback for buttons (macOS buttons give none by default, which reads
//  as non-interactive): a background wash for borderless icon/text buttons and
//  a slight brighten for bordered ones (whose bezel would hide a wash behind
//  it). Both no-ops while the control is disabled.
//

import SwiftUI

extension View {
	/// Rounded background wash on hover — for borderless buttons.
	func hoverHighlight(cornerRadius: CGFloat = 5) -> some View {
		modifier(HoverHighlightModifier(cornerRadius: cornerRadius))
	}

	/// Slight brighten on hover — for bordered/prominent buttons.
	func hoverBrightness() -> some View {
		modifier(HoverBrightnessModifier())
	}
}

private struct HoverHighlightModifier: ViewModifier {
	let cornerRadius: CGFloat
	@Environment(\.isEnabled) private var isEnabled
	@State private var isHovering = false

	func body(content: Content) -> some View {
		content
			.background(
				RoundedRectangle(cornerRadius: cornerRadius)
					.fill(Theme.hoverWash)
					.opacity(isHovering && isEnabled ? 1 : 0)
			)
			.onHover { isHovering = $0 }
	}
}

private struct HoverBrightnessModifier: ViewModifier {
	@Environment(\.isEnabled) private var isEnabled
	@State private var isHovering = false

	func body(content: Content) -> some View {
		content
			.brightness(isHovering && isEnabled ? 0.15 : 0)
			.onHover { isHovering = $0 }
	}
}
