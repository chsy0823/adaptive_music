import 'dart:async';
import 'dart:math' as math;
import 'package:adaptive_music/adaptive_music.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MusicLabApp());

const demoTracks = [
  MusicTrack.asset('assets/audio/daylight.wav', title: 'Daylight'),
  MusicTrack.asset('assets/audio/motion.wav', title: 'Motion'),
  MusicTrack.asset('assets/audio/afterglow.wav', title: 'Afterglow'),
];
const ink = Color(0xFF173B52);
const blue = Color(0xFF2458C7);
const paper = Color(0xFFF1F5F8);
const peach = Color(0xFFFFD3AD);

class MusicLabApp extends StatelessWidget {
  const MusicLabApp({super.key, this.player, this.autoLoad = true});
  final AdaptiveMusicPlayer? player;
  final bool autoLoad;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Adaptive Music Lab',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: blue, surface: paper),
      scaffoldBackgroundColor: paper,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      sliderTheme: const SliderThemeData(trackHeight: 3),
    ),
    home: MusicLab(player: player, autoLoad: autoLoad),
  );
}

class MusicLab extends StatefulWidget {
  const MusicLab({super.key, this.player, required this.autoLoad});
  final AdaptiveMusicPlayer? player;
  final bool autoLoad;
  @override
  State<MusicLab> createState() => _MusicLabState();
}

class _MusicLabState extends State<MusicLab> with WidgetsBindingObserver {
  late final AdaptiveMusicPlayer _player;
  StreamSubscription<MusicState>? _subscription;
  MusicState _state = const MusicState(status: PlaybackStatus.empty);
  List<MusicTrack> _tracks = demoTracks;
  MusicRepeatMode _repeat = MusicRepeatMode.all;
  double _volume = 0.65;
  double _fade = 0.6;
  double _crossfade = 3;
  double _repeatCrossfade = 0.35;
  double _cutoff = 1200;
  bool _smooth = true;
  String _filterType = 'Off';
  double _shelfFrequency = 2000;
  double _shelfGain = -6;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player = widget.player ?? AdaptiveMusicPlayer();
    _subscription = _player.states.listen((state) {
      if (!mounted) return;
      setState(() {
        _state = state;
        if (state.error != null) _error = state.error.toString();
      });
    });
    if (widget.autoLoad) unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _ready) {
      _command(() => _player.pause(transition: Duration.zero));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  bool get _ready =>
      !_busy &&
      ![
        PlaybackStatus.empty,
        PlaybackStatus.loading,
        PlaybackStatus.failed,
        PlaybackStatus.disposed,
      ].contains(_state.status);
  bool get _playing =>
      _state.status == PlaybackStatus.playing ||
      _state.status == PlaybackStatus.pausing;
  Duration get _duration =>
      Duration(milliseconds: _smooth ? (_fade * 1000).round() : 0);
  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _player.load(
        tracks: _tracks,
        repeat: _repeat,
        repeatCrossfadeDuration: Duration(
          milliseconds: (_repeatCrossfade * 1000).round(),
        ),
        transition: _crossfade == 0
            ? const TrackTransition.gapless()
            : TrackTransition.crossfade(
                duration: Duration(milliseconds: (_crossfade * 1000).round()),
              ),
      );
      _player.setVolume(_volume, transition: Duration.zero);
      _applyFilter(Duration.zero);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _applyFilter(Duration duration) {
    switch (_filterType) {
      case 'Low-pass':
        _player.setFilter(
          LowPassFilter(cutoffHz: _cutoff),
          transition: duration,
        );
      case 'High-shelf':
        _player.setFilter(
          HighShelfFilter(frequencyHz: _shelfFrequency, gainDb: _shelfGain),
          transition: duration,
        );
      default:
        _player.clearFilter(transition: duration);
    }
  }

  void _command(VoidCallback command) {
    try {
      command();
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _pickTracks() async {
    try {
      final files = await openFiles(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Audio',
            extensions: ['wav', 'mp3', 'ogg', 'flac'],
            uniformTypeIdentifiers: ['public.audio'],
          ),
        ],
      );
      if (!mounted || files.isEmpty) return;
      setState(() {
        _tracks = files
            .map((file) => MusicTrack.file(file.path, title: file.name))
            .toList();
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                Row(
                  children: [
                    const Icon(Icons.graphic_eq, color: blue, size: 34),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Adaptive Music Lab',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ),
                    if (MediaQuery.sizeOf(context).width > 650)
                      const Text(
                        'A listening playground',
                        style: TextStyle(color: ink),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 720) {
                      return Column(
                        children: [
                          _deck(),
                          const SizedBox(height: 24),
                          _mixer(),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: _deck()),
                        const SizedBox(width: 28),
                        Expanded(flex: 5, child: _mixer()),
                      ],
                    );
                  },
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Try this: play → lower the cutoff → pause mid-transition → resume.\nDemo loops are original synthesized audio, included with the project.',
                  style: TextStyle(height: 1.7, color: ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _deck() {
    final index = _state.index.clamp(0, _tracks.length - 1);
    final progress = _state.duration.inMilliseconds == 0
        ? 0.0
        : (_state.position.inMilliseconds / _state.duration.inMilliseconds)
              .clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: blue,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _playing ? peach : Colors.white54,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _busy
                        ? 'Preparing audio…'
                        : _state.overlapping
                        ? 'Mixing two tracks'
                        : _state.status.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                _tracks[index].title ?? 'Track ${index + 1}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${index + 1} of ${_tracks.length} tracks',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 96,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TimelinePainter(progress, _state.overlapping),
                ),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: progress,
                color: peach,
                backgroundColor: Colors.white24,
                minHeight: 3,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _time(_state.position),
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    _time(_state.duration),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: peach,
                      foregroundColor: ink,
                    ),
                    onPressed: _ready
                        ? () => _command(
                            () => _playing
                                ? _player.pause(transition: _duration)
                                : _player.play(transition: _duration),
                          )
                        : null,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                    label: Text(_playing ? 'Pause' : 'Play'),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Restart track',
                    onPressed: _ready
                        ? () => _command(
                            () => _player.play(
                              start: PlaybackStart.restartTrack,
                              transition: _duration,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.replay),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Next track',
                    onPressed: _ready ? () => _command(_player.next) : null,
                    icon: const Icon(Icons.skip_next),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Stop and rewind',
                    onPressed: _ready ? () => _command(_player.stop) : null,
                    icon: const Icon(Icons.stop),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Playlist',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _pickTracks,
              icon: const Icon(Icons.add),
              label: const Text('Open audio'),
            ),
          ],
        ),
        for (var i = 0; i < _tracks.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              i == index ? Icons.graphic_eq : Icons.music_note,
              color: i == index ? blue : ink,
            ),
            title: Text(_tracks[i].title ?? 'Track ${i + 1}'),
            trailing: i == index
                ? const Text('Selected', style: TextStyle(color: blue))
                : null,
            onTap: _ready ? () => _command(() => _player.skipTo(i)) : null,
          ),
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  setState(() => _tracks = demoTracks);
                  unawaited(_load());
                },
          child: const Text('Restore demo playlist'),
        ),
      ],
    );
  }

  Widget _mixer() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Shape the sound',
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Change the feel without restarting the music.',
        style: TextStyle(height: 1.5),
      ),
      const SizedBox(height: 20),
      _slider('Volume', '${(_volume * 100).round()}%', _volume, 0, 1, (v) {
        setState(() => _volume = v);
        _command(() => _player.setVolume(v, transition: _duration));
      }),
      const Divider(height: 30),
      const Text('Tone filter'),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'Off', label: Text('Off')),
          ButtonSegment(value: 'Low-pass', label: Text('Low-pass')),
          ButtonSegment(value: 'High-shelf', label: Text('High-shelf')),
        ],
        selected: {_filterType},
        showSelectedIcon: false,
        onSelectionChanged: (value) {
          setState(() => _filterType = value.single);
          if (_ready) _command(() => _applyFilter(_duration));
        },
      ),
      const SizedBox(height: 12),
      Text(
        _filterType == 'High-shelf'
            ? 'Reduce brightness while keeping the upper frequencies audible.'
            : _filterType == 'Low-pass'
            ? 'Progressively remove frequencies above the cutoff.'
            : 'Original tone. Choose a filter to compare.',
      ),
      if (_filterType == 'Low-pass')
        _slider(
          'Cutoff',
          '${_cutoff.round()} Hz',
          math.log(_cutoff),
          math.log(100),
          math.log(16000),
          (v) {
            setState(() => _cutoff = math.exp(v));
            if (_ready) _command(() => _applyFilter(_duration));
          },
        ),
      if (_filterType == 'High-shelf') ...[
        _slider(
          'Shelf frequency',
          '${_shelfFrequency.round()} Hz',
          math.log(_shelfFrequency),
          math.log(100),
          math.log(8000),
          (v) {
            setState(() => _shelfFrequency = math.exp(v).clamp(100, 8000));
            if (_ready) _command(() => _applyFilter(_duration));
          },
        ),
        _slider(
          'Treble gain',
          '${_shelfGain.toStringAsFixed(1)} dB',
          _shelfGain,
          -24,
          12,
          (v) {
            setState(() => _shelfGain = v);
            if (_ready) _command(() => _applyFilter(_duration));
          },
        ),
      ],
      const Divider(height: 30),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Smooth controls'),
        subtitle: const Text('Fade play, pause, volume and filter changes'),
        value: _smooth,
        onChanged: (v) => setState(() => _smooth = v),
      ),
      _slider(
        'Control fade',
        '${_fade.toStringAsFixed(1)} s',
        _fade,
        0,
        3,
        (v) => setState(() => _fade = v),
      ),
      const Divider(height: 30),
      const Text(
        'Playlist setup',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      SegmentedButton<MusicRepeatMode>(
        segments: const [
          ButtonSegment(value: MusicRepeatMode.none, label: Text('Once')),
          ButtonSegment(value: MusicRepeatMode.one, label: Text('Repeat one')),
          ButtonSegment(value: MusicRepeatMode.all, label: Text('Repeat all')),
        ],
        selected: {_repeat},
        onSelectionChanged: _busy
            ? null
            : (v) => setState(() => _repeat = v.first),
      ),
      const SizedBox(height: 14),
      _slider(
        'Track crossfade',
        _crossfade == 0 ? 'Gapless' : '${_crossfade.toStringAsFixed(1)} s',
        _crossfade,
        0,
        5,
        (v) => setState(() => _crossfade = v),
      ),
      _slider(
        'Repeat overlap',
        '${_repeatCrossfade.toStringAsFixed(2)} s',
        _repeatCrossfade,
        0,
        3,
        (v) => setState(() => _repeatCrossfade = v),
      ),
      OutlinedButton(
        onPressed: _busy ? null : _load,
        child: const Text('Apply playlist setup'),
      ),
      const SizedBox(height: 6),
      const Text(
        'Applying playlist setup stops playback and prepares the list again.',
        style: TextStyle(fontSize: 12, height: 1.5),
      ),
    ],
  );

  Widget _slider(
    String label,
    String value,
    double current,
    double min,
    double max,
    ValueChanged<double> changed,
  ) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
      Slider(
        value: current.clamp(min, max),
        min: min,
        max: max,
        label: value,
        onChanged: _busy ? null : changed,
      ),
    ],
  );
}

/// A decorative timeline, not an audio waveform or signal meter.
class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.progress, this.overlap);
  final double progress;
  final bool overlap;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 40; i++) {
      final x = (i + .5) / 40 * size.width;
      final height =
          16 +
          58 * (0.5 + 0.5 * math.sin(i * .7)) * (0.6 + 0.4 * math.cos(i * .2));
      paint.color = i / 40 <= progress ? peach : Colors.white24;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.progress != progress || old.overlap != overlap;
}
