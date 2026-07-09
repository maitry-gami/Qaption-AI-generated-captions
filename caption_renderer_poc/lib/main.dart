import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:http/http.dart' as http;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'local_server.dart';
import 'services/caption_api_service.dart';
import 'models/caption_state.dart';
import 'screens/projects_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'models/project_model.dart';
import 'services/project_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caption Renderer POC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F11),
        textTheme: GoogleFonts.robotoTextTheme(ThemeData.dark().textTheme),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          surface: Color(0xFF1A1A1C),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final ProjectModel? project;
  const MyHomePage({super.key, this.project});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final List<Map<String, String>> _templates = [
    {'id': 'hormozi-style', 'name': 'Hormozi Style'},
    {'id': 'ali-abdaal', 'name': 'Ali Abdaal'},
    {'id': 'mr-beast', 'name': 'Mr. Beast'},
    {'id': 'karaoke-flow', 'name': 'Karaoke Flow'},
    {'id': 'pulse-wave', 'name': 'Pulse Wave'},
    {'id': 'typewriter-pro', 'name': 'Typewriter Pro'},
    {'id': 'neon-glow', 'name': 'Neon Glow'},
    {'id': 'impact-bounce', 'name': 'Impact Bounce'},
    {'id': 'minimalist-bg', 'name': 'Minimalist Overlay'},
  ];
  late final WebViewController _controller;
  final LocalServer _localServer = LocalServer();
  bool _serverStarted = false;
  double _exportProgress = 0.0;
  bool _isExporting = false;
  String _selectedTab = 'Editor';
  String _styleEditorTab = 'Template';
  String _selectedTemplate = 'hormozi-style';

  // Custom Styles
  Color? _customTextColor;
  double _customTextOpacity = 1.0;
  String _customFontFamily = 'Montserrat';
  String _customTextAlign = 'center';

  Color? _customEmphasisColor;
  Color? _customActiveWordColor;
  bool _isActiveWordColorEnabled = false;

  double? _customXOffset;
  double? _customYOffset;
  double? _customScale;

  // --- Breaks settings ---
  int _wordsPerLine = 3;
  int _maxLinesPerFrame = 2;

  // --- Video Adjustments ---
  double _videoBrightness = 1.0;
  double _videoContrast = 1.0;
  double _videoSaturation = 1.0;
  double _videoExposure = 0.0;
  double _videoShadows = 0.0;

  final List<String> _popularFonts = [
    'Montserrat',
    'Bangers',
    'Bebas Neue',
    'Roboto',
    'Oswald',
    'Lato',
  ];

  final ValueNotifier<double> _currentTimeNotifier = ValueNotifier<double>(0.0);
  double get _currentTime => _currentTimeNotifier.value;
  set _currentTime(double value) => _currentTimeNotifier.value = value;
  double _duration = 0.0;
  bool _isPlaying = false;
  bool _isMuted = false;
  double _videoAspectRatio = 9 / 16;
  List<String> _thumbnails = [];
  List<dynamic> _captionsList = [];
  List<dynamic> _wordsList = [];
  bool _captionsEditMode = false;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  double _sheetSize = 0.35;

  late final ScrollController _lyricsScrollController = ScrollController();
  late final ScrollController _timelineScrollController = ScrollController();
  int _activeWordIndex = -1;
  // Timeline smooth scroll
  late final AnimationController _scrollAnimController;
  double _scrollTargetOffset = 0.0;
  static const double _kPixelsPerSecond = 140.0;

  bool _isUserScrollingTimeline = false;

  // --- Undo/Redo States ---
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  final List<String> _styleUndoStack = [];
  final List<String> _styleRedoStack = [];

  // --- Caption Pipeline State ---
  CaptionApiService _captionApiService = CaptionApiService();
  final ProjectService _projectService = ProjectService();
  final ImagePicker _imagePicker = ImagePicker();
  CaptionPipelineStatus _pipelineStatus = CaptionPipelineStatus.idle;
  double _uploadProgress = 0.0;
  String? _selectedVideoPath;
  String? _pipelineErrorMessage;
  CaptionResult? _captionResult;

  String _formatTime(double seconds) {
    int secs = seconds.toInt();
    int m = secs ~/ 60;
    int s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  late String _projectName;
  VideoPlayerController? _previewVideoController;

  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _projectName = widget.project?.name ?? 'My Project';

    if (widget.project != null) {
      _selectedVideoPath = widget.project!.videoPath;
      _initializePreviewVideo();
    }

    // Smooth timeline scroll animation
    _scrollAnimController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 100),
        )..addListener(() {
          if (_timelineScrollController.hasClients &&
              !_isUserScrollingTimeline) {
            final double current = _timelineScrollController.offset;
            final double target = _scrollTargetOffset;
            final double next =
                current + (target - current) * _scrollAnimController.value;
            _timelineScrollController.jumpTo(
              next.clamp(
                0.0,
                _timelineScrollController.position.maxScrollExtent,
              ),
            );
          }
        });
    _sheetController.addListener(() {
      if (mounted) {
        setState(() {
          _sheetSize = _sheetController.size;
        });
      }
    });
    final _project = widget.project;
    if (_project != null) {
      _selectedVideoPath = _project.videoPath;
      _localServer.userVideoPath = _selectedVideoPath;

      if (_project.captionResult != null) {
        _pipelineStatus = CaptionPipelineStatus.success;
        _captionResult = CaptionResult.fromJson(_project.captionResult!);
        _captionsList = _captionResult!.segments
            .map((s) => s.toJson())
            .toList();
        _wordsList = [];
        for (var segment in _captionResult!.segments) {
          _wordsList.addAll(segment.words.map((w) => w.toJson()).toList());
        }
        _localServer.captionJsonOverride = jsonEncode(_captionResult!.toJson());
      } else {
        _pipelineStatus = CaptionPipelineStatus.videoSelected;
        _captionsList = [];
        _wordsList = [];
        _localServer.captionJsonOverride = '{"segments": []}';
      }

      if (_project.style != null) {
        _selectedTemplate = _project.style!;
      }
      if (widget.project!.customStyles != null) {
        final Map<String, dynamic> c = widget.project!.customStyles!;
        _customTextColor = c['color'] != null ? Color(c['color']) : null;
        _customTextOpacity = c['opacity'] ?? 1.0;
        _customFontFamily = c['fontFamily'] ?? 'Montserrat';
        _customTextAlign = c['textAlign'] ?? 'center';
        _customEmphasisColor = c['emphasisColor'] != null
            ? Color(c['emphasisColor'])
            : null;
        _customActiveWordColor = c['activeWordColor'] != null
            ? Color(c['activeWordColor'])
            : null;
        _isActiveWordColorEnabled = c['isActiveWordColorEnabled'] ?? false;
        _customXOffset = (c['xOffset'] as num?)?.toDouble();
        _customYOffset = (c['yOffset'] as num?)?.toDouble();
        _customScale = (c['scale'] as num?)?.toDouble();
        _wordsPerLine = c['wordsPerLine'] ?? 3;
        _maxLinesPerFrame = c['maxLinesPerFrame'] ?? 2;
      }
      if (widget.project!.videoAdjustments != null) {
        final Map<String, dynamic> a = widget.project!.videoAdjustments!;
        _videoBrightness = (a['brightness'] as num?)?.toDouble() ?? 1.0;
        _videoContrast = (a['contrast'] as num?)?.toDouble() ?? 1.0;
        _videoSaturation = (a['saturation'] as num?)?.toDouble() ?? 1.0;
        _videoExposure = (a['exposure'] as num?)?.toDouble() ?? 0.0;
        _videoShadows = (a['shadows'] as num?)?.toDouble() ?? 0.0;
      }
    } else {
      _loadCaptions();
    }
    _initServerAndWebView();
  }

  Future<void> _loadCaptions() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/web/captions.json',
      );
      final data = await json.decode(response);
      setState(() {
        _captionsList = data['segments'];
        _wordsList = [];
        for (var segment in _captionsList) {
          if (segment['words'] != null) {
            _wordsList.addAll(segment['words']);
          }
        }
      });
    } catch (e) {
      print("Failed to load captions: $e");
    }
  }

  Future<void> _initializePreviewVideo() async {
    if (widget.project == null) return;
    try {
      _previewVideoController = VideoPlayerController.file(
        File(widget.project!.videoPath),
      );
      await _previewVideoController!.initialize();
      if (mounted) {
        setState(() {}); // Rebuild to show the first frame
      }
    } catch (e) {
      debugPrint("Failed to initialize preview video: $e");
    }
  }

  Future<void> _initServerAndWebView() async {
    await _localServer.start();

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..addJavaScriptChannel(
        'ProgressChannel',
        onMessageReceived: (JavaScriptMessage message) {
          final progress = double.tryParse(message.message) ?? 0.0;
          setState(() {
            _exportProgress = progress;
          });
        },
      )
      ..addJavaScriptChannel(
        'TimeUpdateChannel',
        onMessageReceived: (JavaScriptMessage message) {
          final data = jsonDecode(message.message);

          if (_duration != data['duration'] ||
              _isPlaying != data['isPlaying'] ||
              _isMuted != data['isMuted']) {
            setState(() {
              _duration = data['duration'];
              _isPlaying = data['isPlaying'];
              _isMuted = data['isMuted'];
            });
          }

          _currentTimeNotifier.value = data['currentTime'];

          if (_wordsList.isNotEmpty) {
            int newActiveIndex = _wordsList.indexWhere(
              (wordObj) =>
                  _currentTime >= wordObj['start'] &&
                  _currentTime <= wordObj['end'],
            );
            if (newActiveIndex != -1 && newActiveIndex != _activeWordIndex) {
              _activeWordIndex = newActiveIndex;
              if (_lyricsScrollController.hasClients) {
                double offset = _activeWordIndex * 70.0;
                if (offset > _lyricsScrollController.position.maxScrollExtent) {
                  offset = _lyricsScrollController.position.maxScrollExtent;
                }
                _lyricsScrollController.animateTo(
                  offset,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                );
              }
            }
          }

          if (!_isUserScrollingTimeline &&
              _timelineScrollController.hasClients &&
              _duration > 0) {
            final double targetOffset = (_currentTime * _kPixelsPerSecond)
                .clamp(0.0, _timelineScrollController.position.maxScrollExtent);
            _timelineScrollController.jumpTo(targetOffset);
          }
        },
      )
      ..addJavaScriptChannel(
        'StylesChangedChannel',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message);
            setState(() {
              _customXOffset = (data['xOffset'] as num?)?.toDouble();
              _customYOffset = (data['yOffset'] as num?)?.toDouble();
              _customScale = (data['scale'] as num?)?.toDouble();
            });
            _saveProjectState();
          } catch (e) {
            print("Failed to parse styles change message: $e");
          }
        },
      )
      ..addJavaScriptChannel(
        'ThumbnailsChannel',
        onMessageReceived: (JavaScriptMessage message) {
          final List<dynamic> data = jsonDecode(message.message);
          setState(() {
            _thumbnails = data.cast<String>();
          });
        },
      )
      ..addJavaScriptChannel(
        'VideoDimensionsChannel',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message);
            final double? vw = data['videoWidth'] != null
                ? (data['videoWidth'] as num).toDouble()
                : null;
            final double? vh = data['videoHeight'] != null
                ? (data['videoHeight'] as num).toDouble()
                : null;
            if (vw != null && vh != null && vh > 0) {
              final double newAspect = vw / vh;
              if (_videoAspectRatio != newAspect) {
                setState(() {
                  _videoAspectRatio = newAspect;
                });
              }
            }
          } catch (e) {
            debugPrint('Failed to parse video dimensions: $e');
          }
        },
      );

    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    await _controller.clearCache();
    _controller.loadRequest(Uri.parse('http://localhost:${_localServer.port}'));

    _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (String url) {
          // If a project was passed, inject its details now that the page has loaded
          if (widget.project != null) {
            _controller.runJavaScript(
              'window.reloadVideo && window.reloadVideo()',
            );

            if (widget.project!.captionResult != null) {
              _injectCaptionsIntoWebView(_captionResult!);
              _controller.runJavaScript(
                "window.setStyle('$_selectedTemplate')",
              );
              _updateCustomStyles();
              _updateVideoAdjustments();
            } else {
              setState(() {
                _pipelineStatus = CaptionPipelineStatus.videoSelected;
              });
            }
          }
        },
      ),
    );

    setState(() {
      _serverStarted = true;
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _saveProjectState();
    _previewVideoController?.dispose();
    _lyricsScrollController.dispose();
    _timelineScrollController.dispose();
    _scrollAnimController.dispose();
    _captionApiService.dispose();
    _currentTimeNotifier.dispose();
    _localServer.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveProjectState();
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () {
      _saveProjectState();
    });
  }

  Future<void> _saveProjectState() async {
    if (widget.project == null) return;

    final updatedProject = ProjectModel(
      id: widget.project!.id,
      name: _projectName,
      videoPath: widget.project!.videoPath,
      updatedAt: DateTime.now(),
      captionResult: _captionResult?.toJson(),
      style: _selectedTemplate,
      customStyles: {
        if (_customTextColor != null) 'color': _customTextColor!.value,
        'opacity': _customTextOpacity,
        'fontFamily': _customFontFamily,
        'textAlign': _customTextAlign,
        if (_customEmphasisColor != null)
          'emphasisColor': _customEmphasisColor!.value,
        if (_customActiveWordColor != null)
          'activeWordColor': _customActiveWordColor!.value,
        'isActiveWordColorEnabled': _isActiveWordColorEnabled,
        'xOffset': _customXOffset,
        'yOffset': _customYOffset,
        'scale': _customScale,
        'wordsPerLine': _wordsPerLine,
        'maxLinesPerFrame': _maxLinesPerFrame,
      },
      videoAdjustments: {
        'brightness': _videoBrightness,
        'contrast': _videoContrast,
        'saturation': _videoSaturation,
        'exposure': _videoExposure,
        'shadows': _videoShadows,
      },
    );

    await _projectService.saveProject(updatedProject);
  }

  // ───────────────────────────────────────────────
  // Caption Pipeline Methods
  // ───────────────────────────────────────────────

  /// Opens the device gallery to pick a video, then starts the caption pipeline.
  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );
      if (video == null) return; // user cancelled

      setState(() {
        _selectedVideoPath = video.path;
        _pipelineStatus = CaptionPipelineStatus.videoSelected;
        _pipelineErrorMessage = null;
        _captionResult = null;
        _captionsList = [];
        _wordsList = [];
      });

      // Tell the local server to serve the new video file
      _localServer.userVideoPath = video.path;
      _localServer.captionJsonOverride = '{"segments": []}';

      // Reload the WebView so it picks up the new video source
      await _controller.loadRequest(
        Uri.parse('http://localhost:${_localServer.port}'),
      );

      // Give the WebView a moment to reload before triggering thumbnail regen
      await Future.delayed(const Duration(milliseconds: 500));
      _controller.runJavaScript('window.reloadVideo && window.reloadVideo()');

      // Auto-start the caption pipeline
      _startCaptionPipeline();
    } catch (e) {
      setState(() {
        _pipelineStatus = CaptionPipelineStatus.error;
        _pipelineErrorMessage = 'Failed to pick video: $e';
      });
    }
  }

  /// Orchestrates: upload → generate captions → store → inject into WebView.
  Future<void> _startCaptionPipeline() async {
    if (_selectedVideoPath == null) return;

    final videoFile = File(_selectedVideoPath!);
    if (!await videoFile.exists()) {
      setState(() {
        _pipelineStatus = CaptionPipelineStatus.error;
        _pipelineErrorMessage = 'Selected video file no longer exists.';
      });
      return;
    }

    // --- Upload phase ---
    setState(() {
      _pipelineStatus = CaptionPipelineStatus.uploading;
      _uploadProgress = 0.0;
      _pipelineErrorMessage = null;
    });

    try {
      final result = await _captionApiService.generateCaptions(
        videoFile: videoFile,
        settings: const TranscriptionSettings(),
        onUploadProgress: (percent) {
          if (mounted) {
            setState(() {
              _uploadProgress = percent;
              // Switch to processing phase once upload reaches 99.5%
              if (percent >= 99.5 &&
                  _pipelineStatus == CaptionPipelineStatus.uploading) {
                _pipelineStatus = CaptionPipelineStatus.processing;
              }
            });
          }
        },
      );

      // --- Success: store and inject ---
      setState(() {
        _captionResult = result;
        _pipelineStatus = CaptionPipelineStatus.success;

        // Populate the existing lists so lyrics bar, word highlighting,
        // timeline, and export all work unchanged.
        _captionsList = result.segments.map((s) => s.toJson()).toList();
        _wordsList = [];
        for (var segment in result.segments) {
          _wordsList.addAll(segment.words.map((w) => w.toJson()).toList());
        }
      });

      _injectCaptionsIntoWebView(result);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Captions generated successfully!'),
            backgroundColor: Color(0xFF22C55E),
            duration: Duration(seconds: 2),
          ),
        );
      }

      _saveProjectState();
    } on CaptionApiException catch (e) {
      if (mounted) {
        setState(() {
          _pipelineStatus = CaptionPipelineStatus.error;
          _pipelineErrorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pipelineStatus = CaptionPipelineStatus.error;
          _pipelineErrorMessage = 'Unexpected error: $e';
        });
      }
    }
  }

  /// Injects caption data into the WebView without a page reload.
  void _injectCaptionsIntoWebView(CaptionResult result) {
    final captionJson = jsonEncode(result.toJson());
    // Also set the override on the local server so subsequent page
    // loads (e.g. after a WebView recycle) serve the new data.
    _localServer.captionJsonOverride = captionJson;

    // Escape single quotes and newlines for safe JS string embedding
    final escapedJson = captionJson
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n');
    _controller.runJavaScript("window.updateCaptions('$escapedJson')");
  }

  /// Resets error state and re-runs the caption pipeline.
  void _retryPipeline() {
    setState(() {
      _pipelineStatus = CaptionPipelineStatus.videoSelected;
      _pipelineErrorMessage = null;
    });
    _startCaptionPipeline();
  }

  void _cancelPipeline() {
    _captionApiService.dispose();
    setState(() {
      _captionApiService = CaptionApiService();
      _pipelineStatus = CaptionPipelineStatus.idle;
      _uploadProgress = 0.0;
    });
  }

  void _editProjectName() {
    TextEditingController nameController = TextEditingController(
      text: _projectName,
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151517),
          title: const Text(
            'Edit Project Name',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Enter project name',
              hintStyle: TextStyle(color: Colors.grey),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF8B5CF6)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
              ),
              onPressed: () async {
                setState(() {
                  _projectName = nameController.text;
                });
                await _saveProjectState();
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _pushUndoState() {
    final stateJson = jsonEncode(_captionsList);
    _undoStack.add(stateJson);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final currentStateJson = jsonEncode(_captionsList);
    _redoStack.add(currentStateJson);

    final prevStateJson = _undoStack.removeLast();
    setState(() {
      _captionsList = jsonDecode(prevStateJson);
      _wordsList = [];
      for (var segment in _captionsList) {
        if (segment['words'] != null) {
          _wordsList.addAll(segment['words']);
        }
      }
      // Rebuild _captionResult
      final updatedSegments = _captionsList
          .map(
            (s) => CaptionSegment.fromJson(Map<String, dynamic>.from(s as Map)),
          )
          .toList();
      _captionResult = CaptionResult(
        success: _captionResult?.success ?? true,
        segments: updatedSegments,
        srt: _captionResult?.srt,
        engine: _captionResult?.engine,
        error: _captionResult?.error,
      );
    });
    if (_captionResult != null) {
      _injectCaptionsIntoWebView(_captionResult!);
    }
  }

  Map<String, dynamic> _getStyleState() {
    return {
      'template': _selectedTemplate,
      'textColor': _customTextColor?.value,
      'textOpacity': _customTextOpacity,
      'fontFamily': _customFontFamily,
      'textAlign': _customTextAlign,
      'emphasisColor': _customEmphasisColor?.value,
      'activeColor': _customActiveWordColor?.value,
      'isActiveColorEnabled': _isActiveWordColorEnabled,
      'xOffset': _customXOffset,
      'yOffset': _customYOffset,
      'scale': _customScale,
      'wordsPerLine': _wordsPerLine,
      'maxLinesPerFrame': _maxLinesPerFrame,
    };
  }

  void _restoreStyleState(Map<String, dynamic> state) {
    setState(() {
      _selectedTemplate = state['template'];
      _customTextColor = state['textColor'] != null
          ? Color(state['textColor'])
          : null;
      _customTextOpacity = state['textOpacity'] ?? 1.0;
      _customFontFamily = state['fontFamily'] ?? 'Inter';
      _customTextAlign = state['textAlign'] ?? 'center';
      _customEmphasisColor = state['emphasisColor'] != null
          ? Color(state['emphasisColor'])
          : null;
      _customActiveWordColor = state['activeColor'] != null
          ? Color(state['activeColor'])
          : null;
      _isActiveWordColorEnabled = state['isActiveColorEnabled'] ?? true;
      _customXOffset = state['xOffset'];
      _customYOffset = state['yOffset'];
      _customScale = state['scale'];
      _wordsPerLine = state['wordsPerLine'] ?? 3;
      _maxLinesPerFrame = state['maxLinesPerFrame'] ?? 2;
    });
    if (_selectedTemplate != null && _selectedTemplate != 'none') {
      _controller.runJavaScript("window.setStyle('$_selectedTemplate')");
    }
    _updateCustomStyles();
  }

  void _pushStyleUndoState() {
    setState(() {
      _styleUndoStack.add(jsonEncode(_getStyleState()));
      _styleRedoStack.clear();
    });
  }

  void _undoStyle() {
    if (_styleUndoStack.isEmpty) return;
    setState(() {
      _styleRedoStack.add(jsonEncode(_getStyleState()));
      final prevState = jsonDecode(_styleUndoStack.removeLast());
      _restoreStyleState(prevState);
    });
  }

  void _redoStyle() {
    if (_styleRedoStack.isEmpty) return;
    setState(() {
      _styleUndoStack.add(jsonEncode(_getStyleState()));
      final nextState = jsonDecode(_styleRedoStack.removeLast());
      _restoreStyleState(nextState);
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final currentStateJson = jsonEncode(_captionsList);
    _undoStack.add(currentStateJson);

    final nextStateJson = _redoStack.removeLast();
    setState(() {
      _captionsList = jsonDecode(nextStateJson);
      _wordsList = [];
      for (var segment in _captionsList) {
        if (segment['words'] != null) {
          _wordsList.addAll(segment['words']);
        }
      }
      // Rebuild _captionResult
      final updatedSegments = _captionsList
          .map(
            (s) => CaptionSegment.fromJson(Map<String, dynamic>.from(s as Map)),
          )
          .toList();
      _captionResult = CaptionResult(
        success: _captionResult?.success ?? true,
        segments: updatedSegments,
        srt: _captionResult?.srt,
        engine: _captionResult?.engine,
        error: _captionResult?.error,
      );
    });
    if (_captionResult != null) {
      _injectCaptionsIntoWebView(_captionResult!);
    }
  }

  void _updateSegmentText(int segmentIndex, String newText) {
    _pushUndoState();
    final segment = Map<String, dynamic>.from(
      _captionsList[segmentIndex] as Map,
    );
    final originalWords = segment['words'] as List<dynamic>? ?? [];

    // Clean up whitespace and split into words
    final cleanText = newText.trim().replaceAll(RegExp(r'\s+'), ' ');
    final newWords = cleanText.split(' ').where((w) => w.isNotEmpty).toList();

    final double segStart = (segment['start'] as num).toDouble();
    final double segEnd = (segment['end'] as num).toDouble();
    final double duration = segEnd - segStart;

    List<Map<String, dynamic>> updatedWords = [];

    if (newWords.length == originalWords.length) {
      // Word count is the same, preserve original timestamps, just update the spelling
      for (int i = 0; i < originalWords.length; i++) {
        final wObj = Map<String, dynamic>.from(originalWords[i] as Map);
        wObj['word'] = newWords[i];
        updatedWords.add(wObj);
      }
    } else if (newWords.isNotEmpty) {
      // Word count changed, distribute time evenly
      final double wordDuration = duration / newWords.length;
      for (int i = 0; i < newWords.length; i++) {
        updatedWords.add({
          'word': newWords[i],
          'start': segStart + (i * wordDuration),
          'end': segStart + ((i + 1) * wordDuration),
        });
      }
    }

    setState(() {
      // Update the segment text and words in _captionsList
      _captionsList[segmentIndex] = {
        ...segment,
        'text': cleanText,
        'words': updatedWords,
      };

      // Rebuild the flattened _wordsList from the updated _captionsList
      _wordsList = [];
      for (var seg in _captionsList) {
        if (seg['words'] != null) {
          _wordsList.addAll(seg['words']);
        }
      }

      // Re-create the _captionResult state
      final updatedSegments = _captionsList
          .map(
            (s) => CaptionSegment.fromJson(Map<String, dynamic>.from(s as Map)),
          )
          .toList();
      _captionResult = CaptionResult(
        success: _captionResult?.success ?? true,
        segments: updatedSegments,
        srt: _captionResult?.srt,
        engine: _captionResult?.engine,
        error: _captionResult?.error,
      );
    });

    // Re-inject updated captions into the WebView immediately so the preview updates
    if (_captionResult != null) {
      _injectCaptionsIntoWebView(_captionResult!);
    }

    _saveProjectState();
  }

  void _showEditSegmentDialog(int index, String currentText) {
    final textController = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Edit Caption Segment',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: textController,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter caption text...',
              hintStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFF2C2C2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF8B5CF6),
                  width: 1.5,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                _updateSegmentText(index, textController.text);
                Navigator.of(context).pop();
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _setStyle(String styleId) {
    _pushStyleUndoState();
    setState(() {
      _selectedTemplate = styleId;
      if (styleId == 'mr-beast') {
        _customFontFamily = 'Bangers';
        _customTextColor = const Color(0xFFFFFFFF);
        _customEmphasisColor = const Color(0xFFFFFF00);
      } else if (styleId == 'ali-abdaal') {
        _customFontFamily = 'Inter';
        _customTextColor = const Color(0xFFFFFFFF);
        _customEmphasisColor = const Color(0xFF00E5FF);
      } else if (styleId == 'karaoke-flow') {
        _customFontFamily = 'Montserrat';
        _customTextColor = const Color(0xFFAAAAAA);
        _customEmphasisColor = const Color(0xFF3B82F6);
      } else if (styleId == 'pulse-wave') {
        _customFontFamily = 'Montserrat';
        _customTextColor = const Color(0xFFFFFFFF);
        _customEmphasisColor = const Color(0xFF8B5CF6);
      } else if (styleId == 'typewriter-pro') {
        _customFontFamily = 'Inter';
        _customTextColor = const Color(0xFFFFFFFF);
        _customEmphasisColor = const Color(0xFF00FF00);
      } else if (styleId == 'neon-glow') {
        _customFontFamily = 'Orbitron';
        _customTextColor = const Color(0xFFFFFFFF);
        _customEmphasisColor = const Color(0xFF00FFCC);
      } else if (styleId == 'impact-bounce') {
        _customFontFamily = 'Anton';
        _customTextColor = const Color(0xFFFFFFFF);
        _customEmphasisColor = const Color(0xFFFFE600);
      } else if (styleId == 'minimalist-bg') {
        _customFontFamily = 'Inter';
        _customTextColor = const Color(0xFFFFFFFF);
        _customEmphasisColor = const Color(0xFFA78BFA);
      } else {
        _customFontFamily = 'Montserrat';
        _customTextColor = const Color(0xFFFFFFFF);
        _customEmphasisColor = const Color(0xFFFFFF00);
      }
    });
    _controller.runJavaScript("window.setStyle('$styleId')");
    _updateCustomStyles();
    _scheduleSave();
  }

  void _updateVideoAdjustments() {
    if (!_serverStarted) return;
    _controller.runJavaScript(
      'window.setVideoAdjustments && window.setVideoAdjustments($_videoBrightness, $_videoContrast, $_videoSaturation, $_videoExposure, $_videoShadows)',
    );
    _scheduleSave();
  }

  void _updateCustomStyles() {
    String textColorHex = '';
    if (_customTextColor != null) {
      final tr = (_customTextColor!.r * 255)
          .toInt()
          .toRadixString(16)
          .padLeft(2, '0');
      final tg = (_customTextColor!.g * 255)
          .toInt()
          .toRadixString(16)
          .padLeft(2, '0');
      final tb = (_customTextColor!.b * 255)
          .toInt()
          .toRadixString(16)
          .padLeft(2, '0');
      textColorHex = '#$tr$tg$tb';
    }

    String emphasisColorHex = '';
    if (_customEmphasisColor != null) {
      final er = (_customEmphasisColor!.r * 255)
          .toInt()
          .toRadixString(16)
          .padLeft(2, '0');
      final eg = (_customEmphasisColor!.g * 255)
          .toInt()
          .toRadixString(16)
          .padLeft(2, '0');
      final eb = (_customEmphasisColor!.b * 255)
          .toInt()
          .toRadixString(16)
          .padLeft(2, '0');
      emphasisColorHex = '#$er$eg$eb';
    }

    String activeColorHex = '';
    if (_customActiveWordColor != null) {
      final ar = (_customActiveWordColor!.r * 255)
          .toInt()
          .toRadixString(16)
          .padLeft(2, '0');
      final ag = (_customActiveWordColor!.g * 255)
          .toInt()
          .toRadixString(16)
          .padLeft(2, '0');
      final ab = (_customActiveWordColor!.b * 255)
          .toInt()
          .toRadixString(16)
          .padLeft(2, '0');
      activeColorHex = '#$ar$ag$ab';
    }

    _controller.runJavaScript(
      "window.setCustomStyles('$textColorHex', $_customTextOpacity, '$_customFontFamily', '$_customTextAlign', '$emphasisColorHex', '$activeColorHex', $_isActiveWordColorEnabled, $_customXOffset, $_customYOffset, $_customScale, $_wordsPerLine, $_maxLinesPerFrame)",
    );
    // Trigger rebuild so the native caption preview updates
    setState(() {});
    _scheduleSave();
  }

  void _startExport() async {
    final prefs = await SharedPreferences.getInstance();
    final exportTime = prefs.getInt('export_time') ?? 600;
    if (exportTime <= 0 || _duration > exportTime) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not enough AI export time available! Please upgrade your plan.')),
        );
      }
      return;
    }

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    // Fake progress timer to show activity while Node.js renders
    bool isDone = false;
    Future(() async {
      while (!isDone && _exportProgress < 95.0) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted && !isDone) {
          setState(() {
            _exportProgress +=
                (95.0 - _exportProgress) * 0.05; // slowly approach 95%
          });
        }
      }
    });

    try {
      // Use local render server via local Wi-Fi IP for physical device testing
      final url = Uri.parse('http://192.168.1.11:8000/render');

      final request = http.MultipartRequest('POST', url);
      request.fields['style'] = _selectedTemplate;

      final Map<String, dynamic> styles = {
        'fontFamily': _customFontFamily,
        'textAlign': _customTextAlign,
        'opacity': _customTextOpacity,
        'isActiveWordColorEnabled': _isActiveWordColorEnabled,
        'xOffset': _customXOffset,
        'yOffset': _customYOffset,
        'scale': _customScale,
        'wordsPerLine': _wordsPerLine,
        'maxLinesPerFrame': _maxLinesPerFrame,
      };

      if (_customTextColor != null) {
        styles['color'] =
            '#${_customTextColor!.value.toRadixString(16).padLeft(8, '0').substring(2)}';
      }
      if (_customEmphasisColor != null) {
        styles['emphasisColor'] =
            '#${_customEmphasisColor!.value.toRadixString(16).padLeft(8, '0').substring(2)}';
      }
      if (_isActiveWordColorEnabled && _customActiveWordColor != null) {
        styles['activeWordColor'] =
            '#${_customActiveWordColor!.value.toRadixString(16).padLeft(8, '0').substring(2)}';
      }

      request.fields['customStyles'] = jsonEncode(styles);
      request.fields['videoAdjustments'] = jsonEncode({
        'brightness': _videoBrightness,
        'contrast': _videoContrast,
        'saturation': _videoSaturation,
        'exposure': _videoExposure,
        'shadows': _videoShadows,
      });

      if (_captionsList.isNotEmpty) {
        request.fields['captions'] = jsonEncode({'segments': _captionsList});
      }

      if (_selectedVideoPath != null) {
        request.files.add(
          await http.MultipartFile.fromPath('video', _selectedVideoPath!),
        );
      }

      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 5),
      );
      final response = await http.Response.fromStream(streamedResponse);

      isDone = true; // stop fake progress

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          setState(() {
            _exportProgress = 99.0;
          });

          String downloadUrl = data['url'];
          // Ensure downloadUrl points to 127.0.0.1
          downloadUrl = downloadUrl
              .replaceAll('0.0.0.0', '127.0.0.1')
              .replaceAll('10.0.2.2', '127.0.0.1');

          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/exported_video.mp4');

          final videoResponse = await http
              .get(Uri.parse(downloadUrl))
              .timeout(const Duration(minutes: 5));
          await file.writeAsBytes(videoResponse.bodyBytes);

          bool hasAccess = await Gal.hasAccess();
          if (!hasAccess) {
            await Gal.requestAccess();
          }
          await Gal.putVideo(file.path);

          if (mounted) {
            setState(() {
              _exportProgress = 100.0;
            });
            
            final prefs = await SharedPreferences.getInstance();
            int exportTime = prefs.getInt('export_time') ?? 600;
            exportTime -= _duration.toInt();
            if (exportTime < 0) exportTime = 0;
            await prefs.setInt('export_time', exportTime);

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Video exported and saved to Gallery successfully!',
                ),
              ),
            );
          }
        } else {
          throw Exception(data['error'] ?? 'Unknown success=false error');
        }
      } else {
        String errorMsg = 'Server returned ${response.statusCode}';
        try {
          final data = jsonDecode(response.body);
          if (data['error'] != null) {
            errorMsg += ': ${data['error']}';
          }
        } catch (_) {}
        throw Exception(errorMsg);
      }
    } catch (e) {
      isDone = true;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to export video: $e')));
      }
    } finally {
      isDone = true;
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportProgress = 0.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Snap sizes for the bottom sheet:
    //  0.22 → collapsed  (only controls strip visible)
    //  0.38 → default    (full editor panel)
    //  0.88 → maximised  (e.g. when editing captions)
    const double snapCollapsed = 0.15;
    const double snapDefault = 0.37;
    const double snapMax = 0.88;

    final bool isCollapsed = _sheetSize <= 0.16;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Responsive WebView (fitted above bottom sheet) ──────────────
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).size.height * _sheetSize + 16,
            child: Center(
              child: AspectRatio(
                aspectRatio: _videoAspectRatio,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: _serverStarted
                      ? WebViewWidget(controller: _controller)
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_previewVideoController != null &&
                                _previewVideoController!.value.isInitialized)
                              FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(
                                  width:
                                      _previewVideoController!.value.size.width,
                                  height: _previewVideoController!
                                      .value
                                      .size
                                      .height,
                                  child: VideoPlayer(_previewVideoController!),
                                ),
                              )
                            else
                              const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF8B5CF6),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),

          if (_selectedTab == 'Captions')
            Positioned.fill(child: _buildFullScreenCaptionsEditor()),

          if (_selectedTab != 'Captions')
            // ── Top Bar Overlay ─────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Transform.translate(
                          offset: const Offset(-8, 0),
                          child: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _editProjectName,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _projectName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.edit,
                              color: Colors.white54,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _isExporting ? null : _startExport,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF8B5CF6,
                                  ).withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _isExporting
                                ? Text(
                                    '${_exportProgress.toInt()}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 0,
                                    ),
                                  )
                                : const Text(
                                    'Export',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 0,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Draggable bottom sheet ───────────────────────────────────────
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: snapDefault,
            minChildSize: snapCollapsed,
            maxChildSize: snapMax,
            snap: true,
            snapSizes: const [snapCollapsed, snapDefault, snapMax],
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF151517),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 20,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  physics: const NeverScrollableScrollPhysics(),
                  child: isCollapsed
                      ? _buildCollapsedEditor()
                      : (_selectedTab == 'Style' ||
                            _selectedTab == 'Captions')
                      ? const SizedBox.shrink()
                      : _selectedTab == 'Adjust'
                      ? _buildAdjustTab()
                      : _buildMainEditor(),
                ),
              );
            },
          ),

          if (_selectedTab == 'Captions')
            Positioned.fill(child: _buildFullScreenCaptionsEditor()),

          if (_selectedTab == 'Style')
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).size.height * 0.33,
              child: _buildStyleCaptionPreview(),
            ),

          if (_selectedTab == 'Style')
            Positioned(
              top: MediaQuery.of(context).size.height * 0.33,
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildStyleEditor(),
            ),

          // ── Pipeline full-screen overlay (Transcribing) ─────────────────
          if (_pipelineStatus == CaptionPipelineStatus.videoSelected)
            _buildStyleSelectionOverlay(),
          _buildTranscribingOverlay(),

          // ── Export full-screen overlay ──────────────────────────────────
          _buildExportingOverlay(),
        ],
      ),
    );
  }

  Widget _buildCollapsedEditor() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thin white progress/scrub bar across full width
        GestureDetector(
          onTapDown: (details) {
            final double width = MediaQuery.of(context).size.width;
            final double tapX = details.localPosition.dx;
            final double percent = (tapX / width).clamp(0.0, 1.0);
            _controller.runJavaScript('window.seekTo(${percent * _duration})');
          },
          onHorizontalDragUpdate: (details) {
            final double width = MediaQuery.of(context).size.width;
            final double dragX = details.localPosition.dx;
            final double percent = (dragX / width).clamp(0.0, 1.0);
            _controller.runJavaScript('window.seekTo(${percent * _duration})');
          },
          child: SizedBox(
            height: 16,
            width: double.infinity,
            child: ValueListenableBuilder<double>(
              valueListenable: _currentTimeNotifier,
              builder: (context, time, child) {
                final double percent = _duration > 0
                    ? (time / _duration).clamp(0.0, 1.0)
                    : 0.0;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Container(
                          width: constraints.maxWidth * percent,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Positioned(
                          left: (constraints.maxWidth * percent) - 6,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Row: play/pause | time | spacer | undo | redo | expand chevron
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  _controller.runJavaScript("window.togglePlay()");
                },
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              ValueListenableBuilder<double>(
                valueListenable: _currentTimeNotifier,
                builder: (context, time, child) {
                  return Text(
                    '${_formatTime(time)} / ${_formatTime(_duration)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  );
                },
              ),
              const Spacer(),
              // Undo
              IconButton(
                icon: Icon(
                  Icons.undo,
                  color: _undoStack.isNotEmpty
                      ? Colors.white
                      : Colors.grey[700],
                  size: 20,
                ),
                onPressed: _undoStack.isNotEmpty ? _undo : null,
              ),
              // Redo
              IconButton(
                icon: Icon(
                  Icons.redo,
                  color: _redoStack.isNotEmpty
                      ? Colors.white
                      : Colors.grey[700],
                  size: 20,
                ),
                onPressed: _redoStack.isNotEmpty ? _redo : null,
              ),
              // Expand
              IconButton(
                icon: const Icon(
                  Icons.keyboard_arrow_up,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () {
                  _sheetController.animateTo(
                    0.37,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16.0),
      ],
    );
  }

  // ── Adjust Tab ──────────────────────────────────────────────────────────────
  Widget _buildAdjustTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 20),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Text(
                'Adjust',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () {
                      // Reset all adjustments to defaults
                      setState(() {
                        _videoBrightness = 1.0;
                        _videoContrast = 1.0;
                        _videoSaturation = 1.0;
                        _videoExposure = 0.0;
                        _videoShadows = 0.0;
                      });
                      _updateVideoAdjustments();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Reset',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      _selectTab('Editor');
                      _sheetController.animateTo(
                        0.37,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        // Scrollable Sliders within fixed height
        Container(
          height:
              220, // Fixed height to fit within the 0.35 panel without expanding it
          decoration: const BoxDecoration(
            color: Color(0xFF151515), // Distinct background for scrollable area
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 10, bottom: 20),
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                _buildAdjustSlider(
                  label: 'Brightness',
                  icon: Icons.brightness_6,
                  value: _videoBrightness,
                  min: 0.0,
                  max: 2.0,
                  defaultVal: 1.0,
                  onChanged: (v) {
                    setState(() => _videoBrightness = v);
                    _updateVideoAdjustments();
                  },
                ),
                _buildAdjustSlider(
                  label: 'Contrast',
                  icon: Icons.contrast,
                  value: _videoContrast,
                  min: 0.0,
                  max: 2.0,
                  defaultVal: 1.0,
                  onChanged: (v) {
                    setState(() => _videoContrast = v);
                    _updateVideoAdjustments();
                  },
                ),
                _buildAdjustSlider(
                  label: 'Saturation',
                  icon: Icons.color_lens_outlined,
                  value: _videoSaturation,
                  min: 0.0,
                  max: 2.0,
                  defaultVal: 1.0,
                  onChanged: (v) {
                    setState(() => _videoSaturation = v);
                    _updateVideoAdjustments();
                  },
                ),
                _buildAdjustSlider(
                  label: 'Exposure',
                  icon: Icons.exposure,
                  value: _videoExposure,
                  min: -1.0,
                  max: 1.0,
                  defaultVal: 0.0,
                  onChanged: (v) {
                    setState(() => _videoExposure = v);
                    _updateVideoAdjustments();
                  },
                ),
                _buildAdjustSlider(
                  label: 'Shadows',
                  icon: Icons.tonality,
                  value: _videoShadows,
                  min: 0.0,
                  max: 1.0,
                  defaultVal: 0.0,
                  onChanged: (v) {
                    setState(() => _videoShadows = v);
                    _updateVideoAdjustments();
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdjustSlider({
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required double defaultVal,
    required ValueChanged<double> onChanged,
  }) {
    // Normalized 0–1 for the display percentage (centred at default)
    final double pct;
    if (defaultVal == 0.0) {
      pct = ((value - min) / (max - min) * 100).roundToDouble();
    } else {
      pct = ((value - 1.0) * 100).roundToDouble(); // show +/- relative to 1.0
    }
    final String valLabel = defaultVal == 0.0
        ? pct.toStringAsFixed(0)
        : (pct >= 0 ? '+${pct.toStringAsFixed(0)}' : pct.toStringAsFixed(0));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white60, size: 15),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                valLabel,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              activeTrackColor: const Color(0xFF8B5CF6),
              inactiveTrackColor: const Color(0xFF2C2C2E),
              thumbColor: Colors.white,
              overlayColor: const Color(0xFF8B5CF6).withOpacity(0.2),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainEditor() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        // Playback Controls Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  _controller.runJavaScript("window.togglePlay()");
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ValueListenableBuilder<double>(
                valueListenable: _currentTimeNotifier,
                builder: (context, time, child) {
                  return Text(
                    '${_formatTime(time)} / ${_formatTime(_duration)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  );
                },
              ),
              const Spacer(),
              // Undo
              IconButton(
                icon: Icon(
                  Icons.undo,
                  color: _undoStack.isNotEmpty
                      ? Colors.white
                      : Colors.grey[700],
                  size: 20,
                ),
                onPressed: _undoStack.isNotEmpty ? _undo : null,
              ),
              // Redo
              IconButton(
                icon: Icon(
                  Icons.redo,
                  color: _redoStack.isNotEmpty
                      ? Colors.white
                      : Colors.grey[700],
                  size: 20,
                ),
                onPressed: _redoStack.isNotEmpty ? _redo : null,
              ),
              IconButton(
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () {
                  _sheetController.animateTo(
                    0.15,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Dual Timeline — synced scrollable thumbnail strip and word chips with playhead
        if (_selectedTab != 'Transform')
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 0.0,
            ), // Remove horizontal padding so scroll reaches edges
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: const Color(
                  0xFF1A1A1C,
                ), // Unified background for timeline
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double pixelsPerSecond = _kPixelsPerSecond;
                    final double totalWidth = _duration > 0
                        ? _duration * pixelsPerSecond
                        : constraints.maxWidth * 2;
                    final double halfScreenWidth = constraints.maxWidth / 2;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: (ScrollNotification notification) {
                            if (notification is ScrollStartNotification) {
                              if (notification.dragDetails != null) {
                                _isUserScrollingTimeline = true;
                              }
                            } else if (notification
                                is ScrollUpdateNotification) {
                              if (_isUserScrollingTimeline && _duration > 0) {
                                final double scrollOffset =
                                    _timelineScrollController.offset;
                                final double seekTime =
                                    (scrollOffset / _kPixelsPerSecond).clamp(
                                      0.0,
                                      _duration,
                                    );
                                _controller.runJavaScript(
                                  'window.seekTo($seekTime)',
                                );
                              }
                            } else if (notification is ScrollEndNotification) {
                              _isUserScrollingTimeline = false;
                            }
                            return true;
                          },
                          child: SingleChildScrollView(
                            controller: _timelineScrollController,
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.symmetric(
                              horizontal: halfScreenWidth,
                            ),
                            child: SizedBox(
                              width: totalWidth,
                              height:
                                  104, // 16 (ruler) + 4 + 60 (thumbnails) + 4 + 20 (caption blocks)
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Time Ruler
                                  SizedBox(
                                    height: 16,
                                    child: CustomPaint(
                                      size: Size(totalWidth, 16),
                                      painter: _TimeRulerPainter(
                                        duration: _duration > 0
                                            ? _duration
                                            : totalWidth / 100.0,
                                        pixelsPerSecond: pixelsPerSecond,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // Thumbnail filmstrip
                                  SizedBox(
                                    height: 60,
                                    child: Row(
                                      children: List.generate(20, (index) {
                                        if (_thumbnails.isNotEmpty &&
                                            index < _thumbnails.length) {
                                          final base64String =
                                              _thumbnails[index]
                                                  .split(',')
                                                  .last;
                                          return Container(
                                            width: totalWidth / 20,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              image: DecorationImage(
                                                image: MemoryImage(
                                                  base64Decode(base64String),
                                                ),
                                                fit: BoxFit.fitHeight,
                                                repeat: ImageRepeat.repeatX,
                                              ),
                                            ),
                                          );
                                        }
                                        return Container(
                                          width: totalWidth / 20,
                                          height: 60,
                                          color: const Color(
                                            0xFF8B5CF6,
                                          ).withOpacity(0.15),
                                        );
                                      }),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // Caption blocks — scroll with the video
                                  if (_captionsList.isNotEmpty)
                                    Builder(
                                      builder: (context) {
                                        return SizedBox(
                                          height: 20,
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: _captionsList.asMap().entries.map((
                                              entry,
                                            ) {
                                              final int index = entry.key;
                                              final s = entry.value;
                                              final double sStart =
                                                  (s['start'] as num)
                                                      .toDouble();
                                              final double sEnd =
                                                  (s['end'] as num).toDouble();
                                              final double lp =
                                                  sStart * pixelsPerSecond;
                                              final double bw =
                                                  (sEnd - sStart) *
                                                  pixelsPerSecond;

                                              return Positioned(
                                                left: lp,
                                                width: bw,
                                                height: 20,
                                                child: ValueListenableBuilder<double>(
                                                  valueListenable:
                                                      _currentTimeNotifier,
                                                  builder: (ctx, t, _) {
                                                    final bool isActive =
                                                        t >= sStart &&
                                                        t <= sEnd;
                                                    return GestureDetector(
                                                      onTap: () {
                                                        _controller.runJavaScript(
                                                          "window.seekTo($sStart)",
                                                        );
                                                        _showEditSegmentDialog(
                                                          index,
                                                          (s['text']
                                                                  as String? ??
                                                              ''),
                                                        );
                                                      },
                                                      child: Container(
                                                        decoration: BoxDecoration(
                                                          color: isActive
                                                              ? const Color(
                                                                  0xFF8B5CF6,
                                                                )
                                                              : const Color(
                                                                  0xFF2C2C2E,
                                                                ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                          border: Border.all(
                                                            color: isActive
                                                                ? Colors.white70
                                                                : Colors
                                                                      .transparent,
                                                            width: 1.0,
                                                          ),
                                                        ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          (s['text']
                                                                      as String? ??
                                                                  '')
                                                              .replaceAll(
                                                                '\n',
                                                                ' ',
                                                              ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Fixed Center Playhead
                        Positioned(
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 2,
                            color: Colors.white,
                            child: Stack(
                              alignment: Alignment.topCenter,
                              children: [
                                Positioned(
                                  top: 0,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),

        // Bottom Tab Row
        _buildBottomTabs(),
      ],
    );
  }


  Widget _buildBottomTabs() {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    return SafeArea(
      bottom: false,
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 0.0,
          bottom: bottomPadding > 0 ? bottomPadding + 16.0 : 32.0,
        ),
        child: _selectedTab == 'Transform'
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.translate(
                    offset: const Offset(0, 15),
                    child: GestureDetector(
                      onTap: () {
                        _selectTab('Editor');
                        _sheetController.animateTo(
                          0.37,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 64,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8B5CF6).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
          children: [
            // + FAB
            GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Add option coming soon!'),
                  ),
                );
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFF2C2C2E),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.add, color: Colors.white, size: 24),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Tabs
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTabNavItem(Icons.closed_caption, 'Captions'),
                  _buildTabNavItem(Icons.grid_view, 'Style'),
                  _buildTabNavItem(Icons.transform, 'Transform'),
                  _buildTabNavItem(Icons.tune, 'Adjust'),
                  _buildTabNavItem(Icons.auto_awesome, 'AI'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectTab(String tab) {
    setState(() {
      _selectedTab = tab;
      _captionsEditMode = (tab == 'Transform');
    });

    // Enable drag/resize box in Transform and Captions tabs
    _controller.runJavaScript(
      'window.setCaptionsEditMode && window.setCaptionsEditMode($_captionsEditMode)',
    );
  }

  Widget _buildTabNavItem(IconData icon, String label) {
    final bool isActive = _selectedTab == label;

    return GestureDetector(
      onTap: () {
        if (label == 'Auto Trim' || label == 'AI') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$label is in progress, will be available soon.'),
            ),
          );
        } else if (label == 'Transform') {
          if (_selectedTab == 'Transform') {
            _selectTab('Captions');
            _sheetController.animateTo(
              0.88,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          } else {
            _selectTab('Transform');
            _sheetController.animateTo(
              0.15,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        } else if (label == 'Adjust') {
          if (_selectedTab == 'Adjust') {
            _selectTab('Editor');
            _sheetController.animateTo(
              0.37,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          } else {
            _selectTab('Adjust');
            // Stay at 0.35 so the video preview is always visible above the panel
            _sheetController.animateTo(
              0.37,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        } else {
          if (label == 'Captions') {
            if (_selectedTab == 'Captions') {
              _selectTab('');
              _sheetController.animateTo(
                0.37,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            } else {
              _selectTab('Captions');
              _sheetController.animateTo(
                0.88,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          } else {
            _selectTab(label);
            _sheetController.animateTo(
              0.88,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF8B5CF6).withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: isActive ? const Color(0xFF8B5CF6) : Colors.white70,
              size: 26,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleSelectionOverlay() {
    return Container(
      color: const Color(0xFF151517),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Text(
                'Choose Your Style',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.4,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _templates.length,
                  itemBuilder: (context, index) {
                    final t = _templates[index];
                    return GestureDetector(
                      onTap: () {
                        _setStyle(t['id']!);
                        _startCaptionPipeline();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1C),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFF2C2C2E)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FractionalTranslation(
                              translation: const Offset(-0.05, 0),
                              child: Transform.scale(
                                scale: 1.10,
                                child: Image.asset(
                                  'assets/gifs/${t['id']}.gif',
                                  fit: BoxFit.cover,
                                  alignment: t['id'] == 'typewriter-pro'
                                      ? const Alignment(0, 0.37)
                                      : const Alignment(0, 0.06),
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        color: Colors.black26,
                                        child: const Center(
                                          child: Icon(
                                            Icons.broken_image,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.8),
                                    ],
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  t['name']!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscribingOverlay() {
    if (_pipelineStatus != CaptionPipelineStatus.uploading &&
        _pipelineStatus != CaptionPipelineStatus.processing &&
        _pipelineStatus != CaptionPipelineStatus.error) {
      return const SizedBox.shrink();
    }

    final bool isError = _pipelineStatus == CaptionPipelineStatus.error;
    final bool isUploading = _pipelineStatus == CaptionPipelineStatus.uploading;

    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Text(
                isError
                    ? 'Transcription Failed'
                    : (isUploading ? 'Uploading Video' : 'Transcribing'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: Text(
                  isError
                      ? (_pipelineErrorMessage ?? 'An unknown error occurred.')
                      : (isUploading
                            ? 'Please wait while we upload your video.'
                            : 'Your video is being transcribed. This process might take 2-3 minutes.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ),
              const Spacer(),
              if (!isError) ...[
                // Rounded-square video thumbnail with bounding progress arc
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer bounding progress arc
                    if (isUploading)
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: CustomPaint(
                          painter: RoundedRectProgressPainter(
                            progress: _uploadProgress.clamp(0.0, 99.0) / 100.0,
                            strokeWidth: 4.0,
                            color: const Color(0xFF8B5CF6),
                            borderRadius: 26.0,
                          ),
                        ),
                      ),
                    // Inner video thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox(
                        width: 130,
                        height: 130,
                        child:
                            _previewVideoController != null &&
                                _previewVideoController!.value.isInitialized
                            ? FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width:
                                      _previewVideoController!.value.size.width,
                                  height: _previewVideoController!
                                      .value
                                      .size
                                      .height,
                                  child: VideoPlayer(_previewVideoController!),
                                ),
                              )
                            : _thumbnails.isNotEmpty
                            ? Image.memory(
                                base64Decode(_thumbnails.first.split(',').last),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              )
                            : Container(
                                color: const Color(0xFF2C2C2E),
                                child: const Icon(
                                  Icons.video_file,
                                  color: Colors.grey,
                                  size: 48,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Percentage text only, not bold
                if (isUploading)
                  Text(
                    '${_uploadProgress.clamp(0.0, 99.0).toInt()}%',
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
              ] else ...[
                // Error icon
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 64,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  onPressed: _retryPipeline,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text(
                    'Retry',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: _cancelPipeline,
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    color: Colors.grey,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportingOverlay() {
    if (!_isExporting) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const Text(
                'Exporting Video',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40.0),
                child: Text(
                  'Please wait while we render and save your video. This might take a few minutes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ),
              const Spacer(),
              // Rounded-square video thumbnail with bounding progress arc
              Stack(
                alignment: Alignment.center,
                children: [
                  // Outer bounding progress arc
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: CustomPaint(
                      painter: RoundedRectProgressPainter(
                        progress: _exportProgress.clamp(0.0, 99.0) / 100.0,
                        strokeWidth: 4.0,
                        color: const Color(0xFF8B5CF6),
                        borderRadius: 26.0,
                      ),
                    ),
                  ),
                  // Inner video thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      width: 130,
                      height: 130,
                      child:
                          _previewVideoController != null &&
                              _previewVideoController!.value.isInitialized
                          ? FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width:
                                    _previewVideoController!.value.size.width,
                                height:
                                    _previewVideoController!.value.size.height,
                                child: VideoPlayer(_previewVideoController!),
                              ),
                            )
                          : _thumbnails.isNotEmpty
                          ? Image.memory(
                              base64Decode(_thumbnails.first.split(',').last),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : Container(
                              color: const Color(0xFF2C2C2E),
                              child: const Icon(
                                Icons.video_file,
                                color: Colors.grey,
                                size: 48,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Percentage/Status text
              Text(
                '${_exportProgress.clamp(0.0, 100.0).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStyleCaptionPreview() {
    return Container(
      color: Colors.black,
      child: ValueListenableBuilder<double>(
        valueListenable: _currentTimeNotifier,
        builder: (context, currentTime, _) {
          // Find current caption segment
          Map<String, dynamic>? currentSeg;
          for (final seg in _captionsList) {
            final start = (seg['start'] as num?)?.toDouble() ?? 0.0;
            final end = (seg['end'] as num?)?.toDouble() ?? 0.0;
            if (currentTime >= start && currentTime <= end) {
              currentSeg = Map<String, dynamic>.from(seg as Map);
              break;
            }
          }

          if (currentSeg == null || currentSeg['words'] == null) {
            if (_captionsList.isNotEmpty) {
              currentSeg = Map<String, dynamic>.from(
                _captionsList.first as Map,
              );
            } else {
              currentSeg = {
                'start': 0.0,
                'end': 999.0,
                'words': [
                  {'word': 'PREVIEW', 'start': 0.0, 'end': 999.0},
                  {'word': 'STYLE', 'start': 0.0, 'end': 999.0},
                ],
              };
            }
          }

          final words = currentSeg['words'] as List;

          // Group words into rows of _wordsPerLine
          final rows = <List>[];
          for (int i = 0; i < words.length; i += _wordsPerLine) {
            rows.add(
              words.sublist(i, (i + _wordsPerLine).clamp(0, words.length)),
            );
          }

          // Show only the last _maxLinesPerFrame rows
          final visibleRows = rows.length > _maxLinesPerFrame
              ? rows.sublist(rows.length - _maxLinesPerFrame)
              : rows;

          final textColor = _customTextColor ?? Colors.white;
          final emphColor = _customEmphasisColor ?? const Color(0xFFFFD700);

          final mainAxis = _customTextAlign == 'left'
              ? MainAxisAlignment.start
              : _customTextAlign == 'right'
              ? MainAxisAlignment.end
              : MainAxisAlignment.center;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: visibleRows.map((rowWords) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: mainAxis,
                    children: rowWords.map<Widget>((w) {
                      final word = (w['word'] as String? ?? '').toUpperCase();
                      final wordStart = (w['start'] as num?)?.toDouble() ?? 0.0;
                      final wordEnd = (w['end'] as num?)?.toDouble() ?? 0.0;
                      final isActive =
                          currentTime >= wordStart && currentTime <= wordEnd;

                      final color = isActive
                          ? emphColor.withValues(alpha: _customTextOpacity)
                          : textColor.withValues(alpha: _customTextOpacity);

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Text(
                          word,
                          style: TextStyle(
                            fontFamily: _customFontFamily,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: color,
                            shadows: const [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 6,
                                offset: Offset(2, 2),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStyleEditor() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF151517),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          const Padding(
            padding: EdgeInsets.only(top: 12.0, bottom: 4.0),
            child: SizedBox(
              width: 36,
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFF3A3A3C),
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
          ),
          // Tabs
          SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildEditorTab('Template'),
                _buildEditorTab('Color'),
                _buildEditorTab('Font'),
                _buildEditorTab('Breaks'),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),

          // Content Area
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildEditorContent(),
              ),
            ),
          ),

          // Bottom Bar
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 8.0,
                bottom: 12.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Cancel
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2C2C2E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () {
                      _selectTab('Editor');
                      _sheetController.animateTo(
                        0.37,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  // Undo / Redo
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.undo,
                          color: _styleUndoStack.isNotEmpty
                              ? Colors.white
                              : Colors.grey[700],
                        ),
                        onPressed: _styleUndoStack.isNotEmpty
                            ? _undoStyle
                            : null,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          Icons.redo,
                          color: _styleRedoStack.isNotEmpty
                              ? Colors.white
                              : Colors.grey[700],
                        ),
                        onPressed: _styleRedoStack.isNotEmpty
                            ? _redoStyle
                            : null,
                      ),
                    ],
                  ),
                  // Apply
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () {
                      _selectTab('Editor');
                      _sheetController.animateTo(
                        0.37,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: const Text(
                      'Apply',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullScreenCaptionsEditor() {
    return Container(
      color: const Color(0xFF151517),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 24.0),
              child: Text(
                'Edit Captions',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10, height: 1),

            // List of segments
            Expanded(
              child: _captionsList.isEmpty
                  ? const Center(
                      child: Text(
                        'No captions available. Generate captions first.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ValueListenableBuilder<double>(
                      valueListenable: _currentTimeNotifier,
                      builder: (context, time, child) {
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          itemCount: _captionsList.length,
                          itemBuilder: (context, index) {
                            final segment = _captionsList[index];
                            final text = segment['text'] as String? ?? '';
                            final start = (segment['start'] as num).toDouble();
                            final end = (segment['end'] as num).toDouble();
                            final bool isActive = time >= start && time <= end;

                            return Card(
                              color: const Color(0xFF1E1E22),
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isActive
                                      ? const Color(0xFF8B5CF6)
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                title: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${_formatTime(start)} - ${_formatTime(end)}',
                                      style: const TextStyle(
                                        color: Color(0xFF8B5CF6),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.grey,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        _controller.runJavaScript(
                                          "window.seekTo($start)",
                                        );
                                        _showEditSegmentDialog(index, text);
                                      },
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Text(
                                    text,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                onTap: () {
                                  // Seek video to the segment start when tapped
                                  _controller.runJavaScript(
                                    "window.seekTo($start)",
                                  );
                                  _showEditSegmentDialog(index, text);
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),

            // Fixed bottom center "Done" button
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 24.0),
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    _selectTab('Editor');
                    _sheetController.animateTo(
                      0.37,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 64,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorTab(String label) {
    bool isActive = _styleEditorTab == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _styleEditorTab = label;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 24),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFF8B5CF6) : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildEditorContent() {
    switch (_styleEditorTab) {
      case 'Template':
        return _buildTemplateTab();
      case 'Color':
        return _buildColorTab();
      case 'Font':
        return _buildFontTab();
      case 'Breaks':
        return _buildBreaksTab();
      default:
        return Container();
    }
  }

  // --- TEMPLATE TAB ---
  Widget _buildTemplateTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTemplateCard(
          'hormozi-style',
          'Hormozi Style',
          'YELLOW',
          isLite: false,
        ),
        const SizedBox(height: 12),
        _buildTemplateCard(
          'ali-abdaal',
          'Ali Abdaal',
          'Clean Highlight',
          isLite: false,
        ),
        const SizedBox(height: 12),
        _buildTemplateCard('mr-beast', 'Mr. Beast', 'BOUNCE', isLite: false),
        const SizedBox(height: 12),
        _buildTemplateCard(
          'karaoke-flow',
          'Karaoke Flow',
          'KARAOKE',
          isLite: false,
        ),
        const SizedBox(height: 12),
        _buildTemplateCard('pulse-wave', 'Pulse Wave', 'PULSE', isLite: false),
        const SizedBox(height: 12),
        _buildTemplateCard(
          'typewriter-pro',
          'Typewriter Pro',
          'TYPEWRITER',
          isLite: false,
        ),
        const SizedBox(height: 12),
        _buildTemplateCard(
          'neon-glow',
          'Neon Glow',
          'NEON GLOW',
          isLite: false,
        ),
        const SizedBox(height: 12),
        _buildTemplateCard(
          'impact-bounce',
          'Impact Bounce',
          'IMPACT',
          isLite: false,
        ),
        const SizedBox(height: 12),
        _buildTemplateCard(
          'minimalist-bg',
          'Minimalist Overlay',
          'MINIMALIST',
          isLite: false,
        ),
      ],
    );
  }

  // --- BREAKS TAB ---
  Widget _buildBreaksTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Line Breaks',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Control how words are grouped per line and how many lines appear at once.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 24),

        // Words per line
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WORDS PER LINE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'How many words fit on one line',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_wordsPerLine',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(8, (i) {
                  final val = i + 1;
                  final isSelected = _wordsPerLine == val;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _pushStyleUndoState();
                        setState(() => _wordsPerLine = val);
                        _updateCustomStyles();
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF8B5CF6)
                              : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? null
                              : Border.all(color: Colors.white12),
                        ),
                        child: Center(
                          child: Text(
                            '$val',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Max lines per frame
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MAX LINES PER FRAME',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Max lines visible at once',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_maxLinesPerFrame',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final val = i + 1;
                  final isSelected = _maxLinesPerFrame == val;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _pushStyleUndoState();
                        setState(() => _maxLinesPerFrame = val);
                        _updateCustomStyles();
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF8B5CF6)
                              : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? null
                              : Border.all(color: Colors.white12),
                        ),
                        child: Center(
                          child: Text(
                            '$val',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPillBtn(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF8B5CF6) : const Color(0xFF222225),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  Widget _buildTemplateCard(
    String id,
    String name,
    String previewText, {
    bool isLite = false,
  }) {
    bool isSelected = _selectedTemplate == id;
    return GestureDetector(
      onTap: () => _setStyle(id),
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF222225),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: const Color(0xFF8B5CF6), width: 2)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FractionalTranslation(
              translation: const Offset(-0.05, 0),
              child: Transform.scale(
                scale: 1.10,
                child: Image.asset(
                  'assets/gifs/$id.gif',
                  fit: BoxFit.cover,
                  alignment: id == 'typewriter-pro'
                      ? const Alignment(0, 0.37)
                      : const Alignment(0, 0.06),
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (isLite)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    border: Border.all(color: Color(0xFF8B5CF6)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'LITE',
                    style: TextStyle(
                      color: Color(0xFF8B5CF6),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- COLOR TAB ---
  Widget _buildColorTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Standard Colors',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 4),
        const Text(
          'Apply colors to elements on your video',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 16),

        // TEXT COLOR Block
        GestureDetector(
          onTap: () {
            _showColorPickerModal(
              'Text Color',
              _customTextColor ?? Colors.white,
              (color) {
                _pushStyleUndoState();
                setState(() => _customTextColor = color);
                _updateCustomStyles();
              },
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TEXT COLOR',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Standard color for all captions',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _customTextColor ?? Colors.grey[800],
                    borderRadius: BorderRadius.circular(4),
                    border: _customTextColor == null
                        ? Border.all(color: Colors.grey)
                        : null,
                  ),
                  child: _customTextColor == null
                      ? const Icon(
                          Icons.color_lens,
                          size: 16,
                          color: Colors.grey,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // EMPHASIS COLOR Block
        GestureDetector(
          onTap: () {
            _showColorPickerModal(
              'Emphasis Color',
              _customEmphasisColor ?? const Color(0xFF8B5CF6),
              (color) {
                _pushStyleUndoState();
                setState(() => _customEmphasisColor = color);
                _updateCustomStyles();
              },
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'EMPHASIS COLOR',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Color for emphasized words',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _customEmphasisColor ?? Colors.grey[800],
                    borderRadius: BorderRadius.circular(4),
                    border: _customEmphasisColor == null
                        ? Border.all(color: Colors.grey)
                        : null,
                  ),
                  child: _customEmphasisColor == null
                      ? const Icon(
                          Icons.color_lens,
                          size: 16,
                          color: Colors.grey,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showColorPickerModal(
    String title,
    Color currentColor,
    Function(Color) onColorChanged,
  ) {
    Color tempColor = currentColor;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151517),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: tempColor,
              onColorChanged: (color) {
                tempColor = color;
              },
              pickerAreaHeightPercent: 0.8,
              enableAlpha: false,
              displayThumbColor: true,
              paletteType: PaletteType.hsvWithHue,
              labelTypes: const [],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text(
                'Apply',
                style: TextStyle(color: Color(0xFF8B5CF6)),
              ),
              onPressed: () {
                onColorChanged(tempColor);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionBox(
    String topText,
    String bottomText, {
    Color? colorContent,
    IconData? iconContent,
  }) {
    return Column(
      children: [
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF222225),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: colorContent != null
                ? Container(width: 20, height: 20, color: colorContent)
                : iconContent != null
                ? Icon(iconContent, color: Colors.white, size: 20)
                : Text(
                    topText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          bottomText,
          style: const TextStyle(color: Colors.grey, fontSize: 10),
        ),
      ],
    );
  }

  // --- FONT TAB ---
  Widget _buildFontTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Font', style: TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 4),
        const Text(
          'Select the font for your captions and adjust font properties.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 16),

        // Font List (Grid of Fonts)
        Container(
          height: 180,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // 2 rows
              childAspectRatio: 0.8, // height/width ratio
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _popularFonts.length,
            itemBuilder: (context, index) {
              final fontName = _popularFonts[index];
              return _buildFontCard(
                'Aa',
                fontName,
                _customFontFamily == fontName,
                onTap: () {
                  _pushStyleUndoState();
                  setState(() => _customFontFamily = fontName);
                  _updateCustomStyles();
                },
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        const Text(
          'ATTRIBUTES',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildAlignBtn('Left', Icons.format_align_left)),
            const SizedBox(width: 8),
            Expanded(
              child: _buildAlignBtn('Center', Icons.format_align_center),
            ),
            const SizedBox(width: 8),
            Expanded(child: _buildAlignBtn('Right', Icons.format_align_right)),
            const SizedBox(width: 8),
            Expanded(
              child: _buildAlignBtn('Random', Icons.format_align_justify),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlignBtn(String alignment, IconData icon) {
    bool isActive = _customTextAlign == alignment.toLowerCase();
    return GestureDetector(
      onTap: () {
        _pushStyleUndoState();
        setState(() => _customTextAlign = alignment.toLowerCase());
        _updateCustomStyles();
      },
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF8B5CF6) : const Color(0xFF222225),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(child: Icon(icon, color: Colors.white, size: 20)),
      ),
    );
  }

  Widget _buildFontCard(
    String preview,
    String name,
    bool isActive, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 60,
            width: 60,
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF8B5CF6)
                  : const Color(0xFF222225),
              borderRadius: BorderRadius.circular(12),
              border: isActive
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
            ),
            child: Center(
              child: Text(
                preview,
                style: TextStyle(
                  fontFamily: name,
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey,
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPurpleBtn(String label, bool isActive) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF8B5CF6) : const Color(0xFF222225),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // Helper for Action Box with purple background override
  Widget _buildActionBoxWithPurpleOverride(
    String topText,
    String bottomText, {
    IconData? iconContent,
    bool isPurple = false,
  }) {
    return Column(
      children: [
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: isPurple ? const Color(0xFF8B5CF6) : const Color(0xFF222225),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: iconContent != null
                ? Icon(iconContent, color: Colors.white, size: 20)
                : Text(
                    topText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          bottomText,
          style: const TextStyle(color: Colors.grey, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildNavItem(IconData icon, String label) {
    final bool isActive = label == 'Captions'
        ? (_selectedTab == 'Captions' || _selectedTab == 'Editor')
        : _selectedTab == label;
    return GestureDetector(
      onTap: () {
        if (label == 'Auto Trim' || label == 'Zoom') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Work is in progress, will be available soon.'),
            ),
          );
        } else {
          if (label == 'Captions') {
            if (_selectedTab == 'Captions') {
              _selectTab('Editor');
            } else {
              _selectTab('Captions');
            }
          } else {
            _selectTab(label);
          }
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isActive ? const Color(0xFF8B5CF6) : Colors.grey,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeRulerPainter extends CustomPainter {
  final double duration;
  final double pixelsPerSecond;

  _TimeRulerPainter({required this.duration, required this.pixelsPerSecond});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint tickPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.0;

    final Paint majorTickPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.5;

    final TextStyle labelStyle = const TextStyle(
      color: Colors.white54,
      fontSize: 9,
      fontFamily: 'monospace',
    );

    // Draw minor ticks every 0.5s and major ticks every 1s
    const double minorInterval = 0.5;
    int totalTicks = (duration / minorInterval).ceil() + 1;

    for (int i = 0; i <= totalTicks; i++) {
      final double t = i * minorInterval;
      final double x = t * pixelsPerSecond;
      if (x > size.width) break;

      final bool isMajor = (i % 2 == 0); // every 1s
      final double tickHeight = isMajor
          ? size.height * 0.6
          : size.height * 0.35;
      final Paint paint = isMajor ? majorTickPaint : tickPaint;

      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - tickHeight),
        paint,
      );

      if (isMajor) {
        final int secs = (t).round();
        final String label = '${secs}s';
        final TextPainter tp = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 2, 0));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimeRulerPainter oldDelegate) {
    return oldDelegate.duration != duration ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond;
  }
}

class RoundedRectProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color color;
  final double borderRadius;

  RoundedRectProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().first;
    final extractPath = metrics.extractPath(0, metrics.length * progress);

    canvas.drawPath(extractPath, paint);
  }

  @override
  bool shouldRepaint(covariant RoundedRectProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.color != color ||
        oldDelegate.borderRadius != borderRadius;
  }
}
