import AppKit
import SwiftUI

extension View {
	/// Overlays a transparent capture layer feeding scroll-wheel/trackpad and
	/// horizontal mouse-drag deltas into `offset` (the waveform scrub).
	func observeScrolling(
		offset: Binding<CGFloat>,
		onChange: ((CGFloat) -> Void)? = nil,
		onEnd: (() -> Void)? = nil
	) -> some View {
		overlay(ScrollObserverView(offset: offset, onScrollChange: onChange, onScrollEnd: onEnd))
	}
}

/// The capture layer behind `observeScrolling`: receives scroll events
/// (trackpad or mouse wheel) **and** horizontal mouse-dragging.
private struct ScrollObserverView: NSViewRepresentable {
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

	func updateNSView(_: NSView, context _: Context) {
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

		/// Deferred finger-lift seek, waiting to see whether momentum follows.
		private var pendingEndTimer: Timer?

		deinit {
			pendingEndTimer?.invalidate()
		}

		// MARK: - Initial setup

		override init(frame frameRect: NSRect) {
			super.init(frame: frameRect)
			wantsLayer = true
			// Make the view accept mouse events – we want it to become the first responder.
			window?.makeFirstResponder(self)
		}

		required init?(coder: NSCoder) {
			super.init(coder: coder)
		}

		// MARK: - Scrolling (trackpad / wheel)

		override func scrollWheel(with event: NSEvent) {
			// Zero deltas (a touch that never moves, e.g. stopping a glide) must not
			// register as scrubbing — the callback latches the scrub state.
			if event.scrollingDeltaX != 0 {
				offsetBinding.wrappedValue += event.scrollingDeltaX
				onScrollChange?(offsetBinding.wrappedValue)
			}

			// Trackpad momentum is part of the scrub: the single seek fires when the
			// glide actually stops, not at finger lift (which double-seeked — once at
			// lift, once at fade-out). Whether momentum will follow a lift is unknown
			// at the lift itself, so that seek is deferred a beat and cancelled when
			// momentum picks the gesture up.
			if event.momentumPhase == .began {
				pendingEndTimer?.invalidate()
				pendingEndTimer = nil
			} else if event.momentumPhase == .ended || event.momentumPhase == .cancelled {
				onScrollEnd?()
			} else if event.phase == .ended || event.phase == .cancelled {
				let timer = Timer(timeInterval: 0.1, repeats: false) { [weak self] _ in
					self?.onScrollEnd?()
				}
				RunLoop.main.add(timer, forMode: .common)
				pendingEndTimer = timer
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

		override func mouseUp(with _: NSEvent) {
			lastDragLocation = nil
			onScrollEnd?()
		}
	}
}
