//
//  TimeFormatter.swift
//  looped
//
//  Presentation helper for formatting playback times as m:ss.
//

import Foundation

enum TimeFormatter {
	/// Formats a time interval as `m:ss` (e.g. 2:05); returns "0:00" for nil.
	static func mmss(_ time: TimeInterval?) -> String {
		let formatter = DateComponentsFormatter()
		formatter.allowedUnits = [.minute, .second]
		formatter.zeroFormattingBehavior = [.pad]
		if let time {
			return formatter.string(from: time) ?? "0:00"
		}
		return "0:00"
	}
}
