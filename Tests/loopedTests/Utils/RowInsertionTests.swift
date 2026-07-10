//
//  RowInsertionTests.swift
//  loopedTests
//
//  Gap-index math for the sidebar's hand-rolled reordering + drop insertion.
//

import Foundation
@testable import looped
import Testing

struct RowInsertionTests {
	private let h: CGFloat = 28

	// MARK: - gapIndex (external drops)

	@Test func gapIndexPicksTheNearestRowBoundary() {
		#expect(RowInsertion.gapIndex(y: 0, rowHeight: h, count: 5) == 0)
		#expect(RowInsertion.gapIndex(y: 13, rowHeight: h, count: 5) == 0)
		#expect(RowInsertion.gapIndex(y: 15, rowHeight: h, count: 5) == 1)
		#expect(RowInsertion.gapIndex(y: h * 2, rowHeight: h, count: 5) == 2)
	}

	@Test func gapIndexClampsToTheListBounds() {
		#expect(RowInsertion.gapIndex(y: -50, rowHeight: h, count: 5) == 0)
		#expect(RowInsertion.gapIndex(y: 1000, rowHeight: h, count: 5) == 5)
		#expect(RowInsertion.gapIndex(y: 10, rowHeight: h, count: 0) == 0)
		#expect(RowInsertion.gapIndex(y: 10, rowHeight: 0, count: 5) == 0)
	}

	// MARK: - dragGapIndex (internal reorder)

	@Test func undisturbedDragPointsAtTheRowsOwnSlot() {
		// Gap `from` and `from + 1` are both no-ops; a centered row sits
		// exactly between them.
		let gap = RowInsertion.dragGapIndex(from: 2, translation: 0, rowHeight: h, count: 5)
		#expect(gap == 2 || gap == 3)
	}

	@Test func dragDisplacesANeighborOnlyPastItsCenter() {
		// A neighbor's center sits one full row height from the dragged row's.
		// Down: just short of it → still a no-op gap.
		#expect(RowInsertion.dragGapIndex(from: 2, translation: h - 1, rowHeight: h, count: 5) == 3)
		// Down: past it → below the neighbor.
		#expect(RowInsertion.dragGapIndex(from: 2, translation: h + 1, rowHeight: h, count: 5) == 4)
		// Up: past it → above the neighbor.
		#expect(RowInsertion.dragGapIndex(from: 2, translation: -(h + 1), rowHeight: h, count: 5) == 1)
	}

	@Test func dragGapClampsAtTheListEnds() {
		#expect(RowInsertion.dragGapIndex(from: 0, translation: -500, rowHeight: h, count: 5) == 0)
		#expect(RowInsertion.dragGapIndex(from: 4, translation: 500, rowHeight: h, count: 5) == 5)
	}
}
