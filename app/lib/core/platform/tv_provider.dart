import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_info.dart';

/// Il dispositivo è una Android TV. Dove non c'è un `BuildContext` con
/// `FormFactorScope` (router, controller): nei test si sostituisce.
final androidTvProvider = Provider<bool>((ref) => isAndroidTv);
