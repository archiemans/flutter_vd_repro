# vd_stale_frames_repro

Minimal Android repro for two problems with platform views hosted in a
virtual display (a plain `AndroidView` whose native view is a `SurfaceView`).
It has no plugins and no dependencies beyond Flutter.

The native view (`android/app/src/main/kotlin/.../CounterView.kt`) draws
about 60 frames a second:
- a frame number that only ever goes up;
- its own surface size;
- a background colour that changes every frame.

Tested on a moto g stylus 5G (2024), Android 15 (API 35), Impeller (Vulkan):
- Flutter 3.41.9 (stable, engine 42d3d75a56): both problems reproduce.
- Flutter 3.50.1 (stable, engine 4d35714800): both problems still reproduce.
  The Android build files were updated to the 3.50.1 template (Gradle 9.5.0,
  AGP 9.3.1, Kotlin 2.4.20); the Dart and Kotlin code is unchanged.

```
flutter run --release
```

### Note: HCPP hides both problems

Both problems need the view to be in a virtual display (logcat:
`flutter-vd#0`). On 3.50.1, Hybrid Composition++ is on by default on the
master and beta channels but **off on stable** (`enable-hcpp` in
`packages/flutter_tools/lib/src/features.dart`). With HCPP the `SurfaceView`
is not put in a virtual display, and neither problem shows:

```
FLUTTER_ENABLE_HCPP=true flutter build apk --release
```

(the manifest then has `io.flutter.embedding.android.EnableHcpp=true`). So
test on the **stable** channel, or with `--no-enable-hcpp`, to see the bugs.

## 1. Stale frames replayed after the view was covered

1. Tap **Run repro**. An opaque route covers the platform view, and the page
   below shrinks the view 40 times, 150 ms apart. The view is still laid out
   while covered, so each size change reaches the engine.
2. When it says so, tap **Back**.

**Expected:** the view shows its current frame; the frame number keeps going
up.

**Actual:** for a while the view replays old frames:
- the frame number jumps back to earlier values;
- the size text and the drawn area flip between the sizes it had while
  covered.

**Why:** `FlutterRenderer.ImageReaderSurfaceProducer.setSize()` creates a new
`ImageReader` for every size. `dequeueImage()` takes images from the
**oldest** reader first, one per frame, and drops a reader only when it is
empty. A covered view is not painted, so nothing is dequeued and the readers
pile up; they all play back when it is painted again.

**Cover (manual)** does the same step by step: **Resize hidden view once**
adds one reader, and **Back** shows the playback. A single resize gives a
barely visible blip; 40 give seconds.

## 2. View freezes after the app is resumed

Leave the app and come back, many times. Now and then the frame number stops
changing on screen. The native view keeps drawing and the Flutter UI still
responds, but the view shows its last frame until it is resized: rotate the
phone, or open and close the cover route after a resize.

At the same time logcat shows, about 90 times a second:

```
BufferQueueProducer: [ImageReader-WxH...] dequeueBuffer: BufferQueue has no connected producer
SurfaceFlinger: dequeueBuffer failed for display [flutter-vd#N] error -19
```

On every resume `PlatformViewsController.onResume()` calls
`VirtualDisplayController.resetSurface()`, which releases the virtual display
and creates a new one on the same surface. Sometimes the new display is left
without a connected producer.

A loop that leaves and returns 30 times. It opens Android Settings, then
brings the app back:

```bash
ADB=adb
PKG=dev.repro.vd_stale_frames_repro
adb logcat -c
for i in $(seq 1 30); do
  $ADB shell am start -a android.settings.SETTINGS > /dev/null
  sleep 5
  $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 > /dev/null
  sleep 3
  echo "run $i: $($ADB logcat -d | grep -c 'no connected producer') 'no connected producer' lines so far"
done
```

When the count jumps by about 90 per second while the app is in front, look
at the screen: the frame number is frozen. With this sample it happened on
cycle 24 of 30 (539 lines over about 6 s) on 3.41.9, and on cycles 24–25 of 30
(566 lines) on 3.50.1. With HCPP enabled: 0 of 30.
