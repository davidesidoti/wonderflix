import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/downloads/downloads_api.dart';

final downloadsApiProvider = Provider<DownloadsApi>(
  (ref) => DownloadsApi(ref.watch(jellyfinHttpProvider)),
);
