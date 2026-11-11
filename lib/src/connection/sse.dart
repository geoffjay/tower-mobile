/// Incremental HTTP/1.1 response + Server-Sent Events parser.
///
/// The tower feed (`GET /v1/events`) is a chunked `text/event-stream`.
/// This turns the raw socket bytes into [SseFrame]s without an HTTP
/// client dependency. Pure: no sockets, so it is unit-testable.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'connection.dart' show ConnectionError;

/// One dispatched SSE event: `event:`, `id:` and the joined `data:` lines.
class SseFrame {
  const SseFrame({this.event, this.id, required this.data});

  final String? event;
  final String? id;
  final String data;
}

/// Parse [raw] socket bytes (status line, headers, then a chunked or
/// identity body) into SSE frames. Throws [ConnectionError] on a non-200
/// status or a malformed chunk.
Stream<SseFrame> parseSse(Stream<List<int>> raw) async* {
  final body = _BodyDecoder();
  final line = <int>[];
  String? event;
  String? id;
  final data = <String>[];

  SseFrame? dispatch() {
    if (data.isEmpty && event == null) return null;
    final f = SseFrame(event: event, id: id, data: data.join('\n'));
    event = null;
    data.clear();
    return f;
  }

  await for (final chunk in raw) {
    final bytes = body.add(chunk);
    if (body.headDone && body.status != 200) {
      throw ConnectionError('event feed refused: HTTP ${body.status}');
    }
    for (final b in bytes) {
      if (b != 0x0A) {
        line.add(b);
        continue;
      }
      var text = utf8.decode(line, allowMalformed: true);
      line.clear();
      if (text.endsWith('\r')) text = text.substring(0, text.length - 1);
      if (text.isEmpty) {
        final f = dispatch();
        if (f != null) yield f;
      } else if (!text.startsWith(':')) {
        final i = text.indexOf(':');
        final field = i < 0 ? text : text.substring(0, i);
        var value = i < 0 ? '' : text.substring(i + 1);
        if (value.startsWith(' ')) value = value.substring(1);
        switch (field) {
          case 'event':
            event = value;
          case 'id':
            id = value;
          case 'data':
            data.add(value);
        }
      }
    }
    if (body.done) return;
  }
}

/// Strips the HTTP head and decodes a chunked body incrementally.
class _BodyDecoder {
  final List<int> _buf = [];
  bool headDone = false;
  bool done = false;
  int status = 0;
  bool _chunked = false;

  /// -1: expecting a size line; >0: bytes left in the chunk; 0: expecting
  /// the CRLF that ends the chunk.
  int _remaining = -1;

  List<int> add(List<int> data) {
    _buf.addAll(data);
    final out = <int>[];
    if (!headDone) {
      final end = _find(_buf, const [13, 10, 13, 10]);
      if (end < 0) return out;
      final head = utf8.decode(_buf.sublist(0, end), allowMalformed: true);
      final lines = head.split('\r\n');
      final parts = lines.first.split(' ');
      status = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      for (final l in lines.skip(1)) {
        final i = l.indexOf(':');
        if (i > 0 &&
            l.substring(0, i).toLowerCase() == 'transfer-encoding' &&
            l.substring(i + 1).toLowerCase().contains('chunked')) {
          _chunked = true;
        }
      }
      _buf.removeRange(0, end + 4);
      headDone = true;
    }
    if (status != 200) return out;
    if (!_chunked) {
      out.addAll(_buf);
      _buf.clear();
      return out;
    }
    while (!done) {
      if (_remaining < 0) {
        final i = _find(_buf, const [13, 10]);
        if (i < 0) break;
        final sizeText = ascii
            .decode(_buf.sublist(0, i), allowInvalid: true)
            .split(';')
            .first
            .trim();
        _buf.removeRange(0, i + 2);
        final size = int.tryParse(sizeText, radix: 16);
        if (size == null) throw ConnectionError('bad chunk size "$sizeText"');
        if (size == 0) {
          done = true;
        } else {
          _remaining = size;
        }
      } else if (_remaining > 0) {
        if (_buf.isEmpty) break;
        final n = math.min(_remaining, _buf.length);
        out.addAll(_buf.getRange(0, n));
        _buf.removeRange(0, n);
        _remaining -= n;
      } else {
        if (_buf.length < 2) break;
        _buf.removeRange(0, 2);
        _remaining = -1;
      }
    }
    return out;
  }
}

int _find(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i <= hay.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
