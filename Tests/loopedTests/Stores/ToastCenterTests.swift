//
//  ToastCenterTests.swift
//  loopedTests
//
//  Queue/dismiss behavior of the toast store. The look and the exact 4 s
//  timing stay manual QA (TESTING.md); here a short auto-dismiss interval
//  keeps the timer test fast.
//

import Foundation
@testable import looped
import Testing

@MainActor
struct ToastCenterTests {
	@Test func reportQueuesAToastPerCall() {
		let center = ToastCenter()

		center.report(messages: ["first"])
		center.report(messages: ["second"])

		#expect(center.toasts.map(\.messages) == [["first"], ["second"]])
	}

	@Test func emptyReportsAreNoOps() {
		let center = ToastCenter()

		center.report(messages: [])
		center.report(errors: [])

		#expect(center.toasts.isEmpty)
	}

	@Test func reportedErrorsUseTheirLocalizedDescription() {
		let center = ToastCenter()

		center.report(AudioFileServiceError.tooLong(filename: "song.wav", maxMinutes: 20))

		#expect(center.toasts.first?.messages == ["“song.wav” is longer than 20 minutes."])
	}

	@Test func dismissRemovesOnlyThatToast() throws {
		let center = ToastCenter()
		center.report(messages: ["first"])
		center.report(messages: ["second"])

		let first = try #require(center.toasts.first)
		center.dismiss(id: first.id)

		#expect(center.toasts.map(\.messages) == [["second"]])
	}

	@Test func toastsAutoDismissAfterTheInterval() async throws {
		let center = ToastCenter(dismissAfter: .milliseconds(20))
		center.report(messages: ["going"])
		#expect(center.toasts.count == 1)

		// Poll instead of one fixed sleep — timer scheduling isn't exact.
		for _ in 0 ..< 100 where !center.toasts.isEmpty {
			try await Task.sleep(for: .milliseconds(10))
		}

		#expect(center.toasts.isEmpty)
	}
}
