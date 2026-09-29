import 'dart:convert';
import 'dart:io';

/// File di log a rotazione: `wonderflix.log` più fino a [maxFiles] - 1 file
/// precedenti (`wonderflix.1.log` è il più recente). Scrittura sincrona,
/// così le ultime righe prima di un crash restano sul disco.
///
/// Non lancia mai: un problema col disco non deve fermare l'app.
class RotatingFileSink {
  RotatingFileSink(
    this.directory, {
    this.baseName = 'wonderflix',
    this.maxBytes = 2 * 1024 * 1024,
    this.maxFiles = 5,
  });

  final Directory directory;
  final String baseName;
  final int maxBytes;
  final int maxFiles;

  /// Il file su cui si sta scrivendo.
  File get current => _file(0);

  File _file(int index) => File('${directory.path}${Platform.pathSeparator}'
      '${index == 0 ? '$baseName.log' : '$baseName.$index.log'}');

  void write(String text) {
    try {
      final bytes = utf8.encode(text);
      directory.createSync(recursive: true);
      final file = current;
      final size = file.existsSync() ? file.lengthSync() : 0;
      if (size > 0 && size + bytes.length > maxBytes) {
        try {
          _rotate();
        } on FileSystemException {
          // File bloccato (antivirus, editor): si continua ad aggiungere al
          // file attuale, anche oltre il massimo, e si riprova alla riga dopo.
        }
      }
      current.writeAsBytesSync(bytes, mode: FileMode.append);
    } on FileSystemException {
      // Riga persa: meglio che un errore mentre si registra un errore.
    }
  }

  /// Prima sposta il file attuale in un nome temporaneo: se non si può
  /// (file bloccato) non si cancella né si sposta nient'altro.
  void _rotate() {
    final rotating = File('${directory.path}${Platform.pathSeparator}'
        '$baseName.rotating.log');
    current.renameSync(rotating.path);
    final oldest = _file(maxFiles - 1);
    if (maxFiles > 1 && oldest.existsSync()) oldest.deleteSync();
    for (var i = maxFiles - 2; i >= 1; i--) {
      final file = _file(i);
      if (file.existsSync()) file.renameSync(_file(i + 1).path);
    }
    if (maxFiles > 1) {
      rotating.renameSync(_file(1).path);
    } else {
      rotating.deleteSync();
    }
  }
}
