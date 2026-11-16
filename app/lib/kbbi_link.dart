library;

import 'open_url.dart';

const String kKbbiOfficialHost = 'https://kbbi.kemendikdasmen.go.id';

String kbbiEntryUrl(String word) =>
    '$kKbbiOfficialHost/entri/${Uri.encodeComponent(word.trim())}';

Future<bool> openKbbiOfficial(String word) => openExternalUrl(kbbiEntryUrl(word));
