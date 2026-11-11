import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tower_mobile/src/connection/connection.dart';
import 'package:tower_mobile/src/connection/sse.dart';

List<int> _chunk(String s) {
  final b = utf8.encode(s);
  return [...ascii.encode('${b.length.toRadixString(16)}\r\n'), ...b, 13, 10];
}

const _head =
    'HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n'
    'transfer-encoding: chunked\r\n\r\n';

/// Re-slice [bytes] into [size]-byte pieces, as a socket may deliver them.
Stream<List<int>> _sliced(List<int> bytes, int size) async* {
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size);
  }
}

void main() {
  test('frames survive arbitrary socket splits, incl. mid UTF-8 and mid-chunk',
      () async {
    final wire = [
      ...ascii.encode(_head),
      ..._chunk(': keep-alive\n\n'),
      ..._chunk('id: 7\nevent: tower-batch\ndata: {"a":"é"}\ndata: {"b":2}\n\n'),
      ..._chunk('event: tower-batch\r\ndata: x\r\n\r\n'),
      ...ascii.encode('0\r\n\r\n'),
    ];
    for (final size in [1, 3, 1000]) {
      final frames = await parseSse(_sliced(wire, size)).toList();
      expect(frames, hasLength(2), reason: 'slice size $size');
      expect(frames[0].event, 'tower-batch');
      expect(frames[0].id, '7');
      expect(frames[0].data, '{"a":"é"}\n{"b":2}');
      expect(frames[1].data, 'x');
    }
  });

  test('an event split across two chunks is one frame', () async {
    final wire = [
      ...ascii.encode(_head),
      ..._chunk('event: tower-batch\ndata: hel'),
      ..._chunk('lo\n\n'),
    ];
    final frames = await parseSse(_sliced(wire, 7)).toList();
    expect(frames.single.data, 'hello');
  });

  test('a non-200 status fails the stream', () async {
    final wire = ascii.encode(
      'HTTP/1.1 401 Unauthorized\r\ncontent-length: 0\r\n\r\n',
    );
    expect(parseSse(_sliced(wire, 5)).toList(), throwsA(isA<ConnectionError>()));
  });
}
