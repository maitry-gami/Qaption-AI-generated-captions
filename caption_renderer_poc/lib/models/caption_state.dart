// Data models and state management for the caption generation pipeline.
//
// These models mirror the backend API response structure so the same JSON
// can be reused for both WebView preview and Remotion-based video export.

/// Represents the current status of the caption generation pipeline.
enum CaptionPipelineStatus {
  /// No video selected yet.
  idle,

  /// Video has been picked from device storage.
  videoSelected,

  /// Video is being uploaded to the backend.
  uploading,

  /// Backend is processing the video and generating captions.
  processing,

  /// Captions have been successfully generated and stored.
  success,

  /// An error occurred at some stage of the pipeline.
  error,
}

/// Settings for the transcription API request.
class TranscriptionSettings {
  final String model;
  final String translationType;
  final int linesPerCaption;
  final String? language;
  final String? targetLanguage;
  final String maxWords;

  const TranscriptionSettings({
    this.model = 'small',
    this.translationType = 'original',
    this.linesPerCaption = 2,
    this.language,
    this.targetLanguage,
    this.maxWords = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'model': model,
      'translationType': translationType,
      'linesPerCaption': linesPerCaption,
      if (language != null) 'language': language,
      if (targetLanguage != null) 'targetLanguage': targetLanguage,
      if (maxWords.isNotEmpty) 'maxWords': maxWords,
    };
  }
}

/// A single word with precise timing data for synchronized rendering.
class CaptionWord {
  final String word;
  final double start;
  final double end;

  const CaptionWord({
    required this.word,
    required this.start,
    required this.end,
  });

  factory CaptionWord.fromJson(Map<String, dynamic> json) {
    return CaptionWord(
      word: json['word'] as String,
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'word': word,
    'start': start,
    'end': end,
  };
}

/// A caption segment containing text and word-level timing.
class CaptionSegment {
  final double start;
  final double end;
  final String text;
  final List<CaptionWord> words;

  const CaptionSegment({
    required this.start,
    required this.end,
    required this.text,
    required this.words,
  });

  factory CaptionSegment.fromJson(Map<String, dynamic> json) {
    return CaptionSegment(
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
      text: json['text'] as String,
      words: (json['words'] as List<dynamic>?)
              ?.map((w) => CaptionWord.fromJson(w as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'text': text,
    'words': words.map((w) => w.toJson()).toList(),
  };
}

/// Complete caption result from the backend.
///
/// This structure is designed to be serializable to JSON so it can be
/// passed directly to the Remotion export pipeline.
class CaptionResult {
  final bool success;
  final List<CaptionSegment> segments;
  final String? srt;
  final String? engine;
  final String? error;

  const CaptionResult({
    required this.success,
    this.segments = const [],
    this.srt,
    this.engine,
    this.error,
  });

  factory CaptionResult.fromJson(Map<String, dynamic> json) {
    return CaptionResult(
      success: json['success'] as bool? ?? false,
      segments: (json['segments'] as List<dynamic>?)
              ?.map((s) => CaptionSegment.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      srt: json['srt'] as String?,
      engine: json['engine'] as String?,
      error: json['error'] as String?,
    );
  }

  /// Serializes to JSON format compatible with the Remotion renderer.
  /// This is the same format served at `/captions.json` for the WebView.
  Map<String, dynamic> toJson() => {
    'success': success,
    'segments': segments.map((s) => s.toJson()).toList(),
    if (srt != null) 'srt': srt,
    if (engine != null) 'engine': engine,
    if (error != null) 'error': error,
  };

  /// Flattened list of all words across all segments, used for the
  /// lyrics bar and word-level highlighting in the Flutter UI.
  List<CaptionWord> get allWords {
    final words = <CaptionWord>[];
    for (final segment in segments) {
      words.addAll(segment.words);
    }
    return words;
  }
}

/// Typed exception for caption API errors.
class CaptionApiException implements Exception {
  final CaptionErrorKind kind;
  final String message;
  final int? statusCode;

  const CaptionApiException({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'CaptionApiException($kind): $message';
}

/// Classification of caption API errors for retry decisions.
enum CaptionErrorKind {
  /// Request timed out (retryable).
  timeout,

  /// Network connectivity issue (retryable).
  networkError,

  /// Server returned 5xx (retryable).
  serverError,

  /// Server returned 4xx (not retryable).
  clientError,

  /// Response could not be parsed (not retryable).
  invalidResponse,

  /// Unknown error.
  unknown,
}
