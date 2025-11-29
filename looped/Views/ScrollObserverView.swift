import AppKit
import SwiftUI

/// A SwiftUI view that captures global scroll events (trackpad or mouse wheel)
struct ScrollObserverView: NSViewRepresentable {
	@Binding var offset: CGFloat
	var onScrollChange: ((CGFloat) -> Void)? = nil
	var onScrollEnd: (() -> Void)? = nil

	func makeNSView(context _: Context) -> NSView {
		let view = ScrollCaptureNSView()
		view.offsetBinding = $offset
		view.onScrollChange = onScrollChange
		view.onScrollEnd = onScrollEnd
		return view
	}

	func updateNSView(_: NSView, context _: Context) {}

	/// Custom NSView subclass that receives scrollWheel events
	class ScrollCaptureNSView: NSView {
		var offsetBinding: Binding<CGFloat>!
		var onScrollChange: ((CGFloat) -> Void)?
		var onScrollEnd: (() -> Void)?

		override func scrollWheel(with event: NSEvent) {
			// Update offset
			offsetBinding.wrappedValue += event.scrollingDeltaX

			// Fire change event every time the scroll offset updates
			onScrollChange?(offsetBinding.wrappedValue)

			// Detect end of scrolling
			if event.phase == .ended || event.momentumPhase == .ended {
				onScrollEnd?()
			}
		}
	}
}
