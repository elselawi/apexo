import 'package:apexo/services/dicom/dicom_normalize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nameTokens — aggressive normalization', () {
    test('`LAST^FIRST^MIDDLE` reduces to {first, last, middle}', () {
      final tokens = nameTokens('Smith^John^Q');
      expect(tokens, {'smith', 'john', 'q'});
    });

    test('handles `First Last` (no caret)', () {
      expect(nameTokens('John Smith'), {'john', 'smith'});
    });

    test(
        '`Smith, John Q.` reduces to {smith, john, q} (punctuation stripped, Q kept)',
        () {
      expect(nameTokens('Smith, John Q.'), {'smith', 'john', 'q'});
    });

    test('`Dr John SMITH` strips honorific + case-folds', () {
      expect(nameTokens('Dr John SMITH'), {'john', 'smith'});
    });

    test('`SMITH^JOHN` == `john smith` (case + caret)', () {
      expect(nameTokens('SMITH^JOHN'), nameTokens('john smith'));
    });

    test(
        '`Smith^John^Q` == `Smith, John Q.` (same tokens incl. middle initial)',
        () {
      expect(nameTokens('Smith^John^Q'), nameTokens('Smith, John Q.'));
    });

    test('`Smith^John^Q` has 3 tokens (incl. middle initial Q)', () {
      expect(nameTokens('Smith^John^Q'), {'smith', 'john', 'q'});
    });

    test('strips `Mr`, `Mrs`, `Ms`, `Prof`', () {
      expect(nameTokens('Mr John Smith'), {'john', 'smith'});
      expect(nameTokens('Mrs Jane Doe'), {'jane', 'doe'});
      expect(nameTokens('Ms Mary Jones'), {'mary', 'jones'});
      expect(nameTokens('Prof Albert Einstein'), {'albert', 'einstein'});
    });

    test('strips Arabic honorifics `د.`, `د`, `استاذ`, `الاستاذ`', () {
      expect(nameTokens('د. أحمد محمد'), {'احمد', 'محمد'});
      expect(nameTokens('د أحمد'), {'احمد'});
      expect(nameTokens('استاذ خالد'), {'خالد'});
      expect(nameTokens('الاستاذ خالد'), {'خالد'});
    });

    test('Arabic normalization: `أ|إ → ا`', () {
      expect(nameTokens('أحمد'), nameTokens('احمد'));
      expect(nameTokens('إبراهيم'), nameTokens('ابراهيم'));
    });

    test('order-insensitive: `John Smith` == `Smith John`', () {
      expect(nameTokens('John Smith'), nameTokens('Smith John'));
    });

    test('empty string → empty set', () {
      expect(nameTokens(''), isEmpty);
    });

    test('whitespace-only string → empty set', () {
      expect(nameTokens('   '), isEmpty);
    });

    test('just punctuation/honorifics → empty set', () {
      expect(nameTokens('Dr.'), isEmpty);
      expect(nameTokens('Mr.,'), isEmpty);
    });

    test('collapses multiple spaces', () {
      expect(nameTokens('John   Smith'), {'john', 'smith'});
    });
  });

  group('nameSimilarity — Jaccard over token sets', () {
    test('identical names → 1.0', () {
      expect(nameSimilarity('John Smith', 'John Smith'), 1.0);
    });

    test('identical tokens, different order → 1.0', () {
      expect(nameSimilarity('John Smith', 'Smith John'), 1.0);
    });

    test('different formats, same name → 1.0', () {
      expect(nameSimilarity('SMITH^JOHN', 'John Smith'), 1.0);
    });

    test('no shared tokens → 0.0', () {
      expect(nameSimilarity('John Smith', 'Alice Brown'), 0.0);
    });

    test('one shared token of two → 1/3', () {
      // {john, smith} vs {john, brown} → intersection=1, union=3 → 0.333...
      expect(
        nameSimilarity('John Smith', 'John Brown'),
        closeTo(1 / 3, 0.001),
      );
    });

    test('both empty → 1.0 (treated as match)', () {
      expect(nameSimilarity('', ''), 1.0);
    });

    test('one empty, one non-empty → 0.0', () {
      expect(nameSimilarity('John', ''), 0.0);
      expect(nameSimilarity('', 'John'), 0.0);
    });

    test('Arabic name with/without honorific → 1.0', () {
      expect(nameSimilarity('د. أحمد محمد', 'احمد محمد'), 1.0);
    });
  });
}
