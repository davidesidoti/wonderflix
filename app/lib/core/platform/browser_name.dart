/// Nome del browser per la diagnostica e il nome del dispositivo su
/// Jellyfin. L'ordine conta: Edge dichiara anche Chrome, Chrome anche Safari.
String describeBrowser(String userAgent) {
  if (userAgent.contains('Edg/')) return 'Edge';
  if (userAgent.contains('Firefox/')) return 'Firefox';
  if (userAgent.contains('Chrome/')) return 'Chrome';
  if (userAgent.contains('Safari/')) return 'Safari';
  return 'Browser';
}
