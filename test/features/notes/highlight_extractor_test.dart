// 文件: test/features/notes/highlight_extractor_test.dart
// 作用: 验证 Quill Delta 中红字/下划线重点的最小解析规则。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/features/notes/models/note_highlight.dart';
import 'package:ruoke/src/features/notes/utils/highlight_extractor.dart';

void main() {
  test('只提取红字和下划线文字，双重格式拆成两条重点', () {
    final contentJson = jsonEncode([
      {'insert': '普通文本\n'},
      {
        'insert': '红字',
        'attributes': {'color': 'red'},
      },
      {
        'insert': '下划线',
        'attributes': {'underline': true},
      },
      {
        'insert': '红字下划线',
        'attributes': {'color': 'red', 'underline': true},
      },
    ]);

    final highlights = HighlightExtractor.extract(contentJson);

    expect(highlights, const [
      NoteHighlightDraft(kind: 'red', body: '红字'),
      NoteHighlightDraft(kind: 'underline', body: '下划线'),
      NoteHighlightDraft(kind: 'red', body: '红字下划线'),
      NoteHighlightDraft(kind: 'underline', body: '红字下划线'),
    ]);
  });

  test('空内容、普通文字和格式异常不会产生重点', () {
    expect(HighlightExtractor.extract(null), isEmpty);
    expect(HighlightExtractor.extract(''), isEmpty);
    expect(
      HighlightExtractor.extract(
        jsonEncode([
          {'insert': '普通文本'},
          {'insert': ''},
          {
            'insert': 123,
            'attributes': {'color': 'red'},
          },
        ]),
      ),
      isEmpty,
    );
  });

  test('Quill 工具栏生成的红色十六进制值会被识别为红字重点', () {
    final highlights = HighlightExtractor.extract(
      jsonEncode([
        {
          'insert': '实际红字',
          'attributes': {'color': '#FFF44336'},
        },
      ]),
    );

    expect(highlights, const [NoteHighlightDraft(kind: 'red', body: '实际红字')]);
  });

  test('非法 Delta JSON 或非数组结构会报告解析失败', () {
    expect(
      () => HighlightExtractor.extract('{invalid-json'),
      throwsFormatException,
    );
    expect(
      () => HighlightExtractor.extract('{"insert":"不是数组"}'),
      throwsFormatException,
    );
  });

  test('仅包含空格或换行的格式操作不会生成重点', () {
    final highlights = HighlightExtractor.extract(
      jsonEncode([
        {
          'insert': '   ',
          'attributes': {'color': 'red'},
        },
        {
          'insert': '\n',
          'attributes': {'underline': true},
        },
      ]),
    );

    expect(highlights, isEmpty);
  });
}
