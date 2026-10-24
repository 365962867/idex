# Performance validation

Measured on October 24, 2026, using Xcode 27.1 and the iPhone Duo iOS 27.1 simulator on an Apple M1 Max. The app uses its existing optimized Debug build. These are focused workloads, not whole-app launch or frame-rate measurements.

| Workload | Previous path | Optimized path | Result |
| --- | ---: | ---: | --- |
| 1,200 English/Chinese catalog searches | 952 ms | 664–717 ms | About 25–30% less time |
| Five 951×669 shell renders | 56.2 ms | 11.0 ms | About 5× faster |
| Five synthetic 6000×4000 JPEG preparations | 198 ms | 247 ms | Total time increased; preparation now runs off the main actor |

The shell's PNG output matched the previous drawing path byte for byte. Drawing its texture now submits two filled paths instead of 39,984 individual dot fills at the expanded size. Grid dots and LCD scan lines are batched too. Catalog search retains the same matching rules and ordering; regression tests cover all species names and numbers, partial matches, and localized type queries in both languages.

Photo preparation uses ImageIO thumbnail decoding with EXIF rotation/mirroring, white alpha composition, an approximately 4.2-megapixel thumbnail budget, and a final square no larger than 1200px. The area budget preserves center detail in panoramas better than limiting only the long edge. Encoded source data and any internal decoder allocations are additional memory; peak process memory has not been measured. Completed scans release the photo once its sprite result is displayed, and foregrounding a completed result keeps the camera stopped.

## Scan button responsiveness

A follow-up investigation reproduced both the `AVAudioSession Hang Risk` warning and `unsafeForcedSync called from Swift Concurrent context` using silent native audio. Despite explicit asynchronous session activation, the previous main-actor path still called player preparation and speech APIs that can implicitly contact audio services. Player construction/preparation/play took 211 ms on the main actor, followed by 117 ms of speech construction/voice selection/startup in the same simulator run. These are observed startup delays, not a measurement of the user's physical device.

`AudioPlaybackWorker` now owns all native audio and speech objects on a serial GCD queue. Session configuration and asynchronous activation/deactivation, PCM generation, player preparation/play/stop, voice lookup, and synthesizer creation/speak/stop run there, outside Swift's cooperative executor. Players and voices are cached. Speech is initialized only when needed, and request tokens cancel pending playback before and after expensive preparation. The main actor retains UI state and haptics.

The scanner also imposed a minimum 1.1-second wait regardless of prediction speed. That wait is removed. The sweep accompanies actual inference and the result is published immediately when it finishes. The full sample scan measured 229 ms for the first request on a new classifier and 26.5–29.7 ms for subsequent requests, with audio disabled. This measures the simulator's bundled sample path, not physical camera latency or a change in model accuracy.

`AudioPlaybackTests` exercises native player and speech startup at zero volume. After the change, startup completed on the audio queue while the main actor ticked 13 times at a requested 5ms interval; its maximum observed gap was 6.1 ms. Neither the main-thread audio-session warning nor `unsafeForcedSync` appeared in the focused or full unit runs. These are focused simulator observations, not a guarantee that all system audio messages disappear on every device.

`PerformanceBenchmarks` prints first and subsequent full-scan timings. UI automation keeps application sound disabled; the separate zero-volume native audio tests cover startup, stop, cancellation, player reuse, and lazy speech initialization without producing audible output.

Instruments Points of Interest intervals distinguish `Scan`, `Recognition`, `Model Load`, `Audio Player Preparation`, and `Audio Speech Startup`. Use these to diagnose physical-device latency without assuming that every console message is a cause.

Camera output prefers available 8-bit bi-planar YUV formats, with BGRA as a fallback. Core Image converts the retained frame when scanning. This follows [Apple's pixel-format guidance](https://developer.apple.com/documentation/technotes/tn3121-selecting-a-pixel-format-for-an-avcapturevideodataoutput), which explains the conversion cost of requesting BGRA for a native YUV stream. Simulator tests cover YUV rendering and tap-time frame retention. Live camera energy, frame latency, peak memory, and physical hinge behavior still need device measurement.

## Reproduce

Run the focused performance workloads:

```sh
xcodebuild test -project iDex.xcodeproj -scheme iDex \
  -destination 'platform=iOS Simulator,name=iPhone Duo' \
  -parallel-testing-enabled NO \
  -only-testing:iDexTests/PerformanceBenchmarks
```

`PerformanceBenchmarks` prints elapsed times and attaches both shell renders. Its reference paths preserve the pre-optimization image preparation and shell drawing code. Timing has no fixed pass/fail threshold because host load and device hardware vary. The shell comparison does assert identical images.

Run the complete suite with the README's standard `xcodebuild test` command. It also checks all eight photo orientations, transparency, unreadable/cancelled imports, high-resolution and panoramic photos, completed-scan photo release, real model inference and blank-image abstention, bilingual search, and cover/expanded layouts. UI tests keep audio muted.
