//
//  RightClick.swift
//  looped
//
//  SwiftUI has no right-click gesture on macOS — this invisible overlay claims
//  only right-button events (via the hitTest/currentEvent check) and lets every
//  other event fall through to the SwiftUI controls underneath.
//

import AppKit
import SwiftUI

private struct RightClickCatcher: NSViewRepresentable {
	let onRightClick: () -> Void

	func makeNSView(context _: Context) -> CatcherView {
		let view = CatcherView()
		view.onRightClick = onRightClick
		return view
	}

	func updateNSView(_ view: CatcherView, context _: Context) {
		view.onRightClick = onRightClick
	}

	final class CatcherView: NSView {
		var onRightClick: (() -> Void)?

		override func rightMouseDown(with _: NSEvent) {
			onRightClick?()
		}

		override func hitTest(_ point: NSPoint) -> NSView? {
			guard let event = NSApp.currentEvent else { return nil }
			switch event.type {
			case .rightMouseDown, .rightMouseUp:
				return super.hitTest(point)
			default:
				return nil
			}
		}
	}
}

extension View {
	/// Run `action` on right-click; left clicks pass through untouched.
	func onRightClick(perform action: @escaping () -> Void) -> some View {
		overlay(RightClickCatcher(onRightClick: action))
	}
}
