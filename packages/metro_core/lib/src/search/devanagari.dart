// Devanagari helpers for search: a Latin "skeleton" used only to *match*
// Hindi text against Latin text. It is never shown to users and never stored;
// Hindi names that the dataset does not have stay NULL.

bool isDevanagari(int rune) => rune >= 0x0900 && rune <= 0x097F;

bool hasDevanagari(String s) => s.runes.any(isDevanagari);

const _consonants = <int, String>{
  0x0915: 'k',
  0x0916: 'kh',
  0x0917: 'g',
  0x0918: 'gh',
  0x0919: 'n',
  0x091A: 'ch',
  0x091B: 'ch',
  0x091C: 'j',
  0x091D: 'jh',
  0x091E: 'n',
  0x091F: 't',
  0x0920: 'th',
  0x0921: 'd',
  0x0922: 'dh',
  0x0923: 'n',
  0x0924: 't',
  0x0925: 'th',
  0x0926: 'd',
  0x0927: 'dh',
  0x0928: 'n',
  0x092A: 'p',
  0x092B: 'f',
  0x092C: 'b',
  0x092D: 'bh',
  0x092E: 'm',
  0x092F: 'y',
  0x0930: 'r',
  0x0931: 'r',
  0x0932: 'l',
  0x0933: 'l',
  0x0935: 'v',
  0x0936: 'sh',
  0x0937: 'sh',
  0x0938: 's',
  0x0939: 'h',
};

const _independentVowels = <int, String>{
  0x0905: 'a',
  0x0906: 'aa',
  0x0907: 'i',
  0x0908: 'ii',
  0x0909: 'u',
  0x090A: 'uu',
  0x090B: 'ri',
  0x090F: 'e',
  0x0910: 'ai',
  0x0913: 'o',
  0x0914: 'au',
  0x0911: 'o',
  0x090D: 'e',
  0x090E: 'e',
  0x0912: 'o',
};

const _matras = <int, String>{
  0x093E: 'aa',
  0x093F: 'i',
  0x0940: 'ii',
  0x0941: 'u',
  0x0942: 'uu',
  0x0943: 'ri',
  0x0947: 'e',
  0x0948: 'ai',
  0x094B: 'o',
  0x094C: 'au',
  0x0949: 'o',
  0x0945: 'e',
  0x0946: 'e',
  0x094A: 'o',
};

const _virama = 0x094D;
const _anusvara = 0x0902;
const _visarga = 0x0903;

class _Syllable {
  _Syllable(this.onset, {this.vowel, this.inherent = false});

  String onset;
  String? vowel;
  bool inherent;
  String coda = '';

  bool get hasVowel => vowel != null || inherent;

  @override
  String toString() => '$onset${vowel ?? (inherent ? 'a' : '')}$coda';
}

/// Latin skeleton of one Devanagari word (already folded: no nukta, no
/// chandrabindu). Applies a simple schwa-deletion heuristic: the inherent "a"
/// is dropped at the end of a word and between two syllables that have vowels
/// (processed right to left), so "जनकपुरी" gives "janakpurii", not "janakapurii".
String transliterateDevanagariWord(String word) {
  final syl = <_Syllable>[];
  var afterVirama = false;
  for (final r in word.runes) {
    final c = _consonants[r];
    if (c != null) {
      if (afterVirama && syl.isNotEmpty) {
        syl.last.onset += c;
        syl.last.inherent = true;
      } else {
        syl.add(_Syllable(c, inherent: true));
      }
      afterVirama = false;
    } else if (r == _virama) {
      if (syl.isNotEmpty) syl.last.inherent = false;
      afterVirama = true;
    } else if (_matras.containsKey(r)) {
      if (syl.isNotEmpty) {
        syl.last
          ..vowel = _matras[r]
          ..inherent = false;
      }
      afterVirama = false;
    } else if (_independentVowels.containsKey(r)) {
      syl.add(_Syllable('', vowel: _independentVowels[r]));
      afterVirama = false;
    } else if (r == _anusvara) {
      if (syl.isNotEmpty) syl.last.coda += 'n';
      afterVirama = false;
    } else if (r == _visarga) {
      if (syl.isNotEmpty) syl.last.coda += 'h';
      afterVirama = false;
    } else if (!isDevanagari(r)) {
      // Latin letters/digits inside a Devanagari token pass through.
      syl.add(_Syllable(String.fromCharCode(r)));
      afterVirama = false;
    } else {
      afterVirama = false;
    }
  }
  if (syl.length > 1 && syl.last.inherent && syl.last.vowel == null) {
    syl.last.inherent = false;
  }
  for (var i = syl.length - 2; i > 0; i--) {
    if (syl[i].inherent &&
        syl[i].vowel == null &&
        syl[i - 1].hasVowel &&
        syl[i + 1].hasVowel) {
      syl[i].inherent = false;
    }
  }
  return syl.join();
}
