//
//  WaveformViewModelTests.swift
//  loopedTests
//
//  Automates the scrubbing-state rows of TESTING.md at the view-model layer: the
//  scroll-offset → center-time shift, the scrub end/immediate-snap state, and that
//  the window delegates to the (real, pure) WaveformService. The eased snap-back
//  animation is Timer-driven (needs a live run loop) so only its terminal state is
//  asserted here; the *feel* of the ease stays a manual check.
//
//  The test methods are `async` on purpose: deinitialising a @MainActor object at
//  the end of a *synchronous* main-actor test trips a Swift-runtime dealloc crash
//  under this toolchain, so every test that builds a view-model must be async.
//

@testable import looped
import XCTest

@MainActor
final class WaveformViewModelTests: XCTestCase {
	private func makeViewModel() -> WaveformViewModel {
		let vm = WaveformViewModel(service: DefaultWaveformService())
		vm.waveformWidth = 100 // matches the WaveformService test layout (width → 108)
		return vm
	}

	func testCenterTimeIsPlaybackTimeWhenNotScrolling() {
		let vm = makeViewModel()
		XCTAssertFalse(vm.isScrolling)
		XCTAssertEqual(vm.centerTime(playbackTime: 10), 10, accuracy: 1e-9)
	}

	func testScrollOffsetShiftsCenterTime() {
		let vm = makeViewModel()
		vm.onScrollChange()
		XCTAssertTrue(vm.isScrolling)
		// pixelsPerSecond == 100, so a 100 px scroll shifts the center by 1 s.
		vm.currentScrollOffset = 100
		XCTAssertEqual(vm.centerTime(playbackTime: 10), 9, accuracy: 1e-9)
		XCTAssertEqual(vm.scrolledTime(playbackTime: 10), 9, accuracy: 1e-9)
	}

	func testEndScrubImmediatelyResetsState() {
		let vm = makeViewModel()
		vm.onScrollChange()
		vm.currentScrollOffset = 42
		vm.endScrubImmediately()
		XCTAssertEqual(vm.currentScrollOffset, 0)
		XCTAssertFalse(vm.isScrolling)
	}

	func testSnapBackWithNoOffsetEndsScrubbingImmediately() {
		let vm = makeViewModel()
		vm.onScrollChange()
		vm.currentScrollOffset = 0
		vm.animateSnapBack() // guard branch: nothing to animate
		XCTAssertFalse(vm.isScrolling)
	}

	func testWindowDelegatesToTheService() {
		let vm = makeViewModel()
		// No samples analyzed yet → silence window, but the geometry is the service's.
		let win = vm.window(playbackTime: 1.0)
		XCTAssertEqual(win.width, 108, accuracy: 1e-6)
		XCTAssertEqual(win.chunkStartSample, 88, accuracy: 1e-9)
		XCTAssertEqual(win.samples.count, 216)
	}
}
