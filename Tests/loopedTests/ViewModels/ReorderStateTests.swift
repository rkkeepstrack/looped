//
//  ReorderStateTests.swift
//  loopedTests
//
//  Drag state for the track list: gap decisions, no-op slots, reset on end.
//

import Foundation
@testable import looped
import Testing

@MainActor
struct ReorderStateTests {
	private let h: CGFloat = 28

	@Test func dragChangedLatchesTheFirstIndexAndTracksTranslation() {
		let state = ReorderState()

		state.dragChanged(index: 2, translation: 10)
		state.dragChanged(index: 3, translation: 20) // index latched, not re-read

		#expect(state.draggedIndex == 2)
		#expect(state.dragTranslation == 20)
		#expect(state.isDragging)
	}

	@Test func dragEndedReturnsTheMoveAndResets() {
		let state = ReorderState()
		state.dragChanged(index: 0, translation: 0)

		let move = state.dragEnded(translation: h + 1, rowHeight: h, count: 5)

		#expect(move?.from == 0)
		#expect(move?.toGap == 2)
		#expect(!state.isDragging)
		#expect(state.dragTranslation == 0)
	}

	@Test func dragEndedInTheRowsOwnSlotIsANoOp() {
		let state = ReorderState()
		state.dragChanged(index: 2, translation: 0)

		#expect(state.dragEnded(translation: 3, rowHeight: h, count: 5) == nil)
		#expect(!state.isDragging)
	}

	@Test func activeGapPrefersTheExternalDrag() {
		let state = ReorderState()
		state.externalGapIndex = 4

		#expect(state.activeGapIndex(rowHeight: h, count: 5) == 4)
	}

	@Test func activeGapHidesTheNoOpSlotsWhileDragging() {
		let state = ReorderState()
		state.dragChanged(index: 2, translation: 3)

		#expect(state.activeGapIndex(rowHeight: h, count: 5) == nil)

		state.dragChanged(index: 2, translation: h + 1)
		#expect(state.activeGapIndex(rowHeight: h, count: 5) == 4)
	}

	@Test func externalDragHoveringTracksTheExternalGap() {
		let state = ReorderState()
		#expect(!state.isExternalDragHovering)

		state.externalGapIndex = 0
		#expect(state.isExternalDragHovering)

		state.externalGapIndex = nil // drop or drag-exit
		#expect(!state.isExternalDragHovering)
	}

	@Test func activeGapIsNilWhenIdle() {
		#expect(ReorderState().activeGapIndex(rowHeight: h, count: 5) == nil)
	}
}
