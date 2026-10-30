import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/space/space_api.dart';

final spaceApiProvider = Provider<SpaceApi>(
  (ref) => SpaceApi(ref.watch(jellyfinHttpProvider)),
);
