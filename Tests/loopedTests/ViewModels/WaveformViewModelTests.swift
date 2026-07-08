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

@testable import looped
import Testing

@MainActor
struct WaveformViewModelTests {
	private func makeViewModel() -> WaveformViewModel {
		let vm = WaveformViewModel(service: DefaultWaveformService())
		vm.waveformWidth = 100 // matches the WaveformService test layout (width → 108)
		return vm
	}

	@Test func centerTimeIsPlaybackTimeWhenNotScrolling() {
		let vm = makeViewModel()
		#expect(!vm.isScrolling)
		#expect(vm.centerTime(playbackTime: 10) == 10)
	}

	@Test func scrollOffsetShiftsCenterTime() {
		let vm = makeViewModel()
		vm.onScrollChange()
		#expect(vm.isScrolling)
		// pixelsPerSecond == 100, so a 100 px scroll shifts the center by 1 s.
		vm.currentScrollOffset = 100
		#expect(vm.centerTime(playbackTime: 10) == 9)
		#expect(vm.scrolledTime(playbackTime: 10) == 9)
	}

	@Test func endScrubImmediatelyResetsState() {
		let vm = makeViewModel()
		vm.onScrollChange()
		vm.currentScrollOffset = 42
		vm.endScrubImmediately()
		#expect(vm.currentScrollOffset == 0)
		#expect(!vm.isScrolling)
	}

	@Test func snapBackWithNoOffsetEndsScrubbingImmediately() {
		let vm = makeViewModel()
		vm.onScrollChange()
		vm.currentScrollOffset = 0
		vm.animateSnapBack() // guard branch: nothing to animate
		#expect(!vm.isScrolling)
	}

	@Test func windowDelegatesToTheService() {
		let vm = makeViewModel()
		// No samples analyzed yet → silence window, but the geometry is the service's.
		let win = vm.window(playbackTime: 1.0)
		#expect(win.width == 108)
		#expect(win.chunkStartSample == 88)
		#expect(win.samples.count == 216)
	}
}
