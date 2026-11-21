// Minimal repro: a virtual-display platform view that is resized while it is
// covered by another route replays all its queued frames, oldest first,
// when the route is popped (ImageReaderSurfaceProducer keeps one ImageReader
// per size and dequeues from the oldest).
//
// The native view (android/.../CounterView.kt) is a SurfaceView drawing an
// ever-increasing frame number and its own size. On screen the number must
// only go up. After "Run repro" and Back, it visibly jumps back and the size
// flips between old values for a while: those are stale frames.
//
// The same app also shows the second issue: leave the app and come back
// many times (see README.md); now and then the counter stops changing on
// screen although the view keeps drawing, until the view is resized.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const ReproApp());

class ReproApp extends StatelessWidget {
  const ReproApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'VD stale frames repro',
        theme: ThemeData(useMaterial3: true),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Logical pixels taken off the platform view's height.
  final ValueNotifier<double> _shrink = ValueNotifier(0);

  @override
  void dispose() {
    _shrink.dispose();
    super.dispose();
  }

  void _cover({required bool auto}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CoverPage(shrink: _shrink, auto: auto),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('VD stale frames repro')),
        body: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => ValueListenableBuilder<double>(
                  valueListenable: _shrink,
                  builder: (_, shrink, child) => Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: box.maxWidth,
                      height: box.maxHeight - shrink,
                      child: child,
                    ),
                  ),
                  // A plain AndroidView: Flutter hosts a SurfaceView in a
                  // virtual display (logcat: "flutter-vd#N").
                  child: const AndroidView(
                    viewType: 'repro/counter',
                    creationParamsCodec: StandardMessageCodec(),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () => _cover(auto: true),
                    child: const Text('Run repro'),
                  ),
                  OutlinedButton(
                    onPressed: () => _cover(auto: false),
                    child: const Text('Cover (manual)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// An opaque route over the platform view. While it is shown, the view
/// below is still laid out but not painted, so nothing drains its frames.
class CoverPage extends StatefulWidget {
  const CoverPage({super.key, required this.shrink, required this.auto});

  final ValueNotifier<double> shrink;
  final bool auto;

  @override
  State<CoverPage> createState() => _CoverPageState();
}

class _CoverPageState extends State<CoverPage> {
  static const _steps = 40;
  int _resizes = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    if (widget.auto) {
      // Start once the push transition has finished and the view below is
      // really covered.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await _resizeMany();
      });
    }
  }

  /// One size change of the hidden view: each one makes the engine create a
  /// new ImageReader for it (FlutterRenderer.ImageReaderSurfaceProducer
  /// .setSize -> createNewReader).
  void _resizeOnce() {
    _resizes++;
    widget.shrink.value = (_resizes % 5) * 24.0;
    setState(() {});
  }

  Future<void> _resizeMany() async {
    if (_running) return;
    setState(() => _running = true);
    for (var i = 0; i < _steps && mounted; i++) {
      _resizeOnce();
      // Let the view render a few frames at this size.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Covering the platform view')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hidden view resized $_resizes times',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                _running
                    ? 'Resizing…'
                    : 'Now press Back and watch the frame number: it should '
                        'only go up. Instead it jumps back and the size flips '
                        'for a while (stale frames from every old size).',
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: _running ? null : _resizeOnce,
                    child: const Text('Resize hidden view once'),
                  ),
                  OutlinedButton(
                    onPressed: _running ? null : _resizeMany,
                    child: const Text('Resize $_steps times'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
