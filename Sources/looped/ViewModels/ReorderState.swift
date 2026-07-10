//
//  ReorderState.swift
//  looped
//
//  Observable drag state for the track list: row reordering + the external
//  drop gap. The view stays declarative; the gap decisions are testable here
//  (the pure boundary math lives in RowInsertion).
//

import Foundation

@MainActor
final class ReorderState: ObservableObject {
	@Published private(set) var draggedIndex: Int?
	@Published private(set) var dragTranslation: CGFloat = 0
	/// Insertion gap while an external file drag hovers the list.
	@Published var externalGapIndex: Int?

	var isDragging: Bool {
		draggedIndex != nil
	}

	/// Drives the track list's drop-hint fade.
	var isExternalDragHovering: Bool {
		externalGapIndex != nil
	}

	func dragChanged(index: Int, translation: CGFloat) {
		if draggedIndex == nil { draggedIndex = index }
		dragTranslation = translation
	}

	/// Ends the drag; returns the move to commit, or nil for a no-op gap.
	func dragEnded(translation: CGFloat, rowHeight: CGFloat, count: Int) -> (from: Int, toGap: Int)? {
		defer {
			draggedIndex = nil
			dragTranslation = 0
		}
		guard let from = draggedIndex,
		      let gap = commitGap(from: from, translation: translation, rowHeight: rowHeight, count: count)
		else { return nil }
		return (from, gap)
	}

	/// The gap to draw the insertion indicator at (external drag wins), or nil.
	func activeGapIndex(rowHeight: CGFloat, count: Int) -> Int? {
		if let externalGapIndex { return externalGapIndex }
		guard let from = draggedIndex else { return nil }
		return commitGap(from: from, translation: dragTranslation, rowHeight: rowHeight, count: count)
	}

	/// `from` and `from + 1` are the row's own slots — moving there is a no-op.
	private func commitGap(from: Int, translation: CGFloat, rowHeight: CGFloat, count: Int) -> Int? {
		let gap = RowInsertion.dragGapIndex(
			from: from, translation: translation, rowHeight: rowHeight, count: count
		)
		return (gap == from || gap == from + 1) ? nil : gap
	}
}
