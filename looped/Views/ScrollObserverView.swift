import AppKit
import SwiftUI

/// A SwiftUI view that captures global scroll events (trackpad or mouse wheel)
/// **and** horizontal mouse‑dragging to modify an offset.
struct ScrollObserverView: NSViewRepresentable {
	 @Binding var offset: CGFloat
	 var onScrollChange: ((CGFloat) -> Void)? = nil
	 var onScrollEnd: (() -> Void)? = nil

	 func makeNSView(context: Context) -> NSView {
		  let view = ScrollCaptureNSView()
		  view.offsetBinding = $offset
		  view.onScrollChange = onScrollChange
		  view.onScrollEnd = onScrollEnd
		  return view
	 }

	 func updateNSView(_ nsView: NSView, context: Context) {
		  // Nothing to update – the binding is kept live by the view.
	 }

	 /// Custom `NSView` that receives both `scrollWheel` and mouse‑dragging.
	 final class ScrollCaptureNSView: NSView {
		  // MARK: Properties
		  var offsetBinding: Binding<CGFloat>!
		  var onScrollChange: ((CGFloat) -> Void)?
		  var onScrollEnd: (() -> Void)?

		  /// Remember the last location while dragging.
		  private var lastDragLocation: CGPoint?

		  // MARK: - Initial setup
		  override init(frame frameRect: NSRect) {
				super.init(frame: frameRect)
				wantsLayer = true
				// Make the view accept mouse events – we want it to become the first responder.
				self.window?.makeFirstResponder(self)
		  }

		  required init?(coder: NSCoder) { super.init(coder: coder) }

		  // MARK: - Scrolling (trackpad / wheel)
		  override func scrollWheel(with event: NSEvent) {
				// Update offset with the wheel delta.
				offsetBinding.wrappedValue += event.scrollingDeltaX
				onScrollChange?(offsetBinding.wrappedValue)

				// Detect end of momentum‑based scrolling.
				if event.phase == .ended || event.momentumPhase == .ended {
					 onScrollEnd?()
				}
		  }

		  // MARK: - Dragging
		  override func mouseDown(with event: NSEvent) {
				// Only start dragging on the left mouse button.
				guard event.type == .leftMouseDown else { return }
				lastDragLocation = event.locationInWindow
		  }

		  override func mouseDragged(with event: NSEvent) {
				guard let last = lastDragLocation else { return }

				// Δx = current x – previous x
				let deltaX = event.locationInWindow.x - last.x

				// Update the offset (the binding lives on the view itself).
				offsetBinding.wrappedValue += deltaX
				onScrollChange?(offsetBinding.wrappedValue)

				// Remember the new location for the next drag step.
				lastDragLocation = event.locationInWindow
		  }

		  override func mouseUp(with event: NSEvent) {
				lastDragLocation = nil
				onScrollEnd?()
		  }
	 }
}
