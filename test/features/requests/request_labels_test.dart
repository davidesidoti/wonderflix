import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/request_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/requests_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('stagioni in ordine, quelle di fila unite', () {
    expect(formatSeasonList(const []), '');
    expect(formatSeasonList(const [3]), '3');
    expect(formatSeasonList(const [2, 1]), '1–2');
    expect(formatSeasonList(const [5, 1, 2, 3, 3]), '1–3, 5');
  });

  test('testo dello stato', () {
    String label(RequestStatus status, [double? progress]) => requestStatusLabel(
        l, testMediaRequest(status: status, progress: progress));

    expect(label(RequestStatus.pending), 'In attesa');
    expect(label(RequestStatus.approved), 'Approvata');
    expect(label(RequestStatus.downloading, 0.456), 'In arrivo · 46%');
    expect(label(RequestStatus.downloading), 'In arrivo');
    expect(label(RequestStatus.partial), 'In parte disponibile');
    expect(label(RequestStatus.available), 'Disponibile');
    expect(label(RequestStatus.declined), 'Rifiutata');
    expect(label(RequestStatus.failed), 'Non riuscita');
  });

  test('colore dello stato', () {
    expect(requestStatusColor(RequestStatus.pending), WfColors.gold);
    expect(requestStatusColor(RequestStatus.downloading), WfColors.gold);
    expect(requestStatusColor(RequestStatus.approved), WfColors.cream);
    expect(requestStatusColor(RequestStatus.partial), WfColors.online);
    expect(requestStatusColor(RequestStatus.available), WfColors.online);
    expect(requestStatusColor(RequestStatus.declined), WfColors.error);
    expect(requestStatusColor(RequestStatus.failed), WfColors.error);
  });
}
