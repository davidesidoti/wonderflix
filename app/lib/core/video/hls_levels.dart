/// Indice del livello HLS da tenere fisso: il primo che Jellyfin può servire
/// copiando il video. hls.js ordina i livelli mettendo SDR prima di PQ, e la
/// variante H.264 SDR di Jellyfin (`AllowVideoStreamCopy=false`) obbliga il
/// server a una transcodifica completa. Se nessuno copia, il primo.
int copyLevel(List<String> urls) {
  final index =
      urls.indexWhere((url) => !url.contains('AllowVideoStreamCopy=false'));
  return index < 0 ? 0 : index;
}
