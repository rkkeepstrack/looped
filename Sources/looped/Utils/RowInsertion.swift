//
//  RowInsertion.swift
//  looped
//
//  Pure index math for the sidebar's hand-rolled row reordering and external
//  drop insertion (the native List's drag visuals aren't themeable — see
//  Sidebar in ContentView). Gap indices count the spaces between rows:
//  0 = above the first row, count = below the last row — the same convention
//  Array.move(fromOffsets:toOffset:) uses for its target offset.
//

import Foundation

enum RowInsertion {
	/// The gap index nearest to a cursor at `y` in a uniform-row-height list
	/// (row n spans [n·h, (n+1)·h)), clamped to `0...count`.
	static func gapIndex(y: CGFloat, rowHeight: CGFloat, count: Int) -> Int {
		guard rowHeight > 0, count > 0 else { return 0 }
		return min(max(Int((y / rowHeight).rounded()), 0), count)
	}

	/// The gap a row dragged from index `from` by `translation` points at —
	/// decided by the dragged row's visual center, so a neighbor is displaced
	/// only once the center crosses it. `from` and `from + 1` are the no-op
	/// gaps (the row's own slot).
	static func dragGapIndex(from: Int, translation: CGFloat, rowHeight: CGFloat, count: Int) -> Int {
		let center = (CGFloat(from) + 0.5) * rowHeight + translation
		return gapIndex(y: center, rowHeight: rowHeight, count: count)
	}
}
