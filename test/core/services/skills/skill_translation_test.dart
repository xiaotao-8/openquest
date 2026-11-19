import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/extension_entity_store.dart';
import 'package:Kelivo/core/models/skill_record.dart';
import 'package:Kelivo/core/services/skills/skill_translation_service.dart';
import 'package:Kelivo/core/services/skills/skills_service.dart';

const _englishSkillMd = '''
---
name: pdf-tools
description: Extract text and tables from PDF files with pdfplumber.
---
# PDF Tools
''';

const _chineseSkillMd = '''
---
name: 品牌规范
description: 公司品牌视觉规范，主色与字体要求。
---
# 品牌规范
''';

void main() {
  group('needsTranslation', () {
    test('english text needs translation', () {
      expect(
        SkillTranslationService.needsTranslation('Extract text from PDFs'),
        isTrue,
      );
    });

    test('chinese text does not', () {
      expect(SkillTranslationService.needsTranslation('品牌规范'), isFalse);
      expect(
        SkillTranslationService.needsTranslation('Extract 提取 text'),
        isFalse,
      );
    });

    test('empty and symbol-only text does not', () {
      expect(SkillTranslationService.needsTranslation(''), isFalse);
      expect(SkillTranslationService.needsTranslation('123 ---'), isFalse);
    });
  });

  group('parseResult', () {
    test('bare json', () {
      final parsed = SkillTranslationService.parseResult(
        '{"name":"PDF工具","description":"提取文本"}',
      );
      expect(parsed?.name, 'PDF工具');
      expect(parsed?.description, '提取文本');
    });

    test('fenced json with prose', () {
      final parsed = SkillTranslationService.parseResult(
        '好的：\n```json\n{"name":"PDF工具","description":"提取文本"}\n```',
      );
      expect(parsed?.name, 'PDF工具');
    });

    test('garbage returns null', () {
      expect(SkillTranslationService.parseResult('no json here'), isNull);
      expect(
        SkillTranslationService.parseResult('{"name":"","description":""}'),
        isNull,
      );
    });
  });

  test('SkillRecord json round-trips translation fields', () {
    final record = SkillRecord(
      id: 'x',
      source: SkillSource.paste,
      installedAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      translatedName: '译名',
      translatedDescription: '译文说明',
      translationSourceHash: 'abc12345',
    );
    final restored = SkillRecord.fromJson(record.toJson());
    expect(restored.translatedName, '译名');
    expect(restored.translatedDescription, '译文说明');
    expect(restored.translationSourceHash, 'abc12345');
  });

  group('translateMissing', () {
    late AppDatabase database;
    late ExtensionEntityStore store;
    late Directory tmp;
    late SkillsService service;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      store = ExtensionEntityStore(database);
      await database.customSelect('SELECT 1;').getSingle();
      tmp = await Directory.systemTemp.createTemp('skill_translation_');
      service = SkillsService(
        store: store,
        skillsDirectory: Directory(p.join(tmp.path, 'skills')),
      );
      await service.loaded;
    });

    tearDown(() async {
      service.dispose();
      await database.close();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('translates english skills once and caches on the record', () async {
      await service.importFromText(_englishSkillMd);
      await service.importFromText(_chineseSkillMd);
      final english = service.skills.firstWhere((s) => s.name == 'pdf-tools');
      expect(SkillTranslationService.isStale(english), isTrue);

      var calls = 0;
      await SkillTranslationService.instance.translateMissing(service, (
        prompt,
      ) async {
        calls++;
        expect(prompt, contains('pdf-tools'));
        return '{"name":"PDF工具箱","description":"用 pdfplumber 从 PDF 文件中提取文本和表格。"}';
      });

      // Only the English skill is translated; the Chinese one is skipped.
      expect(calls, 1);
      final updated = service.skills.firstWhere((s) => s.name == 'pdf-tools');
      expect(updated.record.translatedName, 'PDF工具箱');
      expect(
        updated.record.translationSourceHash,
        SkillTranslationService.sourceHash(updated),
      );
      expect(SkillTranslationService.isStale(updated), isFalse);
      expect(updated.displayName(chineseUi: true), 'PDF工具箱');
      expect(updated.displayName(chineseUi: false), 'pdf-tools');
      expect(
        updated.displayDescription(chineseUi: true),
        '用 pdfplumber 从 PDF 文件中提取文本和表格。',
      );

      // Second run: cache is fresh, no further model calls.
      await SkillTranslationService.instance.translateMissing(service, (
        prompt,
      ) async {
        calls++;
        return '{}';
      });
      expect(calls, 1);
    });

    test('translator failure leaves the skill untouched', () async {
      await service.importFromText(_englishSkillMd);
      await SkillTranslationService.instance.translateMissing(service, (
        prompt,
      ) async {
        throw StateError('model unavailable');
      });
      final skill = service.skills.single;
      expect(skill.record.translatedName, isNull);
      expect(SkillTranslationService.isStale(skill), isTrue);
    });
  });
}
