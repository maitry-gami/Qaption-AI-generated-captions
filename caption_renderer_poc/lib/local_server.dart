import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:mime/mime.dart';

/// Local HTTP server that serves web assets to the WebView.
///
/// Supports dynamic overrides for video and caption files so that
/// user-selected content can be served at the same URLs the Remotion
/// app already fetches, without modifying the JS bundle.
class LocalServer {
  HttpServer? _server;
  final int port = 8080;

  /// When set, requests to `/video.mp4` will serve this file from disk
  /// instead of the bundled asset.
  String? userVideoPath;

  /// When set, requests to `/captions.json` will return this JSON string
  /// instead of the bundled asset.
  String? captionJsonOverride;

  Future<void> start() async {
    final handler = const Pipeline()
        .addMiddleware((innerHandler) {
          return (request) async {
            final response = await innerHandler(request);
            return response.change(headers: {
              'Cross-Origin-Embedder-Policy': 'require-corp',
              'Cross-Origin-Opener-Policy': 'same-origin',
            });
          };
        })
        .addHandler(_assetHandler);

    _server = await io.serve(handler, InternetAddress.loopbackIPv4, port);
    print('Local server started at http://localhost:$port');
  }

  Future<Response> _assetHandler(Request request) async {
    try {
      String path = request.url.path;
      if (path.isEmpty || path == '/') {
        path = 'index.html';
      }

      // --- Dynamic overrides ---

      // Serve user-picked video from disk instead of bundled asset
      if (path == 'video.mp4' && userVideoPath != null) {
        return _serveFileFromDisk(userVideoPath!, request);
      }

      // Serve generated captions instead of bundled asset
      if (path == 'captions.json' && captionJsonOverride != null) {
        return Response.ok(
          captionJsonOverride!,
          headers: {
            'content-type': 'application/json',
            'cache-control': 'no-cache, no-store, must-revalidate',
          },
        );
      }

      // --- Fallback: serve bundled assets (original behavior) ---

      final assetPath = 'assets/web/$path';
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List();
      final mimeType = lookupMimeType(assetPath) ?? 'application/octet-stream';

      final rangeHeader = request.headers['range'];
      if (rangeHeader != null) {
        final rangeParts = rangeHeader.replaceFirst('bytes=', '').split('-');
        final start = int.parse(rangeParts[0]);
        final end = rangeParts.length > 1 && rangeParts[1].isNotEmpty
            ? int.parse(rangeParts[1])
            : bytes.length - 1;

        final length = end - start + 1;
        final rangeBytes = bytes.sublist(start, end + 1);

        return Response(
          206,
          body: rangeBytes,
          headers: {
            'content-type': mimeType,
            'content-range': 'bytes $start-$end/${bytes.length}',
            'content-length': length.toString(),
            'accept-ranges': 'bytes',
          },
        );
      }

      return Response.ok(
        bytes, 
        headers: {
          'content-type': mimeType,
          'accept-ranges': 'bytes',
          'content-length': bytes.length.toString(),
        }
      );
    } catch (e) {
      return Response.notFound('Not Found');
    }
  }

  /// Serves a file from the device filesystem with range request support.
  ///
  /// This is used for user-selected videos that aren't bundled in assets.
  Future<Response> _serveFileFromDisk(String filePath, Request request) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return Response.notFound('File not found');
      }

      final fileLength = await file.length();
      final mimeType = lookupMimeType(filePath) ?? 'video/mp4';

      final rangeHeader = request.headers['range'];
      if (rangeHeader != null) {
        final rangeParts = rangeHeader.replaceFirst('bytes=', '').split('-');
        final start = int.parse(rangeParts[0]);
        final end = rangeParts.length > 1 && rangeParts[1].isNotEmpty
            ? int.parse(rangeParts[1])
            : fileLength - 1;

        final length = end - start + 1;
        final stream = file.openRead(start, end + 1);

        return Response(
          206,
          body: stream,
          headers: {
            'content-type': mimeType,
            'content-range': 'bytes $start-$end/$fileLength',
            'content-length': length.toString(),
            'accept-ranges': 'bytes',
          },
        );
      }

      final stream = file.openRead();
      return Response.ok(
        stream,
        headers: {
          'content-type': mimeType,
          'accept-ranges': 'bytes',
          'content-length': fileLength.toString(),
        },
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error serving file: $e');
    }
  }

  void stop() {
    _server?.close();
  }
}
