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
		vm.updateViewportWidth(100) // matches the WaveformService test layout (width → 108)
		return vm
	}

	// MARK: - Viewport width (grow now, shrink after the sidebar animation)

	@Test func viewportGrowthAppliesImmediately() {
		let vm = makeViewModel()
		vm.updateViewportWidth(300)
		#expect(vm.waveformWidth == 300)
	}

	@Test func viewportShrinkIsDeferred() {
		let vm = makeViewModel()
		vm.updateViewportWidth(60)
		// Still the old width — the shrink is deferred.
		#expect(vm.waveformWidth == 100)
	}

	@Test func viewportShrinkLandsOnFlush() {
		let vm = makeViewModel()
		vm.updateViewportWidth(60)
		vm.flushPendingShrink() // stands in for the timer firing
		#expect(vm.waveformWidth == 60)
	}

	@Test func successiveShrinksLandAtTheLastWidth() {
		let vm = makeViewModel()
		// The per-frame onChange path during the animation: each change reschedules.
		vm.updateViewportWidth(80)
		vm.updateViewportWidth(60)
		vm.flushPendingShrink()
		#expect(vm.waveformWidth == 60)
	}

	@Test func regrowingCancelsAPendingShrink() {
		let vm = makeViewModel()
		vm.updateViewportWidth(60) // pending shrink…
		vm.updateViewportWidth(100) // …cancelled
		vm.flushPendingShrink()
		#expect(vm.waveformWidth == 100)
	}

	@Test func centerTimeIsPlaybackTimeWhenNotScrolling() {
		let vm = makeViewModel()
		#expect(!vm.isScrolling)
		#expect(vm.centerTime(playbackTime: 10) == 10)
	}

	@Test func scrollOffsetShiftsCenterTime() {
		let vm = makeViewModel()
		vm.onScrollChange(playbackTime: 10)
		#expect(vm.isScrolling)
		// pixelsPerSecond == 100, so a 100 px scroll shifts the center by 1 s.
		vm.currentScrollOffset = 100
		#expect(vm.centerTime(playbackTime: 10) == 9)
		#expect(vm.scrolledTime(playbackTime: 10) == 9)
	}

	@Test func scrubHoldsAnchorWhilePlaybackAdvances() {
		let vm = makeViewModel()
		vm.onScrollChange(playbackTime: 10) // anchor latched at 10
		vm.currentScrollOffset = 100
		// Playback runs on to 12; the viewport stays put (anchor − 1 s), so the
		// audio progresses out of view while the user "holds" the waveform.
		#expect(vm.centerTime(playbackTime: 12) == 9)
		#expect(vm.scrolledTime(playbackTime: 12) == 9)
	}

	@Test func endScrubImmediatelyResetsState() {
		let vm = makeViewModel()
		vm.onScrollChange(playbackTime: 0)
		vm.currentScrollOffset = 42
		vm.endScrubImmediately()
		#expect(vm.currentScrollOffset == 0)
		#expect(!vm.isScrolling)
	}

	@Test func snapBackWithNoOffsetEndsScrubbingImmediately() {
		let vm = makeViewModel()
		vm.onScrollChange(playbackTime: 5)
		vm.currentScrollOffset = 0
		vm.animateSnapBack(playbackTime: 5) // guard branch: nothing to animate
		#expect(!vm.isScrolling)
	}

	@Test func snapBackRebasesTheFrozenAnchorOntoLivePlayback() {
		let vm = makeViewModel()
		vm.onScrollChange(playbackTime: 10)
		vm.currentScrollOffset = 100 // center = 9
		// Released at playback 12: the center must not jump (still 9), expressed as
		// an offset from the live playhead so the decay converges onto playback.
		vm.animateSnapBack(playbackTime: 12)
		#expect(vm.currentScrollOffset == 300)
		#expect(vm.centerTime(playbackTime: 12) == 9)
	}

	// MARK: - Overview (minimap) scrub

	@Test func overviewDragScrubsTheViewportForward() {
		let vm = makeViewModel()
		// 100 s song on a 200 pt strip: dragging the box 20 pt right moves the
		// viewport 10 s forward — a scrub (anchor latched), never a seek.
		vm.overviewScrub(byStripDelta: 20, stripWidth: 200, duration: 100, playbackTime: 10)
		#expect(vm.isScrolling)
		#expect(vm.centerTime(playbackTime: 10) == 20)
	}

	@Test func overviewDragAccumulatesAcrossDeltas() {
		let vm = makeViewModel()
		vm.overviewScrub(byStripDelta: 10, stripWidth: 200, duration: 100, playbackTime: 10)
		vm.overviewScrub(byStripDelta: -30, stripWidth: 200, duration: 100, playbackTime: 11)
		// Anchor stays latched at the first call's playback time (10): +5 s − 15 s.
		#expect(vm.centerTime(playbackTime: 11) == 0)
	}

	@Test func overviewDragWithZeroGeometryIsANoOp() {
		let vm = makeViewModel()
		vm.overviewScrub(byStripDelta: 20, stripWidth: 0, duration: 100, playbackTime: 10)
		vm.overviewScrub(byStripDelta: 20, stripWidth: 200, duration: 0, playbackTime: 10)
		#expect(!vm.isScrolling)
		#expect(vm.currentScrollOffset == 0)
	}

	@Test func overviewSamplesDelegateToTheService() {
		let vm = makeViewModel()
		// Nothing analyzed yet → empty regardless of the requested width.
		#expect(vm.overviewSamples(targetCount: 100) == [])
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
