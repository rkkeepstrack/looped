import SwiftUI
import AppKit

/// A SwiftUI view that captures global scroll events (trackpad or mouse wheel)
struct ScrollCaptureView: NSViewRepresentable {
	@Binding var offset: CGFloat
	
	func makeNSView(context: Context) -> NSView {
		let view = ScrollCaptureNSView()
		view.offsetBinding = $offset
		return view
	}
	
	func updateNSView(_ nsView: NSView, context: Context) {}
	
	/// Custom NSView subclass that receives scrollWheel events
	class ScrollCaptureNSView: NSView {
		var offsetBinding: Binding<CGFloat>!
		
		override func scrollWheel(with event: NSEvent) {
			// Update the SwiftUI binding with the scroll delta
			offsetBinding.wrappedValue += event.scrollingDeltaY
		}
	}
}
