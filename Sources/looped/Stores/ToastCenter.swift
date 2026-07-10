//
//  ToastCenter.swift
//  looped
//
//  UI-free error-surfacing store: view-models and the coordinator report
//  errors here, ToastView renders the queue. One toast per user action —
//  callers aggregate their messages before reporting. Services stay throwing
//  and never see this type.
//

import Combine
import Foundation

/// One surfaced error card. `messages` is multi-line when a single action
/// produced several failures (e.g. an import skipping three files).
struct Toast: Identifiable, Equatable {
	let id: UUID
	let messages: [String]
}

@MainActor
final class ToastCenter: ObservableObject {
	/// The visible queue, oldest first. New toasts stack; they don't replace.
	@Published private(set) var toasts: [Toast] = []

	private let dismissAfter: Duration

	nonisolated init(dismissAfter: Duration = .seconds(4)) {
		self.dismissAfter = dismissAfter
	}

	func report(_ error: Error) {
		report(errors: [error])
	}

	func report(errors: [Error]) {
		// For LocalizedErrors, localizedDescription routes through errorDescription.
		report(messages: errors.map(\.localizedDescription))
	}

	func report(messages: [String]) {
		guard !messages.isEmpty else { return }
		let toast = Toast(id: UUID(), messages: messages)
		toasts.append(toast)
		Task { [weak self, dismissAfter] in
			try? await Task.sleep(for: dismissAfter)
			self?.dismiss(id: toast.id)
		}
	}

	/// Manual dismiss (click).
	func dismiss(id: UUID) {
		toasts.removeAll { $0.id == id }
	}
}
