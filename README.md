# Form

A native iPhone prototype for selecting an object, measuring captured surfaces with LiDAR, and displaying floating dimensions in AR. iOS 17+, SwiftUI, ARKit, SceneKit and Vision. No third-party dependencies or backend.

## Run

Open `Form.xcodeproj`, select the Form scheme, choose your signing team under Signing & Capabilities, and run on a LiDAR-equipped iPhone. Grant camera access. The simulator and unsupported devices offer a clearly labeled demo. Launch with `--demo` to open that demo directly.

1. Keep an opaque, stationary object fully visible, approximately 0.2–3 m away.
2. Move the phone slowly until tracking initializes, then tap the object’s center.
3. Choose **Add angle**, move around the object, and tap the same object again.
4. Use **Adjust** to align horizontal box axes or edit dimensions. Rotation refits the captured points; edit lengths afterward.
5. Toggle cm/in, save a named result, or share a text summary from the library.

## What is implemented

- On-device foreground instance segmentation using `VNGenerateForegroundInstanceMaskRequest`.
- Tap coordinates converted from the portrait viewport to the original sensor image.
- Same-frame RGB, LiDAR depth, confidence, camera intrinsics and world pose.
- Mask erosion and depth-confidence filtering; 3D back-projection into AR world coordinates.
- Multi-view point accumulation with spatial overlap checks and a bounded point count.
- A gravity-aligned bounding box, fixed horizontal axes across views, trimmed outliers, manual axis alignment and dimension edits.
- World-positioned box edges and camera-facing W/H/D labels.
- JSON persistence, unit conversion, sharing, camera-permission handling and interruption recovery.
- A separate demo scene; saved demo results remain labeled as example data.

## Current limits

This is an initial prototype, not a validated precision measuring instrument. Dimensions bound visible, segmented surfaces; unseen surfaces can be underestimated. Camera-facing horizontal axes can overestimate dimensions until aligned in Adjust. Trimming and mask erosion can slightly shrink results. View count is not an accuracy score or a guarantee of complete coverage.

Apple’s foreground model does not isolate every object. Glass, mirrors, thin objects, touching subjects and clutter can fail. Keep the object still between scans. Overlap checks reduce accidental fusion but are not robust object identity tracking. Scanning uses deliberate taps per angle, rather than continuous automatic segmentation. Resuming after the app goes into the background resets the live scan to avoid mixing coordinate systems; saved measurements remain available.

The simulator verifies UI, math and storage only. Real-device accuracy, segmentation quality, depth alignment and label stability need testing against known-size objects. No accuracy claim is established yet.

## Development

`project.yml` is the source of the Xcode project. Regenerate with `xcodegen generate` after changing targets or build settings.

```sh
xcodebuild -project Form.xcodeproj -scheme Form \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

Unit tests cover rotated/translated object dimensions, invalid input, depth outliers, units and persistence. UI tests cover the labeled demo, unit toggle, saving, library, reset and guide.

## Device validation checklist

- Scan a known-size box from front, side and above. Compare all three dimensions to a tape measure and record error; align the box axes first.
- Try each screen corner to verify tap-to-mask mapping and edge alignment.
- Confirm labels stay attached while walking around the stationary object.
- Confirm selecting another object during Add angle is rejected.
- Try camera denial, returning from Settings, background/foreground, low texture, fast movement and no foreground subject.
- Repeat with a large object, small object, clutter and reflective material. Document failure rates before expanding the supported-object claim.

All camera analysis stays on device. Saved measurements live in the app’s Documents directory.
