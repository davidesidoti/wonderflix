import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/social/match_api.dart';

/// Gli endpoint del match del plugin (spec P §7.1).
final matchApiProvider =
    Provider<MatchApi>((ref) => MatchApi(ref.watch(jellyfinHttpProvider)));
