enum ImportField { lemma, pos, definition, example, translation, pronunciation, homograph }

class ImportExample {
  const ImportExample({required this.text, this.translation});

  final String text;
  final String? translation;
}

class ImportSense {
  const ImportSense({this.pos, required this.definition, this.examples = const []});

  final String? pos;
  final String definition;
  final List<ImportExample> examples;
}

class ImportEntry {
  const ImportEntry({
    required this.lemma,
    this.homographIndex = 1,
    this.pronunciation,
    this.senses = const [],
    this.firstRow = 0,
  });

  final String lemma;
  final int homographIndex;
  final String? pronunciation;
  final List<ImportSense> senses;

  final int firstRow;
}

class ImportIssue {
  const ImportIssue({required this.row, required this.message, this.warning = true});

  final int row;
  final String message;
  final bool warning;
}

class ImportResult {
  const ImportResult({required this.entries, required this.issues});

  final List<ImportEntry> entries;
  final List<ImportIssue> issues;
}

class DictImportOptions {
  const DictImportOptions({
    this.multiSeparator = '|',
    this.maxFileBytes = 150 * 1024 * 1024,
    this.maxRecords,
    this.maxLemmaLength = 100,
    this.maxSensesPerEntry = 50,
    this.maxExamplesPerSense = 50,
  });

  final String multiSeparator;
  final int maxFileBytes;

  final int? maxRecords;
  final int maxLemmaLength;
  final int maxSensesPerEntry;
  final int maxExamplesPerSense;
}

String dictFold(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String dictFoldLoose(String s) {

  final noHomograph = dictFold(s).replaceAll(RegExp(r'\(\d+\)\s*$'), '');

  return noHomograph.replaceAll(RegExp(r'[.\-\u00b7\s]+'), '');
}

String dictTidy(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
