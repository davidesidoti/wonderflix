// Service worker delle notifiche push (spec V §4.3): l'unico del sito, con lo
// scope della cartella del sito. Il plugin manda {"title","body","route","tag"};
// route è una rotta di GoRouter senza '#'.

// Subito attivo e padrone delle pagine aperte: navigate() vale solo per le
// finestre che controlla. Niente gestore 'fetch': le richieste vanno in rete.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = (event.data ? event.data.json() : null) || {};
  } catch (_) {
    // JSON rotto: la notifica si mostra lo stesso (userVisibleOnly).
  }
  event.waitUntil(
    self.registration.showNotification(data.title || 'WonderFlix', {
      body: data.body || '',
      tag: data.tag || undefined,
      data: { route: data.route || '/' },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const scope = self.registration.scope;
  const route = (event.notification.data && event.notification.data.route) || '/';
  // Il sito usa le rotte con '#'.
  const url = scope + '#' + route;
  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      const open = windows.find((client) => client.url.startsWith(scope));
      if (open) {
        await open.focus();
        try {
          await open.navigate(url);
          return;
        } catch (_) {
          // Una finestra non controllata non si sposta: se ne apre una.
        }
      }
      await self.clients.openWindow(url);
    })(),
  );
});
