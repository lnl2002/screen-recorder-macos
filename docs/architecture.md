# Architecture

This is an independent native implementation informed by a bounded static inspection of an installed Screen Studio 4.1.0-5005. No proprietary code, binaries, icons, or private recording data are included. Behavioral equivalence is not claimed.

## Pipeline

`SCStream → AVAssetWriter + pointer.jsonl → CameraPath → Core Image / Lanczos → AVAssetWriter → MP4`

- `CaptureSink` owns a serial queue for video/audio append, the pointer timer and file writes. The first complete screen frame establishes the media epoch. Mouse samples use the Core Media host clock relative to that epoch. Screen frame PTS are preserved; audio before the epoch is omitted. A final frame extends static content through stop time.
- `CaptureEngine` captures a display, excluding this process's application windows. Coordinates come from `CGDisplayBounds`, so the pointer and display use Quartz global coordinates, including negative origins. Capture pixel size can differ from desktop point size; normalized pointer coordinates bridge them.
- `CameraPath` is immutable and precomputed at 120 Hz. It interpolates uneven pointer samples, filters forward/backward within valid segments, and aims at an upcoming click during its lead-in. Auto mode merges click windows. Pan is represented as a position inside the crop’s legal travel range; pan and scale have independent critically damped springs. Zoom-out naturally returns to overview without resetting pan velocity at a moving crop boundary.
- `VideoExporter` decodes original-resolution BGRA samples with `AVAssetReaderTrackOutput`. For every timestamp n/60, it selects the latest source frame, applies the camera crop in original pixels, resamples once with Lanczos, and appends a pixel buffer to `AVAssetWriter`. No lower-resolution intermediate is created before zoom. Audio has an independent bounded producer feeding AAC to the same writer; blocking it behind video can deadlock a muxer. Reader/writer failure, cancellation and a 30-second encoder stall are reported. Preview is not part of this version.
- Output choices are source resolution, 1080p and 720p, without upscaling the overall source dimensions. H.264 High profile uses a target bitrate based on output pixels (8–100 Mbps). Target bitrate is not a guaranteed file bitrate or a substitute for source detail.
- The app saves settings per export and retains the source for repeated export. Cancellation does not remove the source. Quit is blocked during capture/finalization/export so normal UI quit cannot discard an active writer.

The app currently records a baked-in cursor. Custom pointer smoothing needs separate cursor images/hotspots and event anchors; adding it without that metadata would desynchronize clicks and hover highlights.

## Evidence boundary

REA examined selected bundled JavaScript, with parent evidence IDs:

- `ev_17b25fb2424d4752c619140e5fdd4b2a585cd9d3e56ec547c2091a999f86ee65`
- `ev_3e0bd331994b7d914392ea263652ae8a95bbf82e18cdf818f195498b001082a6`

These are references to the original investigation session, not embedded full evidence bundles. Its application graph was partial, the second analysis hit semantic limits, and several unpacked files differed from declared ASAR integrity metadata. Analysis explicitly retained them as untrusted. Main-process bytecode and complete runtime call flow were not recovered.

Observed static interfaces included separate mouse-event/zoom configuration and timed spring simulation. Supplemental native symbol inspection found ScreenCaptureKit and AVAssetWriter imports. Embedded text described rendered-frame export and pointer/hover synchronization. None establishes exact runtime behavior or the original auto-zoom algorithm. All camera thresholds and implementation choices in this repository are our own.

## Primary API references

- [Apple ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [SCStreamConfiguration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration)
- [AVFoundation media reading and writing](https://developer.apple.com/documentation/avfoundation/media-reading-and-writing)
