import 'dart:io';
import 'package:dio/dio.dart';
import '../models/caption_state.dart';

/// Service for communicating with the caption generation backend.
///
/// Handles multipart video upload with progress tracking, caption generation,
/// and retry logic with exponential backoff.
class CaptionApiService {
  static const String _baseUrl =
      'https://awgw38j7f03qa8i601ykib1r.3.shreylink.in/';
  static const String _captionEndpoint = '/direct-caption';
  static const Duration _timeout = Duration(minutes: 10);
  static const int _maxRetries = 3;
  static const Duration _initialRetryDelay = Duration(seconds: 2);

  final Dio _dio;

  CaptionApiService()
      : _dio = Dio(BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: _timeout,
          sendTimeout: _timeout,
        ));

  /// Uploads a video file and generates captions with word-level timestamps.
  ///
  /// [videoFile] — The video file to transcribe.
  /// [settings] — Transcription configuration (model, language, etc.).
  /// [onUploadProgress] — Callback with upload percentage (0.0–100.0).
  ///
  /// Throws [CaptionApiException] on failure after exhausting retries.
  Future<CaptionResult> generateCaptions({
    required File videoFile,
    TranscriptionSettings settings = const TranscriptionSettings(),
    void Function(double percent)? onUploadProgress,
  }) async {
    return _executeWithRetry(
      () => _doGenerateCaptions(
        videoFile: videoFile,
        settings: settings,
        onUploadProgress: onUploadProgress,
      ),
    );
  }

  /// Core upload + caption generation request.
  Future<CaptionResult> _doGenerateCaptions({
    required File videoFile,
    required TranscriptionSettings settings,
    void Function(double percent)? onUploadProgress,
  }) async {
    final fileName = videoFile.path.split(Platform.pathSeparator).last;

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        videoFile.path,
        filename: fileName,
      ),
      'model': settings.model,
      'translationType': settings.translationType,
      'linesPerCaption': settings.linesPerCaption.toString(),
      if (settings.language != null) 'language': settings.language,
      if (settings.targetLanguage != null)
        'targetLanguage': settings.targetLanguage,
      if (settings.maxWords.isNotEmpty) 'maxWords': settings.maxWords,
    });

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _captionEndpoint,
        data: formData,
        options: Options(
          headers: {
            'Content-Type': 'multipart/form-data',
            'x-api-key': 'YOUR_API_KEY_HERE',
          },
          responseType: ResponseType.json,
        ),
        onSendProgress: (sent, total) {
          if (onUploadProgress != null && total > 0) {
            final percent = (sent / total) * 100.0;
            onUploadProgress(percent.clamp(0.0, 100.0));
          }
        },
      );

      final data = response.data;
      if (data == null) {
        throw const CaptionApiException(
          kind: CaptionErrorKind.invalidResponse,
          message: 'Backend returned null response body.',
        );
      }

      final result = CaptionResult.fromJson(data);
      if (!result.success) {
        throw CaptionApiException(
          kind: CaptionErrorKind.serverError,
          message: result.error ?? 'Backend indicated failure without details.',
        );
      }

      return result;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  /// Executes [action] with exponential backoff retry.
  ///
  /// Only retries on [CaptionErrorKind.timeout], [CaptionErrorKind.networkError],
  /// and [CaptionErrorKind.serverError]. Client errors and parse errors are
  /// thrown immediately.
  Future<CaptionResult> _executeWithRetry(
    Future<CaptionResult> Function() action,
  ) async {
    CaptionApiException? lastException;

    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        return await action();
      } on CaptionApiException catch (e) {
        lastException = e;

        // Only retry on transient errors
        if (!_isRetryable(e.kind)) {
          rethrow;
        }

        // Don't wait after the last attempt
        if (attempt < _maxRetries - 1) {
          final delay = _initialRetryDelay * (1 << attempt); // 2s, 4s, 8s
          print(
              'CaptionApiService: Attempt ${attempt + 1} failed (${e.kind}). '
              'Retrying in ${delay.inSeconds}s...');
          await Future.delayed(delay);
        }
      }
    }

    throw lastException ??
        const CaptionApiException(
          kind: CaptionErrorKind.unknown,
          message: 'All retry attempts exhausted.',
        );
  }

  /// Whether an error kind should trigger a retry.
  bool _isRetryable(CaptionErrorKind kind) {
    return kind == CaptionErrorKind.timeout ||
        kind == CaptionErrorKind.networkError ||
        kind == CaptionErrorKind.serverError;
  }

  /// Maps Dio-specific exceptions to our typed [CaptionApiException].
  CaptionApiException _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return CaptionApiException(
          kind: CaptionErrorKind.timeout,
          message:
              'Request timed out. The server may be overloaded or the video is too long.',
          statusCode: e.response?.statusCode,
        );

      case DioExceptionType.connectionError:
        return const CaptionApiException(
          kind: CaptionErrorKind.networkError,
          message:
              'Unable to reach the caption server. Check your internet connection.',
        );

      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode ?? 0;
        final responseData = e.response?.data;
        String message = 'Server error (HTTP $statusCode).';

        if (responseData is Map<String, dynamic>) {
          message = responseData['error'] as String? ??
              responseData['message'] as String? ??
              message;
        }

        return CaptionApiException(
          kind: statusCode >= 500
              ? CaptionErrorKind.serverError
              : CaptionErrorKind.clientError,
          message: message,
          statusCode: statusCode,
        );

      case DioExceptionType.cancel:
        return const CaptionApiException(
          kind: CaptionErrorKind.unknown,
          message: 'Request was cancelled.',
        );

      default:
        return CaptionApiException(
          kind: CaptionErrorKind.unknown,
          message: 'Error: ${e.error ?? e.message ?? "Unknown"} while connecting to $_baseUrl',
        );
    }
  }

  /// Cancels any in-flight requests and cleans up resources.
  void dispose() {
    _dio.close(force: true);
  }
}
