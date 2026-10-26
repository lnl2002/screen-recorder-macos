# Real capture acceptance

Automated camera and media tests do not replace these checks. Run from the packaged `.app`, which has a stable bundle identifier for macOS permissions.

- [ ] Grant Screen Recording, refresh screens, record 60 seconds and stop from the menu bar.
- [ ] Play the MP4 end to end. Inspect `manifest.json` for dropped video/audio buffers.
- [ ] Enable system audio and record a visible timer with a sound marker. Measure start/end A/V drift.
- [ ] Click near all four screen corners, move quickly, pause, then click repeatedly. Verify camera stays within the image and returns to the overview in Auto.
- [ ] Verify click and visible-pointer timing; the 120 Hz polling path may miss extremely short clicks.
- [ ] Test a Retina monitor and an external monitor to the left/above the main screen. Confirm pointer focus and pixel scaling.
- [ ] Re-export with Follow, Full screen and two zoom scales. Original files must remain unchanged.
- [ ] Cancel an export, reopen the session, export again.
- [ ] Deny/revoke capture permission; verify errors and recovery after granting it.
- [ ] Test stream interruption, disconnect, low disk space and a static desktop through Stop.
- [ ] Verify UI quit while recording does not terminate the active writer.

Initial limits: one display, SDR, no microphone/camera/region capture. Multi-hour recording performance, HDR, window movement and display changes are not validated.

## Validation in the initial development session

On 2026-10-26, Swift 6.1.2 / macOS 26.5:

- Camera test runner: all six tests passed.
- Synthetic media smoke: H.264 MP4, full video decode, four-second duration, audio track preservation, follow-crop coordinates and full-screen re-export passed.
- Release `.app` build, ad hoc signature and plist validation passed.
- Real capture test did **not** pass: ScreenCaptureKit returned an empty display list. An independent minimal ScreenCaptureKit query also returned zero displays. This was not a successful recording test; real capture, device performance and real A/V synchronization remain unverified.
- The packaged process created a window according to the WindowServer inventory, but the UI automation provider could not obtain its accessibility window or screenshot. Visual interaction remains unverified.

To explicitly record a three-second local test after the app has permission and a capturable display is available:

```sh
"dist/Screen Recorder.app/Contents/MacOS/ScreenRecorder" --capture-test
```

This test records the main display (or first capturable display), saves a session under Movies / Screen Recorder, exports Follow mode, and decodes the output. It never uploads the resulting private local recording.
