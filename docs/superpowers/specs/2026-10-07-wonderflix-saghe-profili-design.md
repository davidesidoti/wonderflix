# WonderFlix — Spec K: saghe e profili

- **Data:** 2026-10-07
- **Stato:** approvato; piano 17a realizzato (`docs/superpowers/plans/2026-10-07-wonderflix-17a-saghe.md`), piano 17b realizzato (`docs/superpowers/plans/2026-10-08-wonderflix-17b-profili.md`), piano 17c realizzato (`docs/superpowers/plans/2026-10-08-wonderflix-17c-immagini.md`); release da fare
- **Ambito:** Spec K. Realizza due voci dell'idea 3 di `docs/IDEE.md` ("Funzioni escluse dallo Spec A"): **collezioni e saghe** (K1) e **profili "Chi guarda?"** (K2). K2 comprende anche le **immagini del profilo**, chieste durante il brainstorming. Delle altre voci dell'idea 3, il download offline resta in `docs/IDEE.md`. **HDR vero** e **firma del codice** escono dalla lista per scelta dell'utente.

## 1. Obiettivo

- **Saghe (K1).** Le 101 collezioni del server diventano visibili nell'app:
  - una pagina per ogni saga;
  - una riga "Fa parte di" nella scheda del film;
  - una vista "Saghe" nel catalogo Film;
  - le saghe nei risultati della ricerca.
- **Profili (K2).** Più persone usano WonderFlix sullo stesso PC, ognuna con il suo account Jellyfin:
  - all'avvio la schermata "Chi guarda?";
  - si cambia profilo senza rifare l'accesso;
  - l'immagine del profilo si sceglie da una galleria o da un file;
  - le immagini degli utenti prendono il posto delle iniziali in tutta l'app.

  Non sono profili alla Netflix dentro un solo account: su Jellyfin cronologia, preferiti e "Continua a guardare" sono dell'utente, quindi ogni profilo è un utente Jellyfin e "Aggiungi profilo" è l'accesso con un altro account. L'utente l'ha confermato dopo la prova a mano del piano 17b (2026-10-08).

## 2. Situazione di partenza

App 0.10.0, plugin 1.4.0.

### 2.1 Saghe

- **`ItemKind`** (`lib/core/jellyfin/item_models.dart`) non conosce le collezioni: un `BoxSet` diventa `other`. Una collezione aperta oggi finirebbe in `MovieDetailView` (dispatch in `item_detail_screen.dart`), con un "Riproduci" sulla collezione stessa.
- **`ItemQuery`** (`item_query.dart`) non ha `parentId`. `cardImageParams` chiede `PrimaryImageAspectRatio,Genres`.
- **Catalogo.** `CatalogScreen(kind)` mostra:
  - il titolo con il numero dei titoli;
  - `CatalogFiltersBar`, con ordinamento, genere, anno e visti;
  - una griglia di `PosterCard` caricata a pagine da 100.

  `CatalogController` non guarda `libraryRevisionProvider`.
- **Scheda del film.** `DetailHeader`, poi `CastRow` e `SimilarRow` (`detail_rows.dart`), costruite con `MediaRow` (`lib/ui/media_row.dart`).
- **Ricerca** (`search_controller.dart`):
  - attesa di 300 ms e almeno 2 caratteri;
  - tre chiamate in parallelo: film, serie, persone;
  - le sezioni Film, Serie, Persone, poi le richieste Seerr (`RequestablesSection`).
- **Immagini.** `ImageUrls` ha `poster`, `primaryOf`, `backdrop`, `logo`, `landscape` e `person`. Le immagini passano da `WfImage` (`lib/ui/wf_image.dart`): `CachedNetworkImage` con la cache `wonderflixImageCache`, che le tiene 30 giorni e al massimo 5000.
- **Revisioni.** `libraryRevisionProvider` cresce con `LibraryChanged` (dopo un'attesa di 5 s) e quando il WebSocket si ricollega. `userDataRevisionProvider` cresce con `UserDataChanged` e dopo il player.

### 2.2 Sessione

- **Una sola sessione.** `StoredSession{userId, accessToken}` sta sotto la chiave `wonderflix.session` (`lib/core/storage/session_store.dart`), con `flutter_secure_storage` 11.2.0.
  - Su Windows (`flutter_secure_storage_windows` 4.2.2) **tutte le chiavi stanno in un unico file JSON cifrato con DPAPI**: `%AppData%\it.wonderflix\WonderFlix\flutter_secure_storage.dat`, nella cartella dei dati dell'app. **Non** stanno nel Gestore credenziali di Windows.
  - Il commento di `SecureSessionStore`, quello di `sessionKeyFor` e `docs/RELEASING.md` dicevano il contrario: li ha corretti il piano 17b.
- **`SessionController`** ha quattro stati: `SessionStarting`, `SessionSignedOut({expired})`, `SessionUnreachable`, `SessionSignedIn(user)`. `restore()` parte da `WonderflixApp.initState` e dalla schermata "server non raggiungibile": ogni 15 s, e quando si preme il pulsante.
- **Router** (`lib/app/router.dart`). Le rotte d'ingresso sono `/splash`, `/login` e `/unreachable`. Con `SignedIn` si va a `/home` solo da una rotta d'ingresso; altrimenti si resta dove si è.
- **Login** (`login_screen.dart`):
  - password e, se il server lo permette, Quick Connect;
  - niente "Annulla";
  - il nome utente parte sempre vuoto.
- **Uscita** (`AuthService.logout`):
  1. `POST /Sessions/Logout`;
  2. token e sessione locale cancellati;
  3. stato `SignedOut`.

  Tutto il resto si azzera perché molti provider guardano `sessionControllerProvider` o `currentUserIdProvider`: WebSocket, party, canale del party, amici, cassetta, admin, catalogo, Home, scheda, La mia lista, coda. L'uscita **non** lascia il party in modo esplicito: lo chiude il token annullato.
- **DeviceId.** Un UUID v4 per installazione, salvato come `device_id` nelle preferenze. `ClientInfo` si crea una volta in `main.dart` e `JellyfinHttp` lo tiene `final`, quindi oggi il DeviceId non cambia mentre l'app gira. Il token invece è un campo che cambia. Il WebSocket legge l'intestazione `Authorization` al momento della connessione.
- **Istanza di sviluppo.** `WONDERFLIX_PROFILE` (`lib/core/device/dev_profile.dart`) separa:
  - la chiave della sessione (`wonderflix.session.<p>`);
  - il prefisso delle preferenze;
  - la cartella dei log;
  - il DeviceId (UUID v5 dal nome del PC e dall'istanza).
- **Preferenze locali** (`SharedPreferences`), oggi tutte del PC:
  - lingua e aspetto: `locale`, `appearance.motion`;
  - party: `party.lastMode`;
  - player: `player.volume`, `player.quality`, `player.hardwareDecoding`, `player.subtitleScale`, `player.autoSkipIntro`, `player.autoplayNext`;
  - Discord: `discord.enabled`, `discord.showTitle`, `discord.showPoster`;
  - finestra e dispositivo: `window_bounds`, `device_id`.
- **Menu dell'avatar** (`_UserMenu` in `lib/app/app_shell.dart`): Impostazioni, Amministrazione (solo per gli admin), Esci. L'avatar è l'iniziale in un cerchio dorato.
- **Impostazioni** (`settings_screen.dart`), sezioni: Lingua, Aspetto, Player, Lingue (del server), Discord, Account ("Accesso come" ed Esci), Supporto.

### 2.3 Avatar degli altri utenti

- **`MemberAvatar(name)`** (`lib/features/watch_party/party_badge.dart`) disegna l'iniziale. Si usa:
  - nella fila dei membri del party e nel suo menu;
  - nel pannello amici (`_PersonRow`);
  - nel menu degli inviti.
- **Altre iniziali:** `AdminUserLine` (`lib/features/admin/admin_widgets.dart`), nella scheda Sessioni dell'admin.
- **Dove il plugin manda l'id dell'utente:**
  - amici, richieste d'amicizia e ricerca utenti (`FriendEntry`, `PersonEntry`, `UserSearchResult`);
  - mittente della chat e delle reazioni (`StampedEvent`);
  - evento della richiesta d'amicizia (`SocialEvent.FromUserId`).
- **Dove arriva solo il nome:**
  - i membri del party, che vengono da SyncPlay;
  - gli inviti (`FromName`);
  - le richieste Seerr in attesa.
- **Immagini degli utenti:** nessun `ImageTag` viaggia oggi, e `ImageUrls` non ha un indirizzo per le immagini degli utenti.

### 2.4 Plugin 1.4.0

- **Rotte** sotto `WonderFlixWatchParty/`.
  - Info, Inbox e Requests hanno `[Authorize]`.
  - Friends, Parties e WatchParty hanno `Policies.SyncPlayHasAccess`.
  - I controller non rispondono mai 404, perché per l'app un 404 vuol dire "plugin assente".
- **`Info`** risponde `{Version, Protocol: 1, Features}`.
  - Le funzioni sono `friends`, `parties`, `inbox` e `queue`, più `requests` solo con Seerr configurato.
  - L'app le legge in `SocialAvailability` (`lib/features/social/social_providers.dart`).
- **Struttura.** I servizi di Jellyfin stanno dietro interfacce in `Hub\`, con le implementazioni in `Server\` (`JellyfinUserDirectory`, `JellyfinLibraryAccess`…). Si registrano in `PluginServiceRegistrator`.
- **Prove** con `FakeServer`, `FakeAuthorizationContext` e `InterfaceStub` (quest'ultimo per gli adattatori di `Server\`).
- **Collezioni e immagini degli utenti:** nessun codice del plugin le tocca.
- **Release:** in `docs/RELEASING.md`:
  1. versione nel csproj;
  2. `pack.sh`;
  3. tag `watch-party-plugin-vX.Y.Z`;
  4. voce in `manifest.json`.

  La versione è scritta anche in `InfoControllerTests.cs`.

## 3. Il server

Fatti raccolti il 2026-10-07, in sola lettura, dal database e dalle API con la chiave "Wonderflix".

### 3.1 Collezioni

- **Quante e dove.** Ci sono **101 BoxSet**, tutte nella cartella nascosta delle collezioni (`8679d105…`), create dai plugin "TMDb Box Sets" e "Auto Collections".
  - 98 hanno la locandina, 96 lo sfondo, 89 il logo.
  - Il loro ordine (`DisplayOrder`) è `PremiereDate`.
- **Film.**
  - 298 film stanno in almeno una saga, e 59 in più di una.
  - Quasi tutte le saghe hanno 2–3 film. Le più grandi sono:
    - "Marvel Universe" (64);
    - "Fast and Furious - Collezione" (10);
    - "Ferrero Cartoon" (10);
    - "Star Wars - Collezione" e "Star Wars Collection" (9 ciascuna: sono doppioni);
    - "Harry Potter - Collezione" (8).
  - Nelle collezioni non c'è nessuna serie.
- **Come sono collegati i film.** I film di una collezione sono i suoi `LinkedChildren` (nel JSON della collezione), non i suoi discendenti. Per questo `/Items/{film}/Ancestors` non mostra le collezioni.
- **Nessuna API di Jellyfin dice in quali collezioni sta un film.** Nessuna le elenca nemmeno, se non si conosce la cartella nascosta: `/Items?includeItemTypes=BoxSet&recursive=true`, la stessa con `searchTerm` e `/Search/Hints` danno 0, sia per l'admin sia per un utente normale.
- **La vista "Collezioni".** Tutti i 23 utenti hanno `DisplayCollectionsView` spento, quindi la vista non compare tra le loro.
- **Con l'id della cartella** le chiamate funzionano:
  - `/Items?parentId=<cartella>` dà le 101 collezioni anche a un utente normale;
  - `/Items?parentId=<collezione>` dà i film della collezione (provato su "Matrix - Collezione": 3 film).
- **La libreria "Collezioni2"** è una `CollectionFolder` con 102 elementi, invisibile agli utenti. Lo Spec K non la tocca.

### 3.2 Immagini degli utenti

- **Permessi.** Tutti i 23 utenti hanno `EnableUserPreferenceAccess`, quindi possono cambiare la propria immagine. Oggi solo 2 ne hanno una.
- **Lettura.** `GET /UserImage?userId=&tag=&format=` non chiede l'accesso (OpenAPI 10.11.9) e non ridimensiona: accetta solo `userId`, `tag` e `format`. Con il tag la cache dura un anno.
- **Scrittura.** `POST /UserImage?userId=` e `DELETE /UserImage?userId=` chiedono l'accesso, e rispondono 403 se l'utente non ha il permesso.
  - Il corpo del `POST` è l'immagine **in base64**, con `Content-Type` `image/jpeg` o `image/png` (altrimenti 400); risposta 204. Il tag cambia a ogni caricamento.
  - Il `DELETE` risponde 204 anche senza immagine.

  Verificato nel piano 17c sul sorgente di Jellyfin 10.11.9 (`ImageController`, in sola lettura).

## 4. Decisioni

| Tema | Decisione |
|---|---|
| Voci dell'idea 3 | collezioni e profili, con le immagini del profilo; il download offline resta in `docs/IDEE.md`; HDR e firma del codice esclusi per scelta dell'utente |
| Dove compaiono le saghe | pagina della saga, riga "Fa parte di" nella scheda del film, vista "Saghe" nel catalogo Film, ricerca; **niente** riga in Home |
| Dati delle saghe | **plugin 1.5.0**, `GET WonderFlixWatchParty/Collections` (§7.1) |
| Avvio con più profili | schermata **"Chi guarda?"** a ogni avvio; con un solo profilo si entra diretti, come oggi |
| Protezione dei profili | **nessuna**: niente PIN |
| Cambio di profilo | **dentro l'app**, senza riavviarla |
| DeviceId | **uno per profilo**, nuovo a ogni accesso, anche con "Accedi di nuovo" (§9.2) |
| Numero di profili | al massimo 5 |
| Immagine del profilo | si cambia dall'app, scegliendo da una galleria di 24 icone a tema cinema o da un file da ritagliare; si può togliere |
| Immagini degli altri | si vedono dovunque l'utente è noto; i tag li dà il **plugin 1.5.0**, `GET WonderFlixWatchParty/Users/Avatars` (§7.2), tranne nelle sessioni dell'admin, dove li dà Jellyfin (§10.5) |
| Release | plugin **1.5.0**; app **0.11.0 non obbligatoria** |

## 5. Perimetro

### Incluso

- **Plugin 1.5.0:** gli endpoint delle collezioni e degli avatar, e le funzioni `collections` e `avatars`.
- **Saghe (K1):**
  - `ItemKind.boxSet`;
  - la pagina `/collection/:id`;
  - la riga "Fa parte di";
  - la vista "Saghe" del catalogo;
  - le saghe nella ricerca.
- **Profili (K2):**
  - più profili salvati sul PC e la schermata "Chi guarda?";
  - aggiungere, cambiare e togliere un profilo;
  - un DeviceId per profilo;
  - le preferenze del profilo;
  - la migrazione della sessione di oggi.
- **Immagini (K2):**
  - la finestra dell'immagine del profilo, con galleria, file da ritagliare e rimozione;
  - `UserAvatar` al posto delle iniziali.

### Escluso

- Creare, modificare o cancellare collezioni dall'app.
- Sistemare i doppioni: si fa sul server.
- Una riga delle saghe in Home.
- "Guarda la saga insieme", cioè mettere tutta la saga nella coda del party.
- PIN dei profili, profili per bambini, più profili aperti nello stesso momento, avatar animati.
- Cambiare le immagini degli altri utenti, anche da admin.
- L'avatar nelle righe della cassetta per inviti e richieste Seerr: resta la locandina o l'icona di oggi. Lo stesso per le etichette delle reazioni.
- Download offline, HDR, firma del codice.

## 6. Architettura

```
jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/
  Api/CollectionsController.cs        GET WonderFlixWatchParty/Collections
  Api/AvatarsController.cs            GET WonderFlixWatchParty/Users/Avatars
  Hub/ICollectionDirectory.cs         le collezioni che un utente vede, con i loro film
  Hub/IUserAvatars.cs                 utenti per id o per nome, con il tag dell'immagine
  Server/JellyfinCollectionDirectory.cs   ICollectionManager, IUserManager, IImageProcessor
  Server/JellyfinUserAvatars.cs       IUserManager, IImageProcessor
  Protocol/CollectionDtos.cs, Protocol/AvatarDtos.cs
  Protocol/WatchPartyProtocol.cs      + "collections", "avatars"
lib/core/jellyfin/
  item_models.dart                    ItemKind.boxSet
  json_fields.dart                    + jellyfinIdKey (id confrontabili: senza trattini, minuscoli)
  library_api.dart                    + collectionItems (i titoli di una saga, senza ItemQuery.parentId)
  image_urls.dart                     + primaryWithTag(itemId, tag), + user(userId, tag)
  user_image_api.dart                 UserImageApi (POST in base64 e DELETE /UserImage) e ImageUpload
  admin_models.dart                   + SessionEntry.userImageTag (UserPrimaryImageTag di Jellyfin)
  client_info.dart                    + ClientInfo.copyWith(deviceId)
  jellyfin_http.dart                  setCredentials (token + DeviceId insieme), withCredentials (un profilo non attivo), post(contentType:)
lib/core/social/
  collections_api.dart, collections_models.dart   endpoint del plugin
  avatars_api.dart                    AvatarsApi e UserAvatarInfo: endpoint del plugin
  social_models.dart                  + PluginFeatures.collections, PluginFeatures.avatars
lib/core/storage/
  profile_store.dart                  StoredProfile, ProfileBook, ProfileStore, SecureProfileStore (con la migrazione), ProfileLimitException
  session_store.dart                  la sessione di prima della 0.11.0: la legge solo la migrazione
lib/core/device/dev_profile.dart      + profilesKeyFor, accanto a sessionKeyFor
lib/features/collections/
  collections_providers.dart          elenco in cache, indice film → saghe, film di una saga
  collections_logic.dart              funzioni pure: indice, ricerca, ordinamenti, titolo da proporre
  collection_screen.dart              pagina della saga e CollectionHeader
  collection_rows.dart                righe "Fa parte di"
  collection_card.dart                card di una saga (vista "Saghe" e ricerca)
  collections_grid.dart               vista "Saghe" del catalogo
  sagas_search_section.dart           sezione "Saghe" della ricerca
lib/features/catalog/
  catalog_navigation.dart             CatalogView (titoli | saghe), openMovies
  catalog_filters_bar.dart            FilterPicker, pubblico (anche per le saghe)
lib/features/detail/
  detail_header.dart                  DetailHeaderFrame e HeaderTitle, in comune con la pagina della saga
  item_detail_screen.dart             un BoxSet passa a /collection/<id> (context.replace)
lib/ui/
  media_row.dart                      MediaRow.onTitleTap (titolo come link)
  poster_card.dart                    PosterCard.markLabel e openable
lib/features/profiles/
  profiles_screen.dart                "Chi guarda?" e "Gestisci profili"
  profile_preferences.dart            ProfilePreferences e profilePreferencesProvider (§9.6)
  profile_switch.dart                 changeProfile e partyLeaveTimeout (§9.7)
  avatar_dialog.dart                  finestra dell'immagine (Avatar | Dal PC | Rimuovi): showAvatarDialog, avatarFilePickerProvider, avatarImageToolsProvider
  avatar_gallery.dart                 i 24 avatar e il disegno in PNG
  avatar_image.dart                   l'immagine dal PC: preparazione e ritaglio, in isolate (pacchetto image)
  avatar_cropper.dart                 il ritaglio quadrato: widget e conti
lib/features/social/
  avatars_provider.dart               AvatarLookup, AvatarImage, AvatarDirectory (i tag degli altri utenti, in cache), avatarDirectoryProvider, avatarImageProvider
  social_providers.dart               + SocialFeatures.collections, SocialFeatures.avatars
lib/features/watch_party/party_badge.dart   MemberAvatar: un uso di UserAvatar.lookup
lib/ui/user_avatar.dart               UserAvatar e UserAvatar.lookup
lib/ui/wf_confirm_dialog.dart         showWfConfirmDialog: Rimuovi, cambio di profilo nel party, conferme dell'admin
lib/features/auth/
  auth_service.dart                   i profili (§9); clientFor, isActive, updateStoredProfile, markProfileExpired (§10.4)
  session_controller.dart             i profili (§9); setProfileImage (§10.4)
  profiles_state.dart                 ProfilesState e profilesProvider: i profili per l'interfaccia
lib/app/providers.dart                profileStoreProvider al posto di sessionStoreProvider
lib/app/navigation.dart               collectionRoute, openCollection; itemRoute porta un BoxSet alla sua pagina
lib/app/router.dart                   + /profiles, /collection/:id, /movies?view=sagas
```

I nomi dei file sono quelli realizzati: delle saghe (K1) nel piano 17a, dei profili nel piano 17b, delle immagini nel piano 17c. Il 17c aggiunge i pacchetti `file_selector` (la finestra di Windows per scegliere il file) e `image` 4 (Dart puro, per lavorare l'immagine in un isolate). Le API seguono la forma di oggi: una classe sottile su `JellyfinHttp`, modelli con `fromJson` scritti a mano, niente codegen. Le letture del plugin sono tolleranti come in `json_fields.dart`.

## 7. Plugin 1.5.0

### 7.1 Collezioni

`GET WonderFlixWatchParty/Collections` è aperto a ogni utente che ha fatto l'accesso (`[Authorize]`): le saghe non dipendono dal watch party.

```json
{"Collections": [
  {"Id": "f2dad769a40265dd509bdc158f5c8b2c",
   "Name": "Matrix - Collezione",
   "SortName": "matrix - collezione",
   "PrimaryImageTag": "a48dab12a8094e7fcae43d4ae573109b",
   "DateCreated": "2026-05-01T10:00:00.0000000Z",
   "ItemIds": ["0088b3bf1b19ef2d962fa145c461538a", "bbd313bc922ab16278ca26167d51f291", "718742d5…"]},
  {"Id": "5a1f0c2e…",
   "Name": "Senza locandina",
   "SortName": "senza locandina",
   "DateCreated": "2026-05-01T10:00:00.0000000Z",
   "ItemIds": ["4c9d17aa…"]}
]}
```

- **Quali collezioni.** Quelle della cartella delle collezioni (`ICollectionManager.GetCollectionsFolder(false)`) che l'utente può vedere.
- **Quali film.** Gli elementi collegati alla collezione (`LinkedChildren`) che l'utente può vedere, cioè che stanno in una sua libreria e passano il controllo parentale.
  - L'ordine non conta: l'app riordina.
  - Una collezione senza film visibili non compare (la toglie il controller).
- **Come si legge.** L'adattatore (`JellyfinCollectionDirectory`, con `ICollectionManager`, `IUserManager` e `IImageProcessor`) chiama `GetChildren(user, true, new InternalItemsQuery())` sulla cartella e su ogni `BoxSet`: la stessa chiamata che Jellyfin fa per `GET /Items?parentId=…`, quindi con gli stessi filtri di visibilità (librerie e controllo parentale).
  - La query è nuova a ogni chiamata, perché `GetChildren` la modifica.
  - Senza utente (o con un id vuoto) o senza cartella l'elenco è vuoto, e la cartella non si crea mai.
- **Formato.** Gli id sono nel formato di Jellyfin: 32 caratteri esadecimali minuscoli, senza trattini (`Guid.ToString("N")`). Con le impostazioni JSON di Jellyfin (date con sette decimali e `Z`, valori nulli non scritti) `DateCreated` ha la forma `"2026-05-01T10:00:00.0000000Z"` e `PrimaryImageTag` **manca** se la collezione non ha la locandina. La forma non è stata letta byte per byte sul server, ma nella prova a mano del 2026-10-07 (piano 17a, Task 12) l'app ha letto senza problemi la risposta vera. L'app tratta un campo assente come `null`.
- **Casi particolari.**
  - Senza la cartella delle collezioni la risposta è `{"Collections": []}`.
  - Un errore inatteso dà 500, mai 404 (§2.4).
- **Peso:** circa 100 collezioni e 400 id, pochi KB.
- **Funzione:** `collections` è sempre in `Features`.
- **Prove.**
  - I test del plugin simulano `Folder` e `BoxSet` con delle sottoclassi, che danno figli fissi e registrano chi li chiede: provano che ogni lettura passa dall'utente, non la visibilità vera.
  - L'output del plugin con il token di un utente vero si è verificato nella prova a mano del 2026-10-07 (piano 17a, Task 12): saghe, righe, pagina e ricerca come previsto. Un utente che non vede una libreria, sul server, non c'è (§14): quel caso è coperto solo dai test del plugin.
- **Versione.** Il csproj è già a 1.5.0 (§7.3).

### 7.2 Avatar

`GET WonderFlixWatchParty/Users/Avatars?ids=<id,…>&names=<nome,…>` è aperto a ogni utente che ha fatto l'accesso (`[Authorize]`).

```json
{"Users": [{"UserId": "ab8240c5…", "Name": "viviroby", "ImageTag": "9f1c…"},
           {"UserId": "4135c572…", "Name": "mario"}]}
```

- **Parametri.** `ids` e `names` sono separati da virgole; gli spazi ai lati si tolgono e le voci vuote si ignorano.
  - Un id vale con o senza trattini (`Guid.TryParse`). Un id che non è un GUID (o il GUID vuoto) non è di nessuno: si ignora.
- **Quali utenti.** Solo quelli chiesti che esistono e non sono disattivati (`IsDisabled`).
  - Un nome si cerca senza badare alle maiuscole (`OrdinalIgnoreCase`, anche con le lettere non ASCII): in Jellyfin i nomi utente sono unici.
  - Un utente chiesto due volte (per id e per nome) compare una volta.
  - `Name` è il nome utente di Jellyfin; `UserId` è nel formato di Jellyfin (`Guid.ToString("N")`).
- **Come si legge.** L'adattatore (`JellyfinUserAvatars`, con `IUserManager` e `IImageProcessor`) elenca gli utenti **una volta per richiesta** (`UserListing`, come `JellyfinUserDirectory`: in 10.11.0 la proprietà `Users`, in 10.11.9 il metodo `GetUsers()`) e confronta id e nomi in memoria. Con Jellyfin 10.11.9 ogni `GetUserById` o `GetUserByName` è una query al database, e `GetUserByName` lancia con un nome vuoto (diventerebbe un 400).
- **Niente elenco completo:** il plugin risponde solo sugli utenti chiesti.
  - Una ricerca per nome conferma che un account esiste, anche nascosto. Il rischio è basso e si accetta: `/Users/Public` elenca già gli utenti non nascosti, e la ricerca utenti degli amici trova i nomi per sottostringa.
- **Limite:** al massimo 100 voci per chiamata, sommando id e nomi (dopo aver tolto le vuote; gli id che non sono GUID contano); oltre si ha 400, e gli utenti non si leggono.
- **Niente da cercare:** senza voci valide (nessun parametro, solo voci vuote, solo id che non sono GUID) la risposta è `{"Users": []}`, senza leggere gli utenti.
- **`ImageTag`** è `IImageProcessor.GetImageCacheTag` dell'utente, cioè il tag che Jellyfin mette in `PrimaryImageTag` nei suoi `UserDto` (da verificare con la build di prova, §14). Senza immagine è `null`, e con le impostazioni JSON di Jellyfin (valori nulli non scritti) **manca**, come `mario` nell'esempio. I test del protocollo usano `JsonSerializer.Serialize`, che invece scrive `null`; l'app tratta allo stesso modo il campo assente e `null`.
- **Errori:** un errore inatteso dà 500, mai 404 (§2.4).
- **Funzione:** `avatars` è sempre in `Features`.

### 7.3 Versione

- Il plugin passa a **1.5.0**; `Protocol` resta 1.
- Il csproj e `InfoControllerTests` sono già a 1.5.0 dal piano 17a, per la build di prova installata sul server. Tag, manifest e Catalogo si fanno con la release, dopo il merge del piano 17c (§15).
- La descrizione nel manifest si aggiorna con la release.
- Il manifest ha il changelog in italiano.

## 8. Saghe nell'app (K1)

### 8.1 Dati

- **`ItemKind.boxSet`.** Si legge da `"BoxSet"`. `itemRoute` porta una saga a `/collection/<id>`, da qualunque card o link. Se un link porta l'id di una saga a `/item/<id>` (la cassetta, il registro attività dell'admin), `ItemDetailScreen` appena legge un `BoxSet` mostra lo scheletro e sostituisce la rotta con `/collection/<id>` (`context.replace`, una volta sola): non mostra mai l'impaginazione di un film, e indietro non torna a `/item/<id>`.
- **Funzione `collections`.** `PluginFeatures.collections` e `SocialFeatures.collections`: non dipendono dal watch party (come `requests`).
- **`collectionsProvider`** legge `GET WonderFlixWatchParty/Collections` solo se il plugin ha la funzione `collections`. Senza la funzione l'elenco è vuoto e non parte nessuna chiamata. Il risultato è una lista non modificabile.
  - Si rilegge quando cresce `libraryRevisionProvider` e quando cambia l'utente.
  - È `autoDispose`, ma dopo una lettura riuscita resta in cache anche senza ascoltatori (`keepAlive`): la usano la scheda del film, il catalogo e la ricerca.
  - Un errore **non** resta in cache: si riprova quando qualcuno torna ad ascoltare.
  - Se la lettura fallisce:
    - per le righe della scheda e per la ricerca l'elenco è vuoto;
    - la vista "Saghe" mostra l'errore con "Riprova".
  - Nel registro: gli stati inattesi li scrive lo strato HTTP (502, 503 e 504 no, perché Jellyfin si sta riavviando). Il provider scrive solo il tipo dell'errore: come info per un `ApiException`, come avviso per ogni altro errore.
- **Modelli.** `CollectionSummary{id, name, sortName, primaryImageTag, dateCreated, itemIds}`, con `size` = i titoli distinti.
  - `fromJson` normalizza gli `ItemIds` con `jellyfinIdKey` (`lib/core/jellyfin/json_fields.dart`: senza trattini e in minuscolo) e toglie i doppioni.
  - Un `ItemIds` che non è un elenco (per esempio una stringa con le virgole) non è valido: vale come elenco vuoto.
  - Dall'elenco si costruisce l'indice `jellyfinIdKey(itemId) → saghe` (`collectionsByItemProvider`).
- **`collectionItemsProvider(id)`** legge i film della saga con `LibraryApi.collectionItems`: `GET /Items?userId&parentId=<saga>&sortBy=PremiereDate,ProductionYear,SortName&sortOrder=Ascending`, con `cardImageParams`, **senza** `recursive`. Guarda `libraryRevisionProvider` e `userDataRevisionProvider`. `ItemQuery` **non** ha il campo `parentId`: il catalogo non ne ha bisogno.
- **La saga** per la pagina (sfondo, logo, sinossi) si legge con `itemProvider(id)` (`GET /Items/{id}`), come la scheda di un titolo: non c'è un `collectionProvider`.

### 8.2 Pagina della saga (`/collection/:id`)

- **Rotta:** nella shell, con la stessa transizione delle schede (`detailPage`) e lo sfondo sotto la barra.
- **Testata:** `CollectionHeader`, costruita sulle parti che condivide con `DetailHeader`, in `detail_header.dart`: `DetailHeaderFrame` (altezza, gradienti, testi che sfumano salendo) e `HeaderTitle` (logo o nome). Non usa `DetailHeader` stesso, che ha preferiti, visto e trailer pensati per un titolo.
  - Lo sfondo (`backdrop`) e il logo; senza logo, il nome.
  - La riga "{n} film · {m} visti", dove m conta i film con `played`.
  - La sinossi della collezione, se c'è.
- **Pulsante principale.**
  - Il film proposto è il primo, nell'ordine di uscita, che non è stato visto.
  - Il pulsante dice **Riprendi "{titolo}"** se quel film è iniziato, altrimenti **Riproduci "{titolo}"**.
  - Se sono tutti visti, il pulsante è **Riproduci "{titolo}"** sul primo film.
  - Scorrendo, il pulsante passa nella barra in alto come nella scheda del film (`ShellHeaderPublisher`).
  - Nella barra l'etichetta è corta, come nella scheda del film ("Riprendi da 23:14" o "Riproduci", `primaryActionLabel`); il titolo del film sta solo nel pulsante grande della testata.
- **Elenco:** sotto la testata, la griglia dei film come `PosterCard` (avanzamento, visto, non visto), in ordine di uscita.
  - Una rilettura in background (cambia la libreria o i dati utente) tiene le locandine che c'erano.
  - Lo scheletro delle locandine compare solo quando i film si ricaricano dopo un errore ("Riprova").
- **Caricamento:** la pagina chiede la saga e i suoi film insieme, e resta lo scheletro finché i film non sono arrivati (o hanno fallito): così la testata entra già con il conteggio e il pulsante, e non salta.
  - Lo sfondo entra con la testata e resta dietro un errore successivo.
- **Errori:** caricamento ed errore con "Riprova" come nella scheda di un titolo. Una saga che non esiste più dà l'errore generico con "Riprova", come la pagina di un titolo: non c'è un testo "titolo non trovato". Il "Riprova" della pagina rilegge la saga e i suoi film. Se falliscono solo i film, la testata resta e sotto compare l'errore con "Riprova", che rilegge i film.

### 8.3 Righe "Fa parte di"

- **Dove:** in `MovieDetailView`, prima di "Simili". C'è una riga per ogni saga del film che ha almeno 2 film, cercate nell'indice (§8.1).
- **Ordine delle righe:** dalla saga più piccola alla più grande, quindi prima la più specifica ("Iron Man - Collezione" prima di "Marvel Universe"); a parità di dimensione, per nome.
- **Titolo:** "Fa parte di: {nome}" con una freccia (`LucideIcons.arrowRight`, `MediaRow.onTitleTap`). Il titolo è un link: apre la pagina della saga, anche con un clic sullo spazio tra il testo e la freccia.
- **Card:** i film della saga in ordine di uscita (`collectionItemsProvider`), come `PosterCard` alla larghezza di "Simili". Le saghe grandi (64 film) scorrono in orizzontale come le altre righe.
  - Il film aperto ha il bordo dorato sempre acceso e l'etichetta "Questo film" (`PosterCard.markLabel`).
  - Non si apre per niente (`PosterCard.openable: false`): niente clic, niente anteprima al passaggio del mouse, niente cursore da clic.
- **Errori:** finché carica, la riga non compare; un errore la nasconde, come "Simili".

### 8.4 Vista "Saghe" nel catalogo Film

- **Selettore.** In `/movies`, sotto il titolo, c'è il selettore **Film | Saghe** (`WfTabButton`, chiavi `catalog-view-titles` e `catalog-view-sagas`).
  - La scelta va nell'indirizzo: `/movies?view=sagas`. Il selettore usa `openMovies` (`catalog_navigation.dart`, con `CatalogView`), cioè `context.go` come le schede delle pagine Richieste e Amministrazione. Un valore di `view` sconosciuto vale come i film.
  - Senza la funzione `collections` il selettore non c'è, e `?view=sagas` mostra i film.
  - Le due viste hanno la stessa pagina (stessa chiave della rotta): passando da una all'altra non c'è una nuova transizione.
  - Tornando da Saghe a Film i filtri dei film ripartono da zero. Non è richiesto dalla spec, ma si accetta.
- **Contenuto della vista "Saghe":**
  - il titolo "FILM" con "{n} saghe" (il conteggio compare quando l'elenco ha delle saghe);
  - un campo di ricerca per nome;
  - l'ordinamento (menu `FilterPicker`): Nome (`SortName`), Numero di film (dal più grande), Data di aggiunta (dalla più recente); a parità, per nome e poi per id, così l'ordine è fisso;
  - una griglia di card (`CollectionCard`): locandina della saga (`ImageUrls.primaryWithTag`, con il tag), nome, "{n} film". Senza locandina c'è un'icona. Il clic apre la pagina della saga; non c'è l'anteprima al passaggio del mouse.

  La barra dei filtri dei film (generi, anni, visti) non c'è.
- **Ricerca e ordinamento** restano nello stato della vista, non nell'indirizzo. Una nuova ricerca o un nuovo ordine riportano la griglia in cima.
- **Niente pagine:** l'elenco è già tutto in cache.
- **Caricamento ed errore.**
  - Finché non c'è un elenco con delle saghe e la lettura è in corso, compare lo scheletro delle locandine (non "Nessuna saga", nemmeno quando la funzione del plugin passa da sconosciuta a nota). Lo stesso dopo "Riprova".
  - Un errore vince anche sull'elenco vuoto di prima: si vede l'errore con "Riprova", non "Nessuna saga". Con un elenco pieno di prima resta la griglia.
- **Vuoti:** "Nessuna saga"; con una ricerca, "Nessuna saga con questo nome".

### 8.5 Ricerca

- **Sezione "Saghe".** Con almeno 2 caratteri compare una sezione "Saghe" sopra i film, con le saghe il cui nome contiene il testo cercato. Sono delle `CollectionCard` in una fila che va a capo (`SagasSearchSection`).
- **Confronto:** senza badare a maiuscole e accenti (la stessa normalizzazione nel testo cercato e nel nome, `foldForSearch`). La normalizzazione:
  - porta in minuscolo e toglie gli spazi ai lati;
  - toglie anche i segni combinanti (U+0300–U+036F), quindi vale pure per le lettere scritte come lettera più segno;
  - sostituisce le lettere accentate comuni, i macron e: ø, æ, œ, ß, š, č, ž, ł;
  - **non** tocca le lettere polacche ć, ź, ś, ą, ę, ż.
- **Quante:** al massimo 12, in ordine di nome.
- **Quando si legge l'elenco:** appena si apre la schermata di ricerca (una chiamata, poi è in cache), non quando si scrive: così la sezione non arriva dopo i risultati. Poi il filtro lavora sull'elenco in cache (§8.1), senza chiamate in più. Senza saghe che corrispondono, la sezione non c'è.
- **"Nessun risultato"** non compare se la libreria non trova niente ma ci sono delle saghe.

## 9. Profili (K2)

### 9.1 Dati e migrazione

- **`StoredProfile`:** `userId`, `name`, `accessToken`, `deviceId`, `imageTag` (facoltativo), `lastUsedAt`, `expired`.
  - `name` è vuoto finché non si legge (il profilo migrato): "Chi guarda?" mostra "Profilo", e l'accesso non scrive un nome vuoto.
  - `expired` (nel file solo quando è vero): il server ha rifiutato il token (401). "Chi guarda?" mostra il profilo attenuato anche dopo un riavvio, senza una richiesta. Lo toglie un accesso riuscito o un `/Users/Me` riuscito.
- **`ProfileBook`** (immutabile) tiene i profili e `lastUserId`. **`ProfileStore`** (`SecureProfileStore`) salva una sola chiave, `wonderflix.profiles`, nello stesso `flutter_secure_storage` di oggi.
  - Contenuto: `{"version": 1, "profiles": […], "lastUserId": "…"}`.
  - I profili sono nell'ordine in cui sono stati aggiunti. Gli id si confrontano con `jellyfinIdKey` (senza trattini e in minuscolo).
  - Nell'istanza di sviluppo la chiave è `wonderflix.profiles.<p>` (`profilesKeyFor`, in `dev_profile.dart` accanto a `sessionKeyFor`).
  - **Lettura tollerante:** un profilo senza id, token o DeviceId si salta; i doppioni dello stesso utente e i profili oltre il quinto si scartano; un `lastUserId` che non è tra i profili non vale.
- **Dove stanno:** nel file `%AppData%\it.wonderflix\WonderFlix\flutter_secure_storage.dat`, cifrato con DPAPI (§2.2), come dice `docs/RELEASING.md`.
- **Massimo 5 profili.**
- **Migrazione** al primo avvio della 0.11.0, se c'è `wonderflix.session` e non c'è `wonderflix.profiles`:
  1. la sessione diventa il primo profilo, con il DeviceId di oggi (`device_id` delle preferenze, o quello dell'istanza di sviluppo);
  2. nome e tag dell'immagine si prendono al primo `/Users/Me` riuscito;
  3. `wonderflix.session` si cancella.

  `read()` non lancia mai. Se il salvataggio del profilo migrato fallisce, il profilo vale lo stesso in memoria e `wonderflix.session` resta: la migrazione si rifà al prossimo avvio solo se nel frattempo nessun salvataggio riesce. Se fallisce la cancellazione di `wonderflix.session`, va solo un avviso nel registro: con i profili salvati la lettura non migra più.
- **Chi aggiorna non rifà l'accesso:** il token resta legato allo stesso DeviceId.
- **DeviceId dei profili nuovi:** un UUID v4 nuovo a ogni accesso (§9.2). `device_id` resta nelle preferenze come DeviceId del profilo migrato, e non si usa per i profili nuovi.
- **File dei profili rovinato** (dati che non si capiscono): si comporta come oggi con una sessione illeggibile. I profili si considerano assenti, si va all'accesso e nel registro va un avviso. La chiave rovinata non si cancella: la sostituisce il primo salvataggio.
- **Storage che lancia in lettura** (vale anche per la sessione di prima della migrazione): si va all'accesso, ma un salvataggio non sovrascrive alla cieca. Il primo salvataggio rilegge lo storage: se lancia ancora non salva (l'errore va nel registro e i profili valgono in memoria); altrimenti tiene anche i profili salvati che mancano (davanti, finché ce ne stanno 5; vincono quelli nuovi, e il loro ultimo usato) e "Chi guarda?" li mostra subito.
  - **Copre solo i casi rari.** Su Windows `flutter_secure_storage_windows` 4.2.2 legge come vuoto un file che non riesce ad aprire (senza eccezione), e cancella un file che non riesce a decifrare o a leggere prima di lanciare. In quei casi i profili sono persi come con dati rovinati, e si rifà l'accesso.
- **Salvataggio fallito** durante la sessione: i profili valgono lo stesso in memoria per questa esecuzione, l'errore va nel registro e la sessione non si rompe. Un `restore()` nella stessa esecuzione (il "Riprova" del server irraggiungibile) tiene i profili in memoria e riprova a salvarli, invece di rileggere lo storage. Al prossimo avvio si legge l'ultimo elenco salvato.

### 9.2 Credenziali e DeviceId

- **`JellyfinHttp`** tiene le credenziali del profilo attivo: token e DeviceId cambiano insieme, e solo con `setCredentials(token:, deviceId:)` (`token` si legge e basta). Con `null` si torna a nessun token e al DeviceId dell'installazione (`ClientInfo.deviceId`). L'intestazione `Authorization` si costruisce a ogni richiesta con il DeviceId attuale (`ClientInfo.copyWith(deviceId:)`); il resto di `ClientInfo` (client, nome del PC, versione) non cambia.
- **DeviceId usato per l'accesso: uno nuovo a ogni accesso**, con password o con Quick Connect, **anche con "Accedi di nuovo"** (§9.4).
  - Lo prepara la schermata di accesso quando si apre (`SessionController.prepareLogin`, poi `AuthService.prepareLogin()`, senza utente): nessun token e un UUID v4 nuovo nel client. Quick Connect lo usa già per `Initiate`, prima dell'approvazione.
  - **Perché anche "Accedi di nuovo"** (la spec diceva di riusare il DeviceId del profilo): il profilo che rifà l'accesso è scaduto, quindi il suo dispositivo sul server non c'è già più. Riusarlo lo farebbe condividere a un altro utente (il nome si può cambiare, e Quick Connect lo approva chiunque), e annullare il token vecchio con lo stesso DeviceId potrebbe chiudere la sessione nuova.
  - Due profili salvati non hanno mai lo stesso DeviceId (se succedesse, un avviso nel registro).
  - Il DeviceId, e una "generazione" che cresce a ogni cambio delle credenziali del client, si leggono **prima** della richiesta: il token vale per il DeviceId con cui è stato chiesto, anche se il client cambia nel frattempo.
- **Accesso riuscito:** il profilo si salva con il token e il DeviceId della richiesta, e si apre (§9.3). Password e Quick Connect dalla stessa schermata: vale il **primo** accesso che finisce; l'altro è superato (sotto), così le credenziali non cambiano sotto una sessione aperta.
- **Accesso superato:** finisce dopo "Annulla", dopo l'apertura di un altro profilo, dopo un altro accesso preparato o dopo un altro accesso già riuscito (la generazione è cambiata). Il profilo si salva e compare in "Chi guarda?", ma non si apre e non diventa l'ultimo usato. Se quell'utente ha già un profilo valido (non scaduto), resta quello salvato e il token nuovo si annulla.
- **Accesso con un utente già salvato** (lo stesso `userId`):
  1. il profilo prende il token e il DeviceId nuovi, invece di creare un doppione;
  2. il token vecchio si annulla (`POST /Sessions/Logout` con token e DeviceId vecchi; gli errori si ignorano), dopo il salvataggio e senza aspettare.
- **Sesto profilo:** oltre al pulsante nascosto (§9.4, §9.5), `AuthService` rifiuta l'accesso di un utente nuovo quando ci sono già 5 profili (`ProfileLimitException`) e annulla subito il token appena ottenuto. L'accesso mostra "Massimo 5 profili".
- **Chiamate per un profilo non attivo** (rimozione, immagine, §9.4 e §10.1): si fanno con le credenziali di quel profilo, senza toccare quelle attive. `JellyfinHttp.withCredentials(token:, deviceId:)` dà un client con lo stesso server e le stesse impostazioni, le credenziali di quel profilo e nessun `onUnauthorized`. Usa in prestito l'adattatore del client principale: chiuderlo non chiude il client principale.
- **I profili per l'interfaccia** stanno in `profilesProvider` (`ProfilesState`: i profili e quello aperto), così le schermate e le preferenze non creano il controller della sessione. Dopo ogni salvataggio, anche se lo storage non salva, `AuthService.onProfilesChanged` li ripubblica.
- **Aperture:** chi chiama `AuthService.openProfile` non ne sovrappone due: "Chi guarda?" ignora i clic mentre un profilo si apre.

### 9.3 Stati e rotte

- **Nuovo stato `SessionChoosingProfile`.** Porta alla rotta d'ingresso `/profiles`, senza shell; ogni altra rotta porta a `/profiles`. L'accesso (aggiunta o nuovo accesso) ha il suo stato, `SessionSignedOut` (sotto).
- **Le rotte d'ingresso** diventano `/splash`, `/login`, `/unreachable`, `/profiles`. Con `SignedIn` si va a `/home` da una di queste, quindi anche dopo un cambio di profilo.
- **`restore()` all'avvio:**
  - **0 profili:** `SignedOut`, cioè l'accesso, come oggi.
  - **1 profilo:** come oggi, con quel profilo. Se il token è scaduto il profilo si segna scaduto e si va all'accesso con "Sessione scaduta" e il nome già scritto; il profilo resta salvato finché non si rifà l'accesso o lo si toglie.
  - **2 o più:** `ChoosingProfile`, senza richieste.
- **Login: niente parametri nell'indirizzo.** La spec diceva `/login?add=1` e `/login?user=<userId>`. La modalità del login sta invece nello stato della sessione: il router porta già ogni `SignedOut` su `/login`, e lo stesso stato serve anche per un 401 durante la sessione.
  - **`SessionSignedOut(adding: true)`** (aggiungi profilo): il pulsante "Annulla" riporta a "Chi guarda?". Senza profili salvati, "Annulla" non c'è.
  - **`SessionSignedOut(expired: true, reloginUserId: <userId>)`** ("Accedi di nuovo"):
    - il nome del profilo è già scritto e si può cambiare, e il fuoco va alla password; un nome vuoto (il profilo migrato mai letto) non si scrive, e il fuoco resta sul nome;
    - c'è l'avviso "Sessione scaduta";
    - c'è "Annulla" verso "Chi guarda?" (o nessun "Annulla", con un solo profilo).
  - **"Annulla"** (`cancelLogin`) toglie dal client il DeviceId preparato per l'accesso e torna a "Chi guarda?". Quick Connect si ferma del tutto: niente più controlli del codice, codici nuovi o accessi.
- **Un 401 durante la sessione:** il profilo aperto si segna scaduto e si apre l'accesso per quel profilo (`SessionSignedOut(expired: true, reloginUserId:)`), con "Annulla" se ci sono altri profili. Il 401 della richiesta di uscita ("Esci", §9.5) non conta: il profilo si sta già togliendo.
- **Riuscito l'accesso** si entra con quel profilo (`SignedIn`), e il profilo diventa `lastUserId`. Un accesso superato non si apre (§9.2).

### 9.4 Schermata "Chi guarda?" (`/profiles`)

- **Aspetto:** come il login: il logo, il titolo "Chi guarda?", le card dei profili in una fila che va a capo e "Gestisci profili", che entrano uno dopo l'altro. Il logo è di 140 px e gli spazi sono stretti: così la schermata sta tutta nella finestra più piccola (1024×640) senza scorrere, anche con un profilo scaduto.
  - Ogni card ha l'avatar da 120 px e il nome. L'avatar è `UserAvatar` con il tag del profilo salvato (§10.5): l'immagine dell'utente, oppure l'iniziale scura su un cerchio dorato (fino al 17b c'era solo l'iniziale). Un profilo senza nome (quello migrato, se il suo primo `/Users/Me` non è riuscito) si chiama "Profilo".
  - Un profilo scaduto ha l'avatar attenuato e la scritta "Accedi di nuovo".
- **Card "Aggiungi profilo"** (icona +), solo con meno di 5 profili. Apre l'accesso per un profilo nuovo (`SessionSignedOut(adding: true)`, §9.3).
- **Clic su un profilo:**
  1. le credenziali del profilo vanno in `JellyfinHttp`;
  2. si legge `GET /Users/Me`;
  3. secondo la risposta:
     - **riuscita:** si entra (`SignedIn`); nome e tag dell'immagine si aggiornano nel profilo, insieme a `lastUsedAt` e `lastUserId`, e il profilo non è più scaduto;
     - **401:** il profilo si segna come scaduto e si apre l'accesso per quel profilo (`SessionSignedOut(expired: true, reloginUserId:)`, §9.3);
     - **server non raggiungibile** (o un altro errore): `SessionUnreachable(retryUserId:)`, cioè la schermata di oggi. Il suo "Riprova" (e il tentativo ogni 15 s) riapre questo profilo; senza un profilo scelto (all'avvio, con un solo profilo) rifà `restore()`, che lo riapre già. Con un profilo scelto c'è anche "Cambia profilo" (`backToProfiles`), che toglie le credenziali e torna qui: l'errore può essere di quel profilo (per esempio un 403 per un account senza accesso da remoto), e "Riprova" non riuscirebbe mai. Mentre si riprova è spento, come "Riprova".

  Un profilo già segnato scaduto apre subito l'accesso, senza richieste. Durante la lettura l'avatar ha un velo scuro con un indicatore chiaro (sull'oro non si vedrebbe), e gli altri clic non fanno niente.
- **"Gestisci profili"** mette le card in modifica: non si aprono, e "Aggiungi profilo" sparisce. Su ogni card compaiono:
  - **"Modifica immagine"** (matita, in alto a sinistra), che apre la finestra dell'immagine (§10) per quel profilo, con le sue credenziali. Su un profilo scaduto la matita è spenta: il suo token non vale più, e prima va rifatto l'accesso;
  - **"Rimuovi"** (cestino, con il tooltip "Rimuovi {nome}"), con la conferma "Rimuovere {nome} da questo PC? Per usarlo di nuovo servirà l'accesso." e i pulsanti "Annulla" e "Rimuovi". Rimuovere:
    1. toglie subito il profilo dal PC, poi le sue preferenze (§9.6);
    2. annulla il token di quel profilo in background (`POST /Sessions/Logout` con le sue credenziali; gli errori si ignorano): con il server giù non si aspetta il timeout della connessione.

    In `SessionController.removeProfile` togliere il profilo aperto è un'uscita (§9.5), e togliere un altro profilo mentre se ne usa uno lascia la sessione com'è. Come per "Esci", lo stato cambia prima di cancellare le preferenze: tolto l'ultimo profilo, nessun "Chi guarda?" vuoto.

  "Fine", o Esc, chiude la modifica. Tolto l'ultimo profilo si va all'accesso.
- **Lingua della schermata:** quella dell'ultimo profilo usato (`lastUserId`), che senza una scelta sua parte da quella del PC (§9.6). Senza un ultimo usato (è stato tolto), e nell'accesso quando non ci sono profili, vale la lingua del PC: la chiave `locale` di prima della 0.11.0, altrimenti quella di Windows.
- **Tastiera:** il fuoco parte dalla card dell'ultimo profilo usato (o dalla prima), quindi Invio la apre subito. Le card ricevono il focus con Tab e si aprono con Invio, con il focus visibile.
- **Screen reader:** ogni card è un pulsante con il nome; un profilo scaduto ha il suggerimento "Accedi di nuovo".

### 9.5 Menu dell'avatar e Impostazioni

- **Menu dell'avatar:** Impostazioni, [Amministrazione], **Cambia profilo**, **Aggiungi profilo** (con meno di 5 profili), Esci. L'avatar del menu è `UserAvatar` da 30 px con il tag della sessione (§10.5), al posto dell'iniziale (`CircleAvatar`) del 17b.
- **Cambia profilo** (§9.7) porta a "Chi guarda?".
- **Aggiungi profilo** fa lo stesso cambio (in un party la conferma dice "Aggiungi profilo") e poi apre l'accesso per un profilo nuovo (`SessionSignedOut(adding: true)`, §9.3). "Annulla" porta a "Chi guarda?".
- **Esci:**
  1. annulla il token come oggi; il 401 di questa richiesta (un token già scaduto) si ignora;
  2. **toglie il profilo dal PC**;
  3. va a "Chi guarda?" se restano profili, altrimenti all'accesso;
  4. cancella le preferenze del profilo (§9.6). Lo stato cambia prima: la shell non mostra un fotogramma con le preferenze del PC.
- **Impostazioni → Account:** l'avatar da 64 px accanto ad "Accesso come {nome}", poi i pulsanti **Cambia immagine** (la finestra dell'immagine del profilo aperto, §10), Cambia profilo ed Esci.

### 9.6 Preferenze del profilo

- **Del profilo** (chiave `profile.<userId>.<chiave>`, con l'id di `jellyfinIdKey`): `locale`, `party.lastMode`, `discord.enabled`, `discord.showTitle`, `discord.showPoster`, `player.subtitleScale`, `player.autoSkipIntro`, `player.autoplayNext`.
- **Del PC** (come oggi): `player.volume`, `player.quality`, `player.hardwareDecoding`, `appearance.motion`, `window_bounds`, `device_id`.
- **Lettura:** si usa la chiave del profilo. Se manca, vale la chiave di oggi (quella del PC), come valore di partenza.
- **Scrittura:** sempre nella chiave del profilo.

  Così il profilo migrato tiene le sue impostazioni, e i profili nuovi partono da quelle del PC.
- **Lingua "di Windows" in un profilo:** nella chiave del profilo si salva una stringa vuota, perché senza valore varrebbe la lingua del PC. Senza profilo la chiave `locale` si toglie, come prima.
- **Di quale profilo:** `ProfilePreferences` arriva ai controller da `profilePreferencesProvider`, che segue `profilesProvider`: valgono le preferenze del profilo aperto, altrimenti quelle dell'ultimo usato ("Chi guarda?" e l'accesso). Senza nessuno dei due valgono le chiavi del PC, come prima della 0.11.0.
- **Rimozione:** togliendo un profilo si cancellano le sue chiavi (`ProfilePreferences.forget`).
- **Al cambio di profilo** i controller di queste preferenze (`LocaleController`, `PartyModePreference`, `DiscordSettingsController`, `PlayerSettingsController`) rileggono i valori, perché guardano `profilePreferencesProvider`: la lingua dell'app cambia subito.

### 9.7 Cambio di profilo

Il cambio lo fa `changeProfile(context, ref, {addProfile})` (`lib/features/profiles/profile_switch.dart`), dal menu dell'avatar e dalle Impostazioni; con `addProfile` è "Aggiungi profilo" (§9.5).

1. **Party:** se l'utente è in un watch party (`WatchPartyState.phase` non è `none`: sta entrando nel gruppo SyncPlay o ci è dentro; il canale del party si chiude da solo uscendo dal gruppo), compare la conferma "Uscirai dal watch party.", con i pulsanti "Annulla" e "Cambia profilo". Con "Aggiungi profilo" il titolo e il pulsante dicono "Aggiungi profilo". Confermato, l'app esce dal gruppo come con "Esci dal party", aspettando al massimo 3 s (`partyLeaveTimeout`). Questo serve perché **il token non si annulla**, quindi il party non si chiuderebbe da solo.
   - La conferma è `showWfConfirmDialog` (`lib/ui/wf_confirm_dialog.dart`), la stessa di "Rimuovi" (§9.4); `showAdminConfirmDialog` ora la usa.
   - Un cambio confermato si fa anche se chi l'ha chiesto (il menu, le Impostazioni) sparisce durante l'uscita dal party, ma solo se la sessione è ancora dello stesso utente: un'uscita o un 401, nel frattempo, lo fermano.
2. **Stato:** diventa `ChoosingProfile` (con "Aggiungi profilo", l'accesso per un profilo nuovo), e le credenziali spariscono da `JellyfinHttp`. Il token resta valido e salvato.
3. **Azzeramento:** tutto quello che dipende dall'utente si azzera come all'uscita di oggi (§2.2): WebSocket, canale del party, amici, cassetta, richieste, admin, dati utente e cache dei provider.
4. **Router:** porta a `/profiles` (a `/login`, con "Aggiungi profilo").

Il player non può essere aperto durante il cambio, perché il menu dell'avatar sta nella shell. La cache delle immagini è comune a tutti i profili: gli indirizzi non dipendono dall'utente. La cache dei tag degli avatar (`AvatarDirectory`, §10.5) invece è nuova a ogni profilo.

## 10. Immagini del profilo

### 10.1 Finestra dell'immagine

- **Da dove si apre** (`showAvatarDialog`, `lib/features/profiles/avatar_dialog.dart`):
  - da "Gestisci profili" (§9.4), con la matita "Modifica immagine", per qualunque profilo salvato non scaduto, con le credenziali di quel profilo (§9.2);
  - da Impostazioni → Account, con "Cambia immagine", per il profilo aperto.
- **"Immagine del profilo", con tre schede:**
  - **Avatar:** la galleria (§10.2). Un clic sceglie (bordo dorato), e "Usa questo" (spento finché non si sceglie) carica il PNG dell'avatar;
  - **Dal PC:** "Scegli un'immagine…", poi il ritaglio (§10.3) con "Scegli un'immagine…" (un altro file) e "Usa questa", che carica il JPEG;
  - **Rimuovi** (il testo è `profilesRemove`): l'anteprima da 120 px (l'immagine di oggi, o l'iniziale) e il pulsante "Rimuovi immagine", spento se il profilo non ha un'immagine.
- **Le schede:**
  - la scheda "Dal PC" resta viva: passando a un'altra scheda e tornando, il ritaglio è com'era;
  - non si cambia scheda trascinando: il trascinamento serve al ritaglio;
  - il messaggio d'errore sparisce cambiando scheda (era della scheda di prima).
- **Indicatore:** sotto le linguette c'è sempre lo spazio per una barra di avanzamento, così il contenuto non si sposta. La barra compare mentre si prepara un'immagine dal PC e durante il caricamento; il messaggio d'errore compare sotto.
- **Dimensioni:** 560 px di larghezza. Nella finestra più piccola (1024×640), anche con un messaggio d'errore, le 4 righe della galleria ci stanno, con gli avatar sempre da 56 px.
- **Durante il caricamento:**
  - i pulsanti sono spenti;
  - la finestra non si chiude, né con Esc né con un clic fuori. Mentre si prepara un'immagine dal PC invece Esc la chiude, e l'immagine preparata si scarta.

  Riuscito il caricamento (o con un 401, §10.4), la finestra si chiude, ma solo se è ancora quella in cima: se nel frattempo è stata chiusa da altro, o c'è sopra un'altra finestra, un `pop` toglierebbe la pagina sotto.

### 10.2 Galleria

- **24 avatar,** ognuno con un'icona Lucide (pacchetto `lucide_icons_flutter`, licenza ISC, già nell'app) a tema cinema e serate: popcorn, ciak, pellicola, biglietto, TV, proiettore, cinepresa, stella, razzo, fantasma, gatto, cane, coniglio, **uccello**, pesce, teschio, corona, cuore, nota musicale, gamepad, pizza, caffè, scintille, luna. La prima versione diceva il gufo: Lucide 3.1.20 non ce l'ha, e al suo posto c'è l'uccello (`LucideIcons.bird`).
- **Colori:** 8 sfumature dai colori di WonderFlix (oro, rosso sipario, verde acqua, blu notte, viola, verde, arancio, ardesia), costanti in `avatar_gallery.dart`. Si ripetono in ordine sulle icone, quindi due avatar vicini hanno colori diversi.
- **Disegno:** con `PictureRecorder`, 512×512: lo sfondo sfumato (dall'alto a sinistra al basso a destra) e l'icona bianca, grande il 55% del lato. Il risultato è un PNG.
- **Griglia:** 6 avatar per riga, ognuno da 56 px: è lo stesso disegno, in piccolo e rotondo. Per lo screen reader ogni avatar è un pulsante "Avatar {numero}" (`profileImageGalleryItem`), che dice anche quale è scelto.

### 10.3 Immagine dal PC

- **Scelta del file** con `file_selector` (pacchetto ufficiale di Flutter), filtro "Immagini": jpg, jpeg, png, webp, gif, bmp.
  - Oltre 20 MB (la dimensione del file, letta prima del contenuto): "Immagine troppo grande".
- **Preparazione**, in un isolate con il pacchetto `image` (Dart puro). Il risultato è l'**immagine di lavoro**, su cui lavora il ritaglio.
  1. **Intestazione prima di decodificare.** Un file piccolo può dichiarare un'immagine enorme, che in memoria non starebbe.
     - Un JPEG si legge con un parser suo: scorre i segmenti fino al primo SOF e accetta solo i marcatori che il decoder legge allo stesso modo (DQT, DHT, DRI, APPn, COM, RST/TEM e i byte di riempimento). Ogni altra cosa prima del SOF (anche un SOF nascosto dietro `FF 00`) dà "Immagine non valida": il decoder la salterebbe a modo suo, e potrebbe trovare un SOF che il parser non ha visto. Il SOF deve avere da 1 a 4 componenti, ognuna con il campionamento da 1 a 4 (i limiti dello standard): il decoder alloca i blocchi di ogni componente, e un JPEG piccolo con 24 componenti occuperebbe gigabyte.
     - Gli altri formati si leggono con `startDecode` del pacchetto `image`, e valgono solo quelli del filtro: PNG, GIF, WebP e BMP. Ogni altro formato che il pacchetto riconosce (ICO, TIFF, PSD, EXR, TGA, PNM, PVR) dà "Immagine non valida": le sue misure qui non si controllano (un ICO che dice 1×1 può contenere un PNG enorme).
     - **WebP animato:** "Immagine non valida". `startDecode` dà la tela, ma il primo fotogramma si decodifica con le sue misure, che possono essere molto più grandi. (Di una GIF il fotogramma sta sempre dentro la tela.)
     - **PNG:** prima di decodificare, i dati compressi (IDAT) si decomprimono a pezzi contando i byte, senza tenerli: oltre quelli che le misure dell'intestazione permettono (una riga è il byte del filtro più i pixel; con l'interlacciamento, le righe dei 7 passaggi; più 1 KB di margine) è "Immagine non valida". Il decoder li espande tutti in memoria: un file di 4 MB può arrivare a 8 GB.
     - Larghezza o altezza nulla o negativa (un BMP può dichiararla): "Immagine non valida".
     - Oltre 64 milioni di pixel: "Immagine troppo grande". Qualche telefono che salva foto da 108 o 200 megapixel viene rifiutato; la maggior parte dei telefoni ne salva da 12.
  2. **Decodifica.** Un file che non si decodifica: "Immagine non valida". Di una GIF animata vale solo il primo fotogramma.
  3. **Immagine di lavoro:**
     - una tavolozza diventa colori veri (gli indici non si possono mediare);
     - si riduce a 2048 px di lato al massimo, con la media dei pixel: basta per un avatar di 512 px anche a 4×;
     - 8 bit per canale, come il JPEG (16 bit, grigi a pochi bit, HDR);
     - le parti trasparenti prendono il grigio scuro dell'app (`WfColors.surfaceHigh`, `0xFF1B1B1B`). La prima versione diceva nero: il colore va già nell'immagine di lavoro, così l'anteprima del ritaglio è uguale all'immagine caricata;
     - l'orientamento dell'EXIF si applica alla fine, all'immagine già ridotta (più leggero);
     - si salva in PNG, **senza EXIF**: si toglie prima di salvare, senza contare sull'encoder PNG.
- **Ritaglio** (`AvatarCropper`): un riquadro quadrato e fisso di 240 px, con un velo fuori dal cerchio che diventerà l'avatar.
  - L'immagine si trascina, e copre sempre tutto il riquadro.
  - Si ingrandisce con la rotella (1,1× a scatto; uno scorrimento solo orizzontale non conta) o con il cursore, da "riempie il riquadro" fino a 4×, tenendo fermo il centro del riquadro. Per lo screen reader il cursore è "Ingrandimento" con il valore ("2,0×").
  - All'inizio l'immagine è centrata, a 1×.
- **Codifica**, in un isolate: il quadrato scelto, ridimensionato a 512×512 (con la media dei pixel riducendo, con la bicubica ingrandendo un ritaglio piccolo), JPEG con qualità 90. Un riquadro che esce dall'immagine si sposta dentro, senza rimpicciolire; uno più grande del lato corto si stringe a quello.
- **L'EXIF non arriva mai al server** (nemmeno il GPS): le immagini degli utenti si leggono senza accesso (§3.2), e l'EXIF di una foto può dire dove, quando e con cosa è stata scattata.

### 10.4 Caricamento e rimozione

- **Caricamento:** `POST /UserImage?userId=<id>` con il **corpo in base64**, come fa jellyfin-web, e `Content-Type` `image/png` (galleria) o `image/jpeg` (dal PC): `UserImageApi.upload` con `ImageUpload`, attraverso `JellyfinHttp.post(contentType:)` (senza, dio manderebbe `application/json`). Il base64 è **verificato** nel sorgente di Jellyfin 10.11.9 (§3.2, §14).
- **Rimozione:** `DELETE /UserImage?userId=<id>` (`UserImageApi.remove`).
- **Il flusso** sta in `SessionController.setProfileImage(userId, {image})` (senza `image` toglie):
  1. il client è `AuthService.clientFor(userId)`: quello principale per il profilo aperto (`AuthService.isActive`), altrimenti uno con le credenziali di quel profilo (`JellyfinHttp.withCredentials`, che non segnala i 401). Un profilo che non c'è: niente;
  2. carica o toglie, poi rilegge `/Users/Me` con lo stesso client, per avere il `PrimaryImageTag` nuovo;
  3. se la risposta è di un altro utente (non dovrebbe succedere) non si aggiorna niente;
  4. altrimenti il profilo salvato si aggiorna sempre (`AuthService.updateStoredProfile`: nome e tag, solo se cambiano), e la sessione solo se è aperta con quell'utente;
  5. dà l'utente riletto.
- **Dopo la riuscita** la finestra mette il tag nuovo nella cache degli avatar, se c'è (`AvatarDirectory.remember`, per id e per nome), e fa rileggere gli avatar di quell'utente; poi si chiude.
- **Errori:**
  - **403:** "Non hai il permesso di cambiare l'immagine", e la finestra resta aperta;
  - **401:** il token non vale più, e la finestra si chiude. Un profilo non aperto si segna scaduto (`AuthService.markProfileExpired`): in "Chi guarda?" ha "Accedi di nuovo" e la matita spenta. Per il profilo aperto ci pensa la sessione, come per ogni 401 (§9.3): l'accesso con "Sessione scaduta";
  - **ogni altro errore:** "Caricamento non riuscito", e la finestra resta aperta.

  La prima versione diceva che in tutti i casi la finestra restava aperta. Con un 401 si chiude: con lo stesso token un nuovo tentativo non riuscirebbe mai, e per il profilo aperto la sessione è già passata all'accesso.

### 10.5 `UserAvatar` dovunque

- **`UserAvatar`** (`lib/ui/user_avatar.dart`) mostra l'immagine dell'utente con `GET /UserImage?userId=&tag=` (`ImageUrls.user`), attraverso `WfImage` e la cache delle immagini di oggi, decodificata alla dimensione mostrata, perché il server non ridimensiona (§3.2). L'indirizzo non chiede l'accesso, quindi funziona anche in "Chi guarda?", senza sessione. Ha due costruttori:
  - **`UserAvatar(userId:, name:, size:, imageTag:)`:** il tag è già noto (l'utente aperto, i profili salvati, le sessioni dell'admin); `null` vuol dire senza immagine;
  - **`UserAvatar.lookup(userId:, name:, size:)`:** il tag lo cerca `avatarImageProvider`, per id (`AvatarLookup.byId`) o, senza id o con un id vuoto, per nome (`AvatarLookup.byName`: i membri del party, perché SyncPlay dà solo i nomi). La risposta del plugin dà sempre l'id dell'utente, che serve per l'indirizzo.
- **Aspetto:**
  - senza immagine, l'iniziale (grande 0,45 volte il diametro; "?" con un nome vuoto): scura su oro, oppure, con `muted`, dorata su grigio come le iniziali di prima (party, amici, inviti, chat, richiesta d'amicizia);
  - l'immagine sta sopra l'iniziale, con il segnaposto trasparente: mentre si carica, o se non si carica, si vede l'iniziale;
  - l'id nell'indirizzo è normalizzato (`jellyfinIdKey`), come quello delle immagini cercate: un utente ha un solo indirizzo, e la cache delle immagini una sola copia.
- **Screen reader:** l'avatar è decorativo (`ExcludeSemantics`): il nome c'è sempre accanto.
- **Layout:** `UserAvatar` non va misurato con il layout "a secco" (`IntrinsicWidth`, `IntrinsicHeight` e simili, anche dentro un `WidgetSpan`): `WfImage` decodifica attraverso un `LayoutBuilder`, che quel layout non lo sa fare. Oggi non lo fa nessuno. Nella chat l'avatar sta in un `WidgetSpan` e resta lo stesso widget finché il mittente non cambia: un widget nuovo a ogni build rifarebbe il layout del paragrafo (per esempio a ogni tasto nel campo della chat).
- **Da dove prende il tag:**
  - l'utente aperto, dalla sessione (`JellyfinUser.primaryImageTag`); i profili salvati, dal profilo (`StoredProfile.imageTag`);
  - le sessioni dell'admin, da Jellyfin: `UserPrimaryImageTag` della sessione (`SessionEntry.userImageTag`), che c'è anche senza il plugin;
  - gli altri utenti, dalla cache degli avatar.
- **La cache degli avatar** (`AvatarDirectory`, in `lib/features/social/avatars_provider.dart`; la prima versione la chiamava `avatarsProvider`):
  - c'è solo con un profilo aperto e con la funzione `avatars` del plugin (`avatarDirectoryProvider`). Senza, `UserAvatar.lookup` mostra l'iniziale e non chiama niente (anche nei widget test senza sessione). È nuova a ogni profilo; quando si chiude, le richieste in attesa e quelle in viaggio finiscono con l'iniziale;
  - la chiave è `AvatarLookup`: l'id senza trattini e in minuscolo, oppure il nome in minuscolo. Un utente trovato vale per id e per nome (non per il nome vuoto);
  - i nomi vanno al plugin come sono scritti: solo la chiave della cache è in minuscolo. Su qualche lettera (İ, il segno del kelvin, ẞ) le regole delle maiuscole di Dart e di .NET non sono d'accordo, e il confronto lo fa il plugin;
  - un id vuoto, o un nome vuoto senza id: nessuna richiesta, l'iniziale;
  - raccoglie per 50 ms le richieste dei widget e le manda in una sola chiamata, al massimo 100 voci (§7.2); le altre partono in una chiamata subito dopo;
  - una richiesta già partita si condivide: chi chiede lo stesso utente aspetta la sua risposta, senza un'altra chiamata;
  - un risultato vale 10 minuti, e anche un errore, che lascia le iniziali. Un avatar sullo schermo si rilegge passati 10 minuti: il timer di `avatarImageProvider` parte quando arriva la risposta, così alla rilettura la cache è già scaduta. Così, dopo un errore, si riprova dopo 10 minuti;
  - un errore va nel registro come info se è un `ApiException`, altrimenti come avviso;
  - dopo un caricamento, l'immagine nuova (`remember`) vale subito e vince su una risposta del plugin già in viaggio. Anche un'immagine trovata da un'altra chiamata vale più di una risposta partita prima; un errore o un "senza immagine" di un'altra chiamata no: un errore non copre mai un'immagine trovata.
- **Dove compare:**
  - con il tag noto: il menu dell'avatar (30 px), "Chi guarda?" (120 px), Impostazioni → Account (64 px), la scheda "Rimuovi" della finestra (120 px), le righe utente della scheda Sessioni dell'admin (28 px);
  - per id, `muted`: il pannello amici (amici, richieste ricevute e inviate, ricerca; 26 px), il menu degli inviti (26 px), la scheda della richiesta d'amicizia (24 px, al posto dell'icona), la chat del party (18 px, accanto al nome del mittente, anche nei nostri messaggi);
  - per nome, `muted`: la fila e il menu dei membri del party (26 px).
- **`MemberAvatar(name, userId?)`** resta, come un uso di `UserAvatar.lookup` (`muted`, 26 px): per id quando c'è, altrimenti per nome.

## 11. Testi nuovi (ARB, it + en)

`app_it.arb` è il modello, poi `app_en.arb`. I testi principali, in italiano:

| Dove | Testi |
|---|---|
| Saghe | "Saghe", "Film" (selettore), "{n} saghe" (plurale), "{n} film" (plurale), "{n} film · {m} visti", "Fa parte di: {name}", "Questo film", "Riproduci \"{title}\"", "Riprendi \"{title}\"", "Cerca una saga", "Nome", "Numero di film", "Data di aggiunta", "Nessuna saga", "Nessuna saga con questo nome" |
| Chi guarda? | "Chi guarda?", "Aggiungi profilo", "Gestisci profili", "Fine", "Accedi di nuovo", "Modifica immagine", "Rimuovi", "Rimuovi {name}" (tooltip del cestino), "Rimuovere {name} da questo PC?", "Per usarlo di nuovo servirà l'accesso.", "Massimo 5 profili", "Profilo" (un profilo senza nome) |
| Menu e Account | "Cambia profilo", "Aggiungi profilo", "Cambia immagine", "Uscirai dal watch party.", "Cambia profilo" (pulsante della conferma) |
| Login | "Annulla", "Sessione scaduta" (c'è già) |
| Immagine | "Immagine del profilo", "Avatar", "Dal PC", "Rimuovi" (la scheda), "Usa questo", "Scegli un'immagine…", "Usa questa", "Rimuovi immagine", "Immagine troppo grande", "Immagine non valida", "Non hai il permesso di cambiare l'immagine", "Caricamento non riuscito", "Immagini" (il filtro nella finestra di Windows), "Ingrandimento" (il cursore del ritaglio, per lo screen reader), "Avatar {number}" (un avatar della galleria, per lo screen reader) |

I testi dei profili (piano 17b) hanno le chiavi `profiles…`. C'è un solo "Annulla" (`profilesCancel`) per l'accesso, la rimozione e la conferma del cambio, e un solo "Aggiungi profilo" e "Cambia profilo" per la card, il menu, le Impostazioni e la conferma.

I testi delle immagini (piano 17c): "Modifica immagine" è `profilesEditImage`, "Cambia immagine" `settingsChangeImage`, quelli della finestra hanno le chiavi `profileImage…` (per esempio `profileImageGalleryItem`, "Avatar {number}"). La scheda "Rimuovi" usa `profilesRemove`, lo stesso "Rimuovi" di "Gestisci profili".

In inglese "Saghe" e "saga" sono "Collections" e "collection", come in Jellyfin.

Il test dei testi di ogni piano (`test/app/l10n_plan17a_test.dart`, `…17b…`, `…17c…`) controlla che le chiavi ci siano in entrambe le lingue.

## 12. Errori e casi limite

### Plugin e saghe

- **Plugin senza `collections` o senza `avatars`** (1.4.0 o più vecchio): niente saghe e solo iniziali per gli altri utenti (sotto, "Immagini"). Nessun errore visibile.
- **Saga con un solo film visibile:**
  - c'è nella vista "Saghe" e nella ricerca, con "1 film";
  - la sua pagina funziona;
  - non ha la riga "Fa parte di".
- **Film in più saghe:** una riga per saga (§8.3).
- **Saga cancellata mentre la sua pagina è aperta:** alla rilettura successiva compare l'errore generico con "Riprova", come per un titolo (§8.2).
- **Lettura delle saghe fallita:** le righe della scheda e la ricerca non mostrano niente; la vista "Saghe" mostra l'errore con "Riprova". L'errore non resta in cache: la lettura si ripete quando qualcuno torna ad ascoltare (§8.1).
- **Doppioni sul server** (le due "Star Wars"): compaiono tutti e due, finché non si sistemano sul server.

### Profili

- **Lettura dei profili fallita:** si va all'accesso, come oggi. Se lo storage lancia, il primo salvataggio rilegge e tiene i profili salvati, o non salva (§9.1). Su Windows però il plugin di solito non lancia: un file che non si apre si legge vuoto, e uno che non si decifra si cancella; allora i profili sono persi, come con dati rovinati (che si sostituiscono).
- **Salvataggio dei profili fallito:** i profili valgono in memoria per questa esecuzione (anche dopo un `restore()`), un avviso va nel registro e la sessione non si rompe. Nella migrazione la sessione di prima resta, per riprovare al prossimo avvio (§9.1).
- **Server giù aprendo un profilo da "Chi guarda?":** "Riprova" riapre quel profilo, e "Cambia profilo" torna a "Chi guarda?" (§9.4).
- **401 attesi** (aprendo un profilo scaduto, annullando un token già scaduto): nel registro come info, non tra gli "Ultimi errori" della diagnostica.
- **Token di un profilo scaduto:** "Accedi di nuovo" (§9.4). Con un solo profilo, l'accesso con il nome già scritto (§9.3).
- **Profilo migrato senza nome** (il suo primo `/Users/Me` non è riuscito): in "Chi guarda?" si chiama "Profilo", e "Accedi di nuovo" non scrive il nome (§9.3).
- **Risposte in volo durante un cambio di profilo:** si scartano, perché i provider si ricostruiscono per il nuovo utente. Come all'uscita di oggi.
- **Accesso che finisce tardi** (dopo "Annulla", dopo l'apertura di un altro profilo): il profilo si salva ma non si apre; se quell'utente ha già un profilo valido, resta quello e il token nuovo si annulla (§9.2).
- **Uscita dal party fallita o lenta** durante un cambio: dopo 3 s il cambio va avanti lo stesso. Il gruppo lo pulisce Jellyfin quando la sessione del profilo vecchio scade. Se intanto il menu o le Impostazioni spariscono, il cambio si fa lo stesso, purché la sessione sia ancora dello stesso utente (§9.7).
- **Stesso utente aggiunto due volte:** un solo profilo (§9.2).
- **Sesto profilo:** "Aggiungi profilo" non c'è, né nel menu né in "Chi guarda?". Se un accesso ci arriva lo stesso, `AuthService` lo rifiuta: "Massimo 5 profili", e il token appena ottenuto si annulla (§9.2).
- **Rimozione con il server giù:** il profilo si toglie subito; il token si annulla in background e gli errori si ignorano (§9.4).
- **"Esci" con il token già scaduto:** il 401 della richiesta di uscita si ignora, e il profilo si toglie lo stesso (§9.5).

### Immagini

- **Plugin senza `avatars`:** solo iniziali per gli altri, nessuna chiamata e nessun errore; l'utente aperto, i profili e le sessioni dell'admin hanno l'immagine lo stesso (il tag viene da Jellyfin).
- **Immagine di un altro utente molto grande** (caricata da jellyfin-web): in memoria resta alla dimensione mostrata, ma il motore la decodifica prima per intero (limite accettato, sotto).
- **File scelto:** oltre 20 MB, o un'intestazione che dichiara oltre 64 milioni di pixel: "Immagine troppo grande"; un file che non è un'immagine, un formato fuori dal filtro (ICO, TIFF…), un JPEG con marcatori strani prima del SOF o con troppe componenti, un WebP animato, un PNG che si espande oltre le sue misure, misure nulle o negative: "Immagine non valida" (§10.3).
- **401 durante il caricamento:** la finestra si chiude; il profilo non aperto si segna scaduto, quello aperto passa all'accesso (§10.4).
- **La sessione che cambia durante il caricamento:** la finestra non toglie la pagina sotto (si chiude solo se è ancora in cima), e la cache degli avatar si aggiorna lo stesso.
- **Due finestre dell'immagine aperte per lo stesso utente:** vince l'ultimo caricamento.
- **Limiti noti, accettati:**
  - un'immagine non quadrata caricata da jellyfin-web può sembrare sfocata (si decodifica alla larghezza dell'avatar), e una con la trasparenza lascia vedere l'iniziale sotto;
  - sul touchpad non si ingrandisce con due dita (solo rotella e cursore);
  - Invio su un avatar della galleria lo sceglie, ma non carica: serve "Usa questo";
  - un `refreshUser` della sessione che finisce durante un caricamento può rimettere per un momento il tag vecchio;
  - se il caricamento riesce ma la rilettura dell'utente no, la finestra dice "Caricamento non riuscito" anche se l'immagine è cambiata (il tag nuovo arriva alla prossima lettura dell'utente);
  - le immagini degli altri utenti le decodifica il motore di Flutter alle loro misure vere, prima di ridurle a quelle mostrate: un utente malintenzionato potrebbe caricare (da jellyfin-web o con l'API) un'immagine con misure enormi e far usare molta memoria all'app di chi la vede. Su un server privato, tra persone che si conoscono, è poco probabile;
  - Esc durante la preparazione di un'immagine dal PC chiude la finestra, ma non ferma l'isolate: una foto grande continua a usare CPU e memoria per qualche secondo, e il risultato si scarta.

## 13. Test

- **Plugin** (xUnit):
  - Collezioni:
    - l'adattatore, con `Folder` e `BoxSet` simulati da sottoclassi: la cartella e ogni collezione si leggono sempre attraverso l'utente e con i collegati; un film sciolto nella cartella non è una collezione; nome e `SortName` mancanti diventano vuoti; il tag della locandina c'è solo con la locandina;
    - senza utente (anche con l'id vuoto, che farebbe lanciare `UserManager`) o senza la cartella delle collezioni, elenco vuoto, e la cartella non si crea mai;
    - una collezione senza film visibili non compare (controller);
    - id nel formato "N" (controller);
    - l'autorizzazione: `[Authorize]` senza policy;
    - il JSON del protocollo e la registrazione del servizio;
    - la visibilità vera (librerie e controllo parentale) non si prova con i test: si controlla nella prova a mano con il token di un utente vero (§14).
  - Avatar:
    - l'adattatore, con gli utenti dello stub: ricerca per id e per nome, con il nome senza badare alle maiuscole (anche con lettere non ASCII); nessun doppione; utenti inesistenti, il GUID vuoto o disattivati assenti; il tag solo con l'immagine; nessuna richiesta, nessuna lettura degli utenti;
    - il controller: id e nomi passati all'adattatore, con gli id che non sono GUID e le voci vuote saltati; un GUID con i trattini accettato; gli id nel formato "N"; più di 100 voci danno 400 senza chiedere niente (100 vanno bene); senza voci valide, elenco vuoto senza leggere gli utenti;
    - l'autorizzazione: `[Authorize]` senza policy;
    - il JSON del protocollo e la registrazione del servizio.
  - Le funzioni in `Info` (con `avatars`) e la versione.
- **Modelli e API dell'app:**
  - `ItemKind.boxSet` e `itemRoute`;
  - `LibraryApi.collectionItems` (percorso e parametri, senza `recursive`), `ImageUrls.primaryWithTag` e `jellyfinIdKey` (non c'è un test su `ItemQuery.parentId`: il campo non esiste);
  - `SocialFeatures.collections` letta da `Info`, anche senza watch party;
  - `CollectionsApi` (`FakeAdapter`): percorso, letture tolleranti, `ItemIds` normalizzati e senza doppioni, corpo di forma inattesa, 404;
  - `AvatarsApi` (`FakeAdapter`): id e nomi separati da virgole; letture tolleranti (id senza trattini, tag assente, voci rotte saltate); corpo di forma inattesa, 404;
  - `UserImageApi`: corpo in base64, `Content-Type`, `DELETE`, errori 403 e 401; `JellyfinHttp.post` con il `Content-Type` di un corpo che non è JSON;
  - `ImageUrls.user` (con il tag, senza ridimensionare); `SessionEntry.userImageTag`; `SocialFeatures.avatars` letta da `Info`, anche senza watch party.
- **Saghe:**
  - l'indice film → saghe;
  - l'ordine delle righe;
  - una riga solo con almeno 2 film;
  - il pulsante principale della pagina (primo non visto, iniziato, tutti visti);
  - la vista "Saghe": ricerca, ordinamenti, vuoti, selettore nascosto senza la funzione, `?view=sagas`;
  - la ricerca: accenti e maiuscole, massimo 12, nessuna chiamata;
  - `collectionsProvider`: nessuna chiamata senza la funzione, rilettura con la libreria o l'utente, elenco non modificabile, una lettura riuscita che resta in cache senza ascoltatori, un errore che non resta in cache (si riprova tornando ad ascoltare), una rilettura fallita che lascia l'indice com'era;
  - la vista "Saghe" in caricamento (scheletro, non "Nessuna saga"), l'errore che vince su un elenco vuoto di prima, "Riprova" che mostra lo scheletro, il ritorno in cima con una nuova ricerca o un nuovo ordine, il selettore che riporta ai film;
  - la pagina della saga: errore con "Riprova" per una saga che non c'è, sfondo che resta dietro un errore, testata che arriva insieme ai film, errore dei soli film con "Riprova";
  - le righe: titolo come link (anche lo spazio tra il titolo e la freccia), "Questo film" che non apre niente (né clic né anteprima), le altre card che si aprono;
  - la ricerca: la sezione "Saghe" sopra i film, l'elenco letto all'apertura, "Nessun risultato" assente con le sole saghe;
  - la normalizzazione della ricerca (`foldForSearch`): maiuscole, accenti, lettere accentate scritte come lettera più segno, macron e lettere speciali.
- **Profili** (quelli del piano 17b):
  - `ProfileBook` e `StoredProfile`: lo stesso utente sostituito al suo posto, la rimozione (anche dell'ultimo usato), gli id confrontati senza trattini e maiuscole, pieno a 5, la lettura tollerante (profili rotti, doppioni, oltre 5, un elenco che non è un elenco), l'immagine in `copyWith`;
  - `SecureProfileStore`: scrittura e rilettura (ultimo usato, immagine, scadenza), file illeggibile o di forma sbagliata, storage che non si legge, chiavi dell'istanza di sviluppo;
  - la migrazione da `wonderflix.session` con il DeviceId di oggi (anche nell'istanza di sviluppo), con `read()` che non lancia se il salvataggio dei profili o la cancellazione della sessione di prima falliscono, o se la sessione di prima è rovinata e non si cancella;
  - `JellyfinHttp`: token e DeviceId insieme nell'intestazione dopo `setCredentials`; `withCredentials` con le credenziali di un altro profilo, e il client derivato che, chiuso, non chiude l'adattatore del principale; `ClientInfo.copyWith`;
  - `AuthService`:
    - `restore()` con 0 profili, 1 (valido, scaduto, server giù, errore 500) e 2; `openProfile` riuscito e di un profilo che non c'è;
    - l'accesso: un DeviceId nuovo a ogni accesso, anche con "Accedi di nuovo" (e quando accede un altro utente); il DeviceId della richiesta con la password e con Quick Connect; profilo nuovo; stesso utente con il token vecchio annullato; sesto profilo rifiutato con il token annullato; errore del server; profili non salvati;
    - gli accessi superati: da "Annulla", da un profilo aperto o che si sta aprendo, per un utente con un profilo valido o scaduto;
    - `onProfilesChanged` a ogni salvataggio; l'avviso per un DeviceId già di un altro profilo;
    - uscita e rimozione: le credenziali di quel profilo, il server giù, la rimozione che non aspetta il server, gli errori ignorati; `deactivate`, `markActiveExpired`, `updateActiveProfile`;
  - `SessionController`: `restore()` e `openProfile` per ogni esito; il login e Quick Connect, anche superati o insieme; `prepareLogin`, `switchProfile`, `addProfile`, `relogin`, `cancelLogin`; "Esci" con e senza altri profili, con lo stato che cambia prima di cancellare le preferenze; la rimozione da "Chi guarda?" e da una sessione (che resta, anche con un 401 nel frattempo); le preferenze cancellate; un 401 durante la sessione e quello, ignorato, della richiesta di uscita; `refreshUser`, che aggiorna anche il profilo;
  - con `AuthService` e `JellyfinHttp` veri (`session_integration_test.dart`): un 401 aprendo un profilo, un 401 durante la sessione, un accesso che finisce dopo "Annulla" mentre si apre un altro profilo (nei due ordini), il 401 della richiesta di uscita;
  - il cambio di profilo (`changeProfile`): senza party; "Aggiungi profilo"; nel party con la conferma (anche quella di "Aggiungi profilo") e con "Annulla"; l'uscita lenta (3 s); chi ha chiesto il cambio che sparisce; la sessione che cambia durante l'uscita;
  - preferenze del profilo: le chiavi del PC senza profilo, la lettura con il valore del PC, la stringa vuota per la lingua, `forget`; i controller (lingua del profilo aperto o dell'ultimo usato, sottotitoli del profilo e qualità del PC, Discord e modalità del party);
  - router: `/profiles` con `ChoosingProfile`, `/login` per aggiungere, `/home` dopo la scelta; con il router vero, "Chi guarda?" → "Aggiungi profilo" → "Annulla" → "Accedi di nuovo", con l'accesso preparato a ogni apertura del login;
  - `describeError` per `ProfileLimitException`; i testi del piano (`l10n_plan17b_test.dart`).

  Non c'è un test che controlla l'azzeramento dei provider al cambio di profilo: lo fanno i provider che guardano la sessione, come all'uscita di oggi (§2.2).
- **Immagini** (quelli del piano 17c):
  - la galleria: 24 avatar con icone tutte diverse e colori diversi da quelli vicini; ogni avatar è un PNG 512×512; l'anteprima ha il suo lato;
  - la preparazione (`avatar_image_test.dart`): un PNG; oltre 2048 px ridotta; una foto girata raddrizzata secondo l'EXIF, anche grande (ridotta, poi raddrizzata); un file che non è un'immagine; oltre 20 MB e troppi pixel nell'intestazione (anche di un JPEG) senza decodificare; un JPEG con l'intestazione troncata; le parti trasparenti con il colore di fondo dell'app; 16 bit e tavolozza a 8 bit; il lavoro in un isolate;
  - le dimensioni di un JPEG dall'intestazione: il SOF, i byte di riempimento e i marcatori senza lunghezza, un JPEG progressivo e i segmenti saltati per lunghezza, un SOF nascosto dietro `FF 00`, un marcatore che il decoder non legge per lunghezza, intestazioni troncate o rovinate;
  - il ritaglio: i conti, l'immagine che copre sempre il riquadro, trascinamento, cursore e rotella, il cursore letto dallo screen reader; l'uscita JPEG 512×512, l'EXIF (anche il GPS) che non arriva mai al JPEG, un riquadro che esce dall'immagine e si sposta dentro;
  - `AvatarDirectory`: raccolta in 50 ms, massimo 100 voci per chiamata, per nome con l'id della risposta, un risultato e un errore che valgono 10 minuti, `remember` (anche durante una chiamata), le richieste già partite condivise, le chiamate fallite che non coprono un'immagine trovata, id o nome vuoti senza chiamate, `dispose` (anche durante una chiamata);
  - i provider: niente cache senza un profilo aperto (e la sessione non si crea) o senza `avatars`, una cache per profilo (quella di prima si chiude), la funzione che arriva dopo, un avatar sullo schermo che si rilegge dopo 10 minuti;
  - `UserAvatar`: l'immagine sopra l'iniziale con il tag, l'iniziale senza (anche `muted`), `lookup` senza profilo aperto, per nome, con l'id vuoto; l'id normalizzato; decorativo per lo screen reader;
  - `AuthService`: `clientFor`, `isActive`, `updateActiveProfile` solo per il profilo aperto, `updateStoredProfile`, `markProfileExpired`;
  - `SessionController.setProfileImage`: il profilo aperto (sessione e profilo aggiornati), il 401 del profilo aperto (ci pensa il client), la risposta di un altro utente, un profilo non aperto, la rimozione, il 403, il 401 di un profilo non aperto (scaduto), un profilo che non c'è.
- **Widget:**
  - "Chi guarda?": card e apertura, l'indicatore mentre un profilo si apre (gli altri clic non fanno niente), scaduto, aggiungi, niente "Aggiungi profilo" con 5 profili, "Gestisci profili" con la rimozione confermata, Esc (anche con il fuoco su "Fine" o su Rimuovi), profilo senza nome, le card come pulsanti per lo screen reader, fuoco da tastiera (Invio, Tab, l'ultimo profilo usato), la finestra più piccola senza scorrere, l'entrata uno dopo l'altro;
  - menu dell'avatar con le voci nuove: "Aggiungi profilo" che apre l'accesso, la conferma in un party, niente "Aggiungi profilo" con 5 profili;
  - Impostazioni → Account: Cambia profilo ed Esci;
  - login: "Annulla" per aggiungere un profilo; "Accedi di nuovo" con il nome già scritto, l'avviso e "Annulla"; senza nome salvato il fuoco al nome; con un solo profilo niente "Annulla"; "Massimo 5 profili"; l'accesso preparato all'apertura, prima di Quick Connect;
  - righe "Fa parte di";
  - pagina della saga;
  - vista "Saghe";
  - sezione "Saghe" della ricerca;
  - finestra dell'immagine (`avatar_dialog_test.dart`): le tre schede e "Usa questo" solo con un avatar scelto; un avatar della galleria caricato come PNG, poi la finestra chiusa; 403 e altri errori con la finestra che resta; un 401 che la chiude; il messaggio che sparisce cambiando scheda; la finestra più piccola con l'errore (le 4 righe della galleria, avatar da 56 px); gli avatar della galleria come pulsanti con un nome; i pulsanti spenti durante il caricamento; Esc e il clic fuori che non la chiudono durante il caricamento, Esc che la chiude mentre si prepara un'immagine; un caricamento che finisce a finestra chiusa e non chiude la pagina sotto; "Dal PC" annullato, troppo grande, non valido, il ritaglio caricato come JPEG, il ritaglio che resta cambiando scheda, il trascinamento che non cambia scheda; "Rimuovi" spento senza immagine e riuscito con un'immagine; la cache degli avatar aggiornata dopo il caricamento, con gli avatar sullo schermo;
  - gli avatar nei loro posti: il menu dell'avatar, "Chi guarda?" (immagine o iniziale; la matita di "Gestisci profili", spenta per un profilo scaduto), Impostazioni → Account ("Cambia immagine"), amici, richieste e ricerca (per id), la richiesta d'amicizia (per id), la fila e il menu del party (per nome) e gli amici da invitare (per id), la chat (per id, e lo stesso avatar finché il mittente non cambia), le sessioni dell'admin (con il tag di Jellyfin, e senza tag l'iniziale);
  - i testi del piano (`l10n_plan17c_test.dart`).
- **A mano, sul server vero e con l'utente:**
  - Saghe:
    - la riga su un film della Marvel e su Matrix;
    - la pagina "Marvel Universe";
    - la vista "Saghe" e la ricerca "matrix";
    - un utente normale vede le saghe (la seconda istanza di sviluppo, `WONDERFLIX_PROFILE=b`, con un altro account).
  - Profili:
    - l'aggiornamento dalla 0.10.0 senza rifare l'accesso;
    - aggiungere un secondo profilo (password e Quick Connect);
    - "Chi guarda?" al riavvio;
    - il cambio di profilo durante un party;
    - la rimozione;
    - nella scheda Sessioni dell'admin, due dispositivi distinti per i due profili.
  - Immagini:
    - avatar dalla galleria;
    - immagine da file;
    - rimozione;
    - l'immagine che si vede in jellyfin-web, tra gli amici e nel party dell'altra istanza.

## 14. Rischi e punti da verificare

- **Corpo di `POST /UserImage` in base64.** Verificato nel sorgente di Jellyfin 10.11.9 (`ImageController.PostUserImage` legge il corpo con `FromBase64Transform`; un altro `Content-Type` dà 400; risposta 204, §3.2), quindi non serve più una prova sull'account dell'utente prima del piano: la prova vera è quella a mano del 17c. Se Jellyfin volesse i byte grezzi, cambierebbe solo `UserImageApi`.
- **Collezioni nel plugin.** Fatto nel piano 17a: `ICollectionManager.GetCollectionsFolder(false)` e `GetChildren(user, true, …)` sulla cartella e su ogni collezione, come fa `GET /Items?parentId=…` (§7.1). La prova a mano del 2026-10-07 (piano 17a, Task 12) ha confermato l'output del plugin con il token di un utente vero. Sul server nessun utente ha librerie ristrette o limiti parentali, quindi il caso di un titolo che un utente non può vedere è coperto solo dai test del plugin (che controllano che ogni lettura passi per l'utente).
- **`IImageProcessor.GetImageCacheTag` per gli utenti** in Jellyfin 10.11: la firma è la stessa in 10.11.0 e 10.11.9 (`null` senza immagine), e Jellyfin lo usa per `UserDto.PrimaryImageTag`. Che sul server dia lo stesso `PrimaryImageTag` di `/Users`, è **da verificare con la build di prova** del plugin 1.5.0 (piano 17c, Task 2), che non è ancora installata: sul server c'era qualcuno che guardava. Si guarda prima della prova a mano.
- **Limiti accettati delle immagini:** in §12 (immagini non quadrate di jellyfin-web, niente zoom con due dita sul touchpad, Invio nella galleria, `refreshUser` durante un caricamento, rilettura fallita dopo un caricamento riuscito, immagini degli altri con misure enormi decodificate per intero dal motore, Esc che non ferma la preparazione già partita).
- **File scelti costruiti apposta.** Il controllo "intestazione prima di decodificare" (§10.3) segue il pacchetto `image` 4.10.1: formati ammessi, parser JPEG con i soli marcatori che il decoder legge per lunghezza e le componenti nei limiti, niente WebP animati, PNG con la decompressione contata. Il file lo sceglie chi lo carica, quindi il danno resta sul suo PC; se si aggiorna il pacchetto `image`, questi controlli si ricontrollano.
- **Uscita dal party al cambio di profilo:** si verifica che il gruppo SyncPlay perda davvero il membro. Prova a mano del 2026-10-08 (piano 17b, Task 10): l'utente ha confermato che tutto funziona, cambio di profilo compreso.
- **Due WonderFlix aperti insieme** (non di sviluppo) con lo stesso file dei profili: oggi non è un caso previsto, e resta così.

## 15. Piani e release

- **Tre piani:**
  - **17a — saghe:**
    - endpoint `Collections` del plugin, con la funzione `collections`;
    - tutto K1 nell'app.

    Per la prova a mano il plugin si installa sul server come build di prova.
  - **17b — profili:**
    - `ProfileStore` e migrazione;
    - credenziali e DeviceId per profilo;
    - stati e rotte;
    - "Chi guarda?";
    - menu e Impostazioni;
    - preferenze del profilo;
    - correzione dei commenti sul Gestore credenziali.

    Il plugin non cambia. Gli avatar restano le iniziali. Realizzato: le differenze dalla prima versione di questa spec sono scritte nelle sezioni (§9.1–§9.7, §11, §12) e nella decisione 10 del piano.
  - **17c — immagini e release:**
    - endpoint `Users/Avatars` del plugin, con la funzione `avatars`;
    - finestra dell'immagine, galleria, ritaglio, caricamento; "Modifica immagine" in "Gestisci profili" e l'avatar con "Cambia immagine" in Impostazioni → Account;
    - `UserAvatar` e la cache degli avatar (`AvatarDirectory`), anche al posto dell'iniziale di "Chi guarda?" e del `CircleAvatar` del menu dell'avatar;
    - release.

    Realizzato: le differenze dalla prima versione di questa spec sono scritte nelle sezioni (§3.2, §6, §7.2, §9.4, §9.5, §10, §11, §12, §14) e nella decisione 15 del piano. La release (plugin 1.5.0 dal Catalogo, app 0.11.0) è il passo successivo, dopo la prova a mano.
- **Release:**
  - plugin **1.5.0** (collezioni e avatar);
  - poi app **0.11.0 non obbligatoria**, con le note in italiano nella bozza.

  Con il plugin 1.4.0 l'app 0.11.0 funziona, senza saghe e con le iniziali.
- **Alla fine**, in `docs/IDEE.md`:
  - dall'idea 3 escono collezioni e profili, e resta solo il download offline;
  - tra le fatte entra "Spec K — saghe e profili (plugin 1.5.0, app 0.11.0)".

  HDR e firma del codice passano subito tra le esclusioni per scelta dell'utente.
