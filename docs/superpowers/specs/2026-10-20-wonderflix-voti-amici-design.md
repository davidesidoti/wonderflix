# WonderFlix — Spec Q: voti degli amici

- **Data:** 2026-10-20
- **Stato:** approvata il 2026-10-20; piani 23a (plugin) e 23b (app) da scrivere.
- **Ambito:** Spec Q. Realizza l'idea 7 di `docs/IDEE.md` ("Voti degli amici"). A fine film nel watch party ognuno dà un voto da 1 a 10 con un commento facoltativo; i voti si scoprono tutti insieme. Nella scheda del film (o della stagione) restano la media e i commenti degli amici.

## 1. Obiettivo

Portare nell'app il rito che il gruppo fa già: finito un film nel watch party, ognuno dice il suo voto da 1 a 10, più o meno tutti insieme e senza un ordine, a volte con un commento. Settimane dopo, nella scheda del film, si ritrova com'era andata.

- **Nel party:** il voto sta nel post-play, mentre scorrono i titoli di coda. Ognuno vota per conto suo, e i voti restano nascosti finché non si scoprono per tutti nello stesso momento.
- **Nella scheda:** sotto il titolo c'è la riga "Voti degli amici", con la media e una card per ogni amico (voto e commento).
- **Dopo:** chi ha visto il titolo può votare dalla scheda in qualsiasi momento, e può cambiare o togliere il suo voto.

**Nota sul modello:** non è il voto TMDB/IMDb che Jellyfin mostra già (`CommunityRating`, usato anche dal filtro "Belli/Brutti" della 0.16.1). Questo voto resta tra gli utenti del server ed è visibile solo agli amici di WonderFlix (Spec F).

## 2. Situazione di partenza

App 0.16.1, plugin 1.10.1, Jellyfin 10.11.9 su Ultra.cc.

- **Party** (Spec E, F, H):
  - i membri sono quelli del gruppo SyncPlay (`IGroupDirectory.GetParticipants`, nomi utente);
  - il canale del party (`PartyHub`) inoltra azioni, chat e reazioni;
  - gli avvisi per utente (`SocialEvent`, per esempio `MatchUpdated`) vanno a tutte le sessioni dell'app di quell'utente;
  - chi ha creato il party è `PartyView.CreatorId` (`PartyDirectory`). Sta solo in RAM, si perde al riavvio del plugin, non arriva all'app, e i gruppi creati da jellyfin-web non ce l'hanno.
- **Match** (Spec P): `MatchRoom`/`MatchService` sono il precedente più vicino, cioè uno stato condiviso in memoria con `Rev`, timer su `TimeProvider`, avvisi raggruppati e pulizia periodica.
- **Post-play** (`post_play.dart`, `player_screen.dart`):
  - ci sono due zone di fine. `EndZone.credits` (Outro noto) apre il post-play completo, cioè il film piccolo in alto a sinistra e le informazioni del prossimo titolo. `EndZone.lastSeconds` (ultimi 30 s senza Outro) mostra la scheda piccola;
  - nel party il "prossimo" è la voce successiva della coda (`nextEntry`). Non c'è il conto alla rovescia, e a coda vuota non compare niente;
  - a video finito ogni client del party chiama `nextItem` (i doppioni li scarta il server), e chiunque può premere "Riproduci ora".
- **Scheda:**
  - `movie_detail_view.dart`: `DetailHeader`, poi Cast, Saghe e Simili;
  - `series_detail_view.dart`: `DetailHeader`, poi le schede delle stagioni (`_SeasonTabs`) con gli episodi, Cast e Simili;
  - lo stato di visione arriva da `watchUserData` (`played`), anche per le stagioni.
- **Archivi del plugin:** `InboxStore`, `RecommendationStore` e simili, con scrittura atomica, `.bad` se il file è illeggibile e un `*Book` in memoria.
- **Admin:** nel plugin gli endpoint admin usano `Policies.RequiresElevation`; nell'app c'è la scheda WonderFlix della dashboard (`wonderflix_tab.dart`).
- **Niente dialog** nell'app: le scelte stanno in pannelli e menu.

## 3. Decisioni

Prese con l'utente nel brainstorming del 2026-10-20:

1. **Scala da 1 a 10**, con un commento breve facoltativo.
2. **Si vota nel party**, a fine film o a fine stagione per le serie (dopo l'ultimo episodio della stagione). Il gruppo guarda insieme solo nei watch party.
3. **Il voto sta dentro il post-play** (bozza A): film piccolo in alto a sinistra, sotto il prossimo titolo della coda, a destra il pannello del voto.
4. **I voti si scoprono tutti insieme**, appena succede la prima di queste cose:
   - hanno votato tutti i presenti;
   - sono passati **2 minuti**;
   - chi ha creato il party preme **"Scopri i voti"**.
5. **Chi esce dal party prima di votare**, o preme "Salta", non viene aspettato e non entra nella media del party.
6. **Dopo il party si vota dalla scheda**: lo può fare chi ha visto il titolo secondo Jellyfin, anche se l'ha visto da solo.
7. **Visibilità:** nella scheda si vedono la media e i commenti dei **propri amici**; chi non è amico non vede niente. Nella schermata di fine party si vedono i voti di tutti i presenti.
8. **Modifica e cancellazione** del proprio voto sono libere e non avvisano nessuno.
9. **L'admin può cancellare un commento** dalla dashboard.
10. **Nella scheda** i voti stanno in una riga "Voti degli amici" sotto il titolo, prima del Cast.
11. **Cambio di titolo mentre si vota** (decisione presa durante la revisione dello spec): non si blocca. La votazione continua sopra il nuovo titolo (§7.2).

**Le mie scelte** (proposte nel brainstorming e accettate dall'utente con "va bene"):

12. Un voto per persona e per titolo, dove il titolo è un film o una stagione. Se si riguarda un film, nel party il pannello parte dal voto di prima, che si può confermare o cambiare.
13. Nella scheda il proprio voto è a parte e non entra nella media, che è "degli amici".
14. L'admin cancella il commento ma lascia il voto, quindi la media non cambia.
15. Chi vota dopo che i voti sono stati scoperti salva comunque il voto.
16. Voti e commenti li tiene il plugin sul server.

## 4. Perimetro

### Incluso

- **Plugin 1.11.0:** archivio dei voti, votazione di fine party in memoria, endpoint per la scheda, endpoint admin per i commenti, avviso `RatingRoundUpdated`, funzione `ratings` in `Info`.
- **App 0.17.0:**
  - pannello del voto nel post-play del party, con la coda che aspetta;
  - riga "Voti degli amici" nella scheda dei film e delle serie (per stagione), con il proprio voto modificabile;
  - scheda Commenti nella dashboard admin;
  - testi it/en.

### Escluso

- Voti agli episodi singoli, alle serie intere e alle saghe.
- Avvisi nella cassetta quando un amico vota.
- Classifiche ("i più votati dagli amici"), righe della Home, ordinamento o filtri del catalogo per voto degli amici.
- Risposte o reazioni ai commenti.
- Voti visibili a chi non è amico (salvo i presenti a fine party).
- Votazione a fine film fuori dal party (da soli si vota dalla scheda).

## 5. Architettura

```
Fine film nel party
  App ──POST Ratings/Rounds {GroupId, ItemId}──▶ Plugin: RatingRound in memoria (per gruppo)
  App ──POST …/Vote | …/Skip | …/Reveal──▶ Plugin ──▶ ratings.json (voto salvato subito)
  Plugin ──RatingRoundUpdated──▶ app di ogni presente (stato visto da quel destinatario)

Scheda
  App ──GET Ratings?itemId=──▶ Plugin (filtra: amici, CanSee) ──▶ media, card, voto proprio
  App ──PUT / DELETE Ratings/{itemId}──▶ Plugin ──▶ ratings.json

Dashboard admin
  App ──GET Ratings/Admin/Comments──▶ Plugin;  DELETE …/{userId}/{itemId} toglie il commento
```

- L'archivio (`ratings.json`) è la sola fonte dei voti. La votazione di fine party (`RatingRound`) tiene solo chi deve votare, chi ha votato e quando scoprire i voti, e si perde al riavvio del plugin come le sale del match.
- **Cosa decide il plugin:** quale titolo si vota (film, oppure stagione se l'episodio è l'ultimo della stagione), chi è presente, quando i voti si scoprono e chi vede cosa.
- **Cosa fa l'app:** apre la votazione al momento giusto e tiene ferma la coda finché i voti non si scoprono.

## 6. Plugin 1.11.0

### 6.1 Archivio (`ratings.json`)

- File in `<PluginConfigurationsPath>/WonderFlixWatchParty/`, con le stesse regole di `RecommendationStore`:
  - caricamento pigro sotto lock;
  - scrittura atomica;
  - file illeggibile rinominato in `.bad`, si riparte vuoti;
  - un errore del disco non annulla la modifica in memoria.
- **Contenuto:** `{"Version": 1, "Items": {"<itemId>": [{"UserId", "Score", "Comment", "CreatedAt", "UpdatedAt"}]}}`.
  - `itemId` è l'id di un film o di una stagione, in formato `N`;
  - `Score` è un intero da 1 a 10;
  - `Comment` manca se è vuoto o se è stato tolto dall'admin;
  - le date sono ISO-8601 UTC.
- **Un voto per utente e titolo:** votare di nuovo sostituisce `Score` e `Comment` (anche togliendo il commento) e aggiorna `UpdatedAt`; `CreatedAt` resta quello del primo voto.
- **Commento:** stesse regole dei messaggi dei consigli (Spec N §6.2). È testo semplice; gli a capo e gli altri caratteri di controllo diventano spazi, e gli spazi ai bordi si tolgono. Il massimo è 200 punti di codice; oltre si risponde 400.
- **Pulizia periodica** (`RatingsHostedService`, ogni 5 minuti, con il suo `try/catch`): toglie i voti degli utenti che non esistono più e quelli dei titoli che non esistono più. Una stagione cancellata e poi riaggiunta da Jellyfin con un id nuovo perde i voti (accettato).

### 6.2 Votazione di fine party (`RatingRound`, in memoria)

Una votazione per gruppo SyncPlay alla volta, con la chiave `GroupId`.

- **Apertura:** `POST Ratings/Rounds {GroupId, ItemId}`.
  - Chi chiama deve essere fra i presenti del gruppo, altrimenti 409 `NotMember`.
  - `ItemId` è quello che il party sta guardando:
    - un **film**: si vota il film;
    - un **episodio che è l'ultimo della sua stagione** fra quelli presenti nella libreria (nessun episodio con numero più alto nella stessa stagione): si vota la stagione;
    - qualunque altro caso (episodio intermedio, altro tipo, chi chiama non vede il titolo): 400.
  - Se il gruppo ha già una votazione aperta per lo stesso titolo, la risposta è quella, senza aprirne un'altra: aprono tutti i client, e vale la prima richiesta. Una votazione per un titolo diverso viene chiusa e sostituita.
- **Presenti:** i partecipanti attuali del gruppo SyncPlay, ricalcolati a ogni cambio, a ogni voto e alla pulizia ogni 30 s.
  - Chi esce viene tolto dall'attesa e il suo voto non conta nella media del party: è la decisione 5. Se ha già votato, il voto resta salvato nell'archivio.
  - Chi entra durante la votazione si aggiunge in attesa.
- **Stato di ogni presente:** `Waiting`, `Voted` o `Skipped`.
- **Fasi:** `Voting`, poi `Revealed`. Si passa a `Revealed` quando succede la prima di queste cose:
  - non c'è più nessuno in `Waiting`;
  - sono passati 2 minuti dall'apertura (timer su `TimeProvider`);
  - chi ha creato il party chiama `Reveal`.
  Se il creatore non è noto (riavvio del plugin, gruppo nato fuori da WonderFlix), restano solo le prime due.
- **Voto nella votazione** (`…/Vote {Score, Comment}`): salva subito nell'archivio (§6.1), senza chiedere che il titolo risulti visto (a fine film Jellyfin potrebbe non averlo ancora segnato), e passa chi vota a `Voted`. È ammesso anche in `Revealed`: è la decisione 15, e il voto compare anche nei risultati della votazione. `Skip` passa a `Skipped`, ed è ammesso solo in `Voting`.
- **Fine:** la votazione si scarta 10 minuti dopo `Revealed`, quando il gruppo non esiste più, oppure quando se ne apre una per un altro titolo.
- **Stato visto da un presente** (`RatingRoundDto`):
  - `GroupId`, `ItemId` (film o stagione), `Phase`, `Rev`, `EndsAt` (apertura + 2 min);
  - `CanReveal`: chi guarda è il creatore e la fase è `Voting`;
  - `Mine`: il voto di chi guarda nell'archivio, se c'è, per partire dal voto di prima (decisione 12);
  - `Voters`: `{UserId, Name, Status}` per ogni presente, in ordine di nome;
  - solo in `Revealed`, `Results`: `{UserId, Name, Score, Comment}` di chi ha votato fra i presenti, dal voto più alto, più `Average`, la media con un decimale arrotondata a metà in su.
  - In `Voting` voti e commenti degli altri non escono mai.
- **Avviso:** `SocialEventTypes.RatingRoundUpdated` con lo stato di quel destinatario va alle sessioni dell'app di ogni presente, raggruppato come `MatchUpdated` (al più uno ogni 250 ms).

### 6.3 Endpoint (sotto `/WonderFlixWatchParty`)

`RatingsController`, con la policy `SyncPlayHasAccess` come amici e consigli. Chi chiama si ricava dal token. Il plugin **non risponde mai 404**, e gli id sono stringhe senza vincoli di rotta.

| Metodo e percorso | Corpo / risposta |
|---|---|
| `POST Ratings/Rounds` `{GroupId, ItemId}` | `RatingRoundDto` (§6.2) |
| `GET Ratings/Rounds/{groupId}` | `RatingRoundDto`, oppure `{}` se non c'è una votazione aperta o chi chiama non è presente |
| `POST Ratings/Rounds/{groupId}/Vote` `{Score, Comment}` | `RatingRoundDto`; 400 per un voto fuori da 1–10 o un commento troppo lungo |
| `POST Ratings/Rounds/{groupId}/Skip` | `RatingRoundDto` |
| `POST Ratings/Rounds/{groupId}/Reveal` | `RatingRoundDto`; 409 `NotCreator` |
| `GET Ratings?itemId=` | `{CanRate, Mine?, Average?, Count, Friends: [{UserId, Name, Score, Comment?, UpdatedAt}]}` |
| `PUT Ratings/{itemId}` `{Score, Comment}` | 204; 400 se il titolo non è un film o una stagione, chi chiama non lo vede, non lo ha visto e non ha già un voto (stessa regola di `CanRate`), o il voto non è valido |
| `DELETE Ratings/{itemId}` | 204, anche se il voto non c'era |

Per le votazioni gli errori 409 usano un valore di `RatingReasons` (`NotMember`, `NotCreator`, `Closed`), come `MatchReasons`.

**`GET Ratings`:**
- 400 se il titolo non è un film o una stagione, o chi chiama non lo vede (`CanSee`).
- `Friends` contiene i voti degli **amici attuali** di chi chiama (`FriendService.AreFriends`), senza gli utenti disabilitati, dal più recente (`UpdatedAt`).
- `Average` è la media dei voti in `Friends`, con un decimale arrotondato a metà in su; manca se `Friends` è vuoto. `Count` è il numero dei voti in `Friends`.
- `Mine` è il voto di chi chiama, a parte (decisione 13).
- `CanRate` vale vero se chi chiama ha visto il titolo:
  - **film:** `Played` nei suoi dati utente;
  - **stagione:** tutti gli episodi della stagione presenti nella libreria risultano visti. È una sola domanda alla libreria, cioè episodi della stagione con `IsPlayed = false`, limite 1.

  Se `Mine` c'è, `CanRate` vale vero comunque, così chi ha votato nel party può sempre cambiare il voto.
- La visibilità per amicizia vale solo per la scheda. Le votazioni di fine party mostrano tutti i presenti, che è la decisione 7.

**Limite:** `LimitTypes.Ratings`, 60 scritture all'ora per utente (`Vote`, `PUT`, `DELETE`), con 429 oltre. `Rounds`, `Skip` e `Reveal` non contano.

### 6.4 Admin: commenti

Endpoint con `Policies.RequiresElevation` sul metodo, come gli annunci della cassetta:

| Metodo e percorso | Corpo / risposta |
|---|---|
| `GET Ratings/Admin/Comments?before=` | `{Items: [{UserId, UserName, ItemId, Title, Score, Comment, UpdatedAt}], Next?}`: i voti con un commento, dal più recente, 50 per pagina; `before` è l'`UpdatedAt` più vecchio della pagina precedente, `Next` manca all'ultima pagina |
| `DELETE Ratings/Admin/Comments/{userId}/{itemId}` | 204: toglie `Comment` e lascia `Score` (decisione 14); 204 anche se non c'era |

- `Title` è il nome leggibile del titolo, cioè "Il Padrino (1972)" oppure "Breaking Bad · Stagione 2". Se il titolo non c'è più, è vuoto.
- Ogni cancellazione va nel log di controllo con `AdminCaller.Describe`, come le altre azioni admin: solo gli id, mai il testo.

### 6.5 `Info`, log, privacy

- `Features` aggiunge `"ratings"`, `Version` diventa "1.11.0" (e va aggiornato anche `InfoControllerTests`), `Protocol` resta 1.
- **Log:** mai titoli, commenti o nomi, solo id e numeri.
  - `Debug` per apertura, cambio di fase e chiusura di una votazione, con la ragione: tutti votato, tempo scaduto o creatore;
  - `Warning` per file illeggibile, errori di scrittura ed errori della libreria.

## 7. App 0.17.0

### 7.1 Nucleo

- **Modelli** in `lib/core/social/`:
  - `RatingRound` (con `RatingVoter` e `RatingResult`);
  - `ItemRatings` (`canRate`, `mine`, `average`, `count`, `friends`);
  - `FriendRating`;
  - `AdminComment`.
- **`SocialApi`:** `openRatingRound`, `ratingRound`, `voteInRound`, `skipRound`, `revealRound`, `itemRatings`, `rate`, `deleteRating`, con gli stessi metodi in `FakeSocialApi`. `PluginAdminApi` aggiunge `ratingComments(before)` e `deleteRatingComment(userId, itemId)`.
- **`SocialFeatures.ratings`** viene dalla funzione `ratings` del plugin e vale solo con l'accesso ai watch party, come gli amici.
- **`RatingRoundUpdated`** si legge in `parseSocialEvent`; uno stato con `rev` non più nuovo di quello che l'app ha già viene scartato, come nel match.

### 7.2 Pannello del voto nel post-play del party

**Quando si apre.** Nel party, con la funzione `ratings`, se il titolo è un film o un episodio. Il momento è il primo di questi due:
- l'inizio della zona `credits` (Outro noto);
- il video finito, se l'Outro non c'è.

L'app chiama `POST Ratings/Rounds`. Se risponde 400 (per esempio un episodio non ultimo della stagione), non c'è niente da votare e il post-play resta quello di oggi. Nella zona `lastSeconds` senza Outro la scheda piccola resta come oggi, fino alla fine del video.

**Disposizione** (bozza A, `.superpowers/brainstorm/…/fine-party-v2.html` e `rivelazione-scheda.html`):
- in alto a sinistra il film piccolo, come oggi;
- sotto, il prossimo titolo della coda. Se la coda è vuota, questo riquadro non c'è e il post-play compare lo stesso, solo per il voto;
- a destra, al posto delle informazioni del prossimo titolo, il pannello del voto.

**Pannello in `Voting`:**
- titolo "Il tuo voto · *Il Padrino*", oppure "*Breaking Bad* · Stagione 2";
- i numeri da 1 a 10 in fila, selezionabili anche con le frecce e con i tasti 1–9 e 0 (= 10). La selezione parte da `Mine`, se c'è;
- il campo del commento, facoltativo, fino a 200 caratteri, con lo stesso comportamento del messaggio dei consigli (Invio non va a capo);
- i pulsanti **Vota** (spento finché non c'è un numero) e **Salta**. Dopo il voto il pannello mostra "Hai votato *8*" con "Cambia", che riapre il voto finché la fase resta `Voting`;
- "Hanno votato 2 su 4" e l'elenco dei presenti con la spunta per chi ha votato o "ha saltato". Mai il voto degli altri;
- il tempo che resta (da `EndsAt`) in piccolo;
- **Scopri i voti**, solo con `CanReveal`.

**Pannello in `Revealed`:** in alto la media del party, grande, e il numero dei voti; poi una riga per ogni risultato con avatar, nome ("Tu" per sé), voto e commento. Le righe entrano tutte insieme con la stessa animazione, che rispetta le animazioni ridotte. Sotto c'è "Puoi cambiare il tuo voto dalla scheda del film".

**Coda ferma durante `Voting`:**
- l'app non chiama `nextItem` a video finito;
- al posto di "Riproduci ora" il pulsante dice "In attesa dei voti" ed è spento;
- se il video finisce mentre si vota, il player resta sull'ultimo fotogramma con il post-play aperto.

**Dopo `Revealed`:**
- se il video è già finito, parte un conto alla rovescia di **15 s** sul pulsante "Riproduci ora" (lo stesso `PlayNowButton`), poi `nextItem` come oggi;
- se il video sta ancora andando, si torna al comportamento di oggi: "Riproduci ora" disponibile e `nextItem` a fine video;
- a coda vuota non parte niente, e il pannello resta finché qualcuno chiude il post-play.

**Errori:**
- se `POST Ratings/Rounds` fallisce (rete, plugin riavviato), il post-play resta quello di oggi, la coda non si ferma e c'è una riga di log;
- se la votazione sparisce a metà (`GET` → `{}`), il pannello dice "Votazione non disponibile: puoi votare dalla scheda" e la coda torna libera.

**Chiudere il post-play** (Esc, "Guarda i titoli") chiude il pannello solo per sé, senza saltare la votazione. Chi non ha votato resta in `Waiting` fino ai 2 minuti. *(Mie scelte:)*
- **cambio di titolo durante `Voting`** (coda, "successivo", azione di un altro membro): è permesso (decisione dell'utente nella revisione dello spec). La votazione continua sopra il nuovo titolo con la pillola "Voti del party" fino a quando i voti si scoprono; il pannello si riapre da lì e in `Revealed` la pillola diventa "Voti scoperti" finché la votazione non viene scartata (10 minuti) o la si chiude. Il plugin non chiude la votazione per il cambio di titolo: solo l'apertura di una votazione per un altro titolo la sostituisce (§6.2);
- la coda ferma e il conto di 15 s dopo `Revealed` dipendono dallo stato della votazione nel player, non dal post-play aperto: anche se tutti lo hanno chiuso, dopo `Revealed` a video finito la coda riparte;
- finché la votazione esiste, con il post-play chiuso, in basso a destra resta una pillola "Voti del party" (stile `PartyNoticePill`) che lo riapre, per votare o vedere i risultati.

### 7.3 Riga "Voti degli amici" nella scheda

- **Dove:** nel dettaglio dei film, subito dopo `DetailHeader` e prima del Cast. Nel dettaglio delle serie, dopo `DetailHeader` e prima delle schede delle stagioni, con i voti della **stagione scelta** nelle schede: il titolo dice "Voti degli amici · Stagione 2" e cambia con la scheda. Non c'è nel dettaglio degli episodi.
- **Quando si vede:** con la funzione `ratings`, e solo se c'è almeno un voto degli amici oppure se chi guarda può votare (`CanRate`). Altrimenti la riga non c'è. Mentre carica non occupa spazio, e un errore la nasconde (una riga di log).
- **Contenuto** (bozza "Riga sotto il titolo"):
  - a sinistra un riquadro con la media ("7,7", con la virgola in italiano) e "3 amici";
  - poi una card per ogni amico, con avatar, nome, voto e commento su al massimo 3 righe con ellissi. Le card scorrono di lato come le altre righe; il passaggio del mouse mostra il commento intero in un tooltip;
  - nessun amico ha votato ma si può votare: al posto della media "Ancora nessun voto degli amici";
  - a destra nell'intestazione della riga: "Il tuo voto: 8 ✎" se `Mine` c'è, "Vota" se `CanRate` e `Mine` non c'è, niente negli altri casi.
- **Voto dalla scheda:** "Vota" o "Il tuo voto" aprono un pannello laterale a destra di 360 px, lo stesso `ShellSidePanel` di Consigli e Amici. Dentro ci sono:
  - locandina e titolo;
  - i numeri da 1 a 10;
  - il commento;
  - **Salva**;
  - **Togli il mio voto**, solo se `Mine` c'è.

  Dopo il salvataggio il pannello si chiude e la riga si rilegge. Un errore lascia il pannello aperto con "Voto non salvato" (con 429: "Troppi voti: riprova più tardi").
- La riga si rilegge a ogni apertura della scheda e quando cambiano i dati di visione dell'utente, così dopo "Visto" compare "Vota".

### 7.4 Dashboard admin: commenti

- **Card "Commenti degli utenti"** nella scheda WonderFlix (`wonderflix_tab.dart`), con l'elenco di `GET Ratings/Admin/Comments`. Per ogni commento ci sono nome, titolo, voto, commento intero, data relativa e un pulsante **Cancella commento**. In fondo c'è "Altri" finché arriva `Next`.
- **Conferma** con `AdminConfirmDialog`, come le altre azioni distruttive della dashboard. Dopo la cancellazione la voce sparisce dall'elenco.
- **Senza la funzione `ratings`** la card dice "Serve il plugin 1.11.0".

### 7.5 Versione

L'app 0.17.0 è **obbligatoria** (min-version 0.17.0) perché un'app 0.16.x in un party a fine film chiama `nextItem` e farebbe ripartire la coda per tutti mentre si vota. *(Mia scelta.)*

## 8. Senza plugin ed errori

- **Plugin senza `ratings`** (< 1.11.0): niente pannello nel post-play, niente riga nella scheda, card admin con il motivo e nessuna chiamata.
- **Riavvio del plugin durante una votazione:** la votazione si perde, l'app mostra "Votazione non disponibile" (§7.2) e i voti già dati restano nell'archivio.
- **Amicizia tolta:** i voti di quella persona spariscono dalla scheda alla lettura successiva.
- **Utente cancellato:** i suoi voti escono alla pulizia periodica e intanto non compaiono, perché l'utente non esiste.
- **Permessi cambiati:** `GET Ratings` risponde 400 a chi non vede più il titolo, e la riga non si vede.

## 9. Testi nuovi (ARB, it + en)

| Chiave | it | en |
|---|---|---|
| `ratingYourVote` | Il tuo voto | Your rating |
| `ratingVote` | Vota | Rate |
| `ratingSkip` | Salta | Skip |
| `ratingChange` | Cambia | Change |
| `ratingVoted` | Hai votato {score} | You rated it {score} |
| `ratingVotedCount` | Hanno votato {voted} su {total} | {voted} of {total} have rated |
| `ratingSkipped` | ha saltato | skipped |
| `ratingReveal` | Scopri i voti | Reveal ratings |
| `ratingWaiting` | In attesa dei voti | Waiting for ratings |
| `ratingPartyAverage` | media del party · {count} voti | party average · {count} ratings |
| `ratingYou` | Tu | You |
| `ratingChangeLater` | Puoi cambiare il tuo voto dalla scheda del film | You can change your rating from the title page |
| `ratingRoundUnavailable` | Votazione non disponibile: puoi votare dalla scheda | Rating unavailable: you can rate from the title page |
| `ratingCommentHint` | Commento (facoltativo) | Comment (optional) |
| `ratingFriendsRow` | Voti degli amici | Friends' ratings |
| `ratingFriendsRowSeason` | Voti degli amici · {season} | Friends' ratings · {season} |
| `ratingFriendsCount` | {count, plural, =1{1 amico} other{{count} amici}} | {count, plural, =1{1 friend} other{{count} friends}} |
| `ratingNoFriendsYet` | Ancora nessun voto degli amici | No ratings from friends yet |
| `ratingMine` | Il tuo voto: {score} | Your rating: {score} |
| `ratingSave` | Salva | Save |
| `ratingRemove` | Togli il mio voto | Remove my rating |
| `ratingNotSaved` | Voto non salvato | Rating not saved |
| `ratingTooMany` | Troppi voti: riprova più tardi | Too many ratings: try again later |
| `adminCommentsTitle` | Commenti degli utenti | User comments |
| `adminCommentDelete` | Cancella commento | Delete comment |
| `adminCommentsNeedPlugin` | Serve il plugin 1.11.0 | Requires plugin 1.11.0 |

I testi della conferma admin e gli altri minori li sceglie il piano.

## 10. Sicurezza e privacy

- I voti e i commenti di un utente li vedono solo:
  - i suoi amici, nella scheda;
  - i presenti alla stessa votazione di fine party;
  - l'admin, nella dashboard.
- Il plugin filtra sempre lato server; l'app non riceve mai voti che non deve mostrare.
- **In `Voting`** il plugin non manda mai voti e commenti degli altri, nemmeno nell'avviso.
- **Controllo dell'appartenenza:** ogni chiamata a `Rounds/{groupId}` verifica che chi chiama sia fra i partecipanti del gruppo SyncPlay.
- I commenti sono testo semplice, ripulito come nel §6.1; l'app li mostra come testo e mai come markup.
- Nei log ci sono solo id e numeri.

## 11. Test

### 11.1 Plugin (xUnit)

- **Archivio:**
  - voto nuovo e voto sostituito, con `CreatedAt` che resta quello del primo voto;
  - pulizia del commento e limite di 200;
  - file illeggibile rinominato in `.bad`;
  - pulizia di utenti e titoli spariti.
- **Votazione:**
  - apertura idempotente e sostituzione con un titolo diverso;
  - film, episodio ultimo della stagione ed episodio intermedio (400);
  - i tre modi di scoprire i voti, con il timer su `FakeTimeProvider`;
  - creatore non noto: niente `CanReveal`;
  - chi esce non viene aspettato, chi entra si aggiunge;
  - in `Voting` i voti degli altri non escono;
  - voto dopo `Revealed`;
  - scarto dopo 10 minuti.
- **Scheda:**
  - filtro amici, utenti disabilitati, `Mine` a parte e media arrotondata;
  - `CanRate` per film e stagione, e vero anche con `Mine`;
  - 400 per titolo non visibile o non visto.
- **Admin:** paginazione, cancellazione che lascia il voto, policy.
- **Altro:** limite 429, `Info` con `ratings` e 1.11.0.

### 11.2 App

- Parsing dei modelli e di `RatingRoundUpdated`, con lo scarto per `rev`.
- **Post-play:**
  - apertura alla zona credits o a video finito;
  - nessun pannello con 400;
  - coda ferma in `Voting` e conto alla rovescia di 15 s dopo `Revealed` a video finito;
  - coda vuota;
  - "Scopri i voti" solo con `CanReveal`;
  - tasti 1–0;
  - errori.
- **Riga della scheda:** visibile o nascosta, stagione scelta, pannello Salva/Togli.
- **Card admin:** elenco, "Altri", cancellazione.

### 11.3 Prova a mano

Si fa sul server con due istanze dell'app in un party, su un film breve con Outro e poi sull'ultimo episodio di una stagione. Si provano:
- voti scoperti per tutti votato, per tempo scaduto e con il pulsante;
- uscita dal party durante la votazione;
- voto dalla scheda dopo il party;
- cancellazione di un commento dalla dashboard.

## 12. Da verificare sul sorgente di Jellyfin 10.11.9

- **"Ultimo episodio della stagione":** cioè il numero di episodio più alto fra gli episodi della stagione presenti nella libreria. Va verificato come si comportano gli episodi doppi (`IndexNumberEnd`) e gli speciali (stagione 0, che si vota come le altre).
- **`IsPlayed = false` sugli episodi di una stagione:** controllare che consideri i dati dell'utente della query e ignori gli episodi mancanti (`IsMissing`, `LocationType.Virtual`).
- **Momento in cui Jellyfin segna `Played`** a fine film in SyncPlay: serve a sapere se basta `Played` o se va considerata anche la percentuale vista. Non cambia il voto nel party, che non lo richiede.

## 13. Piani e release

- **Piano 23a — plugin 1.11.0:** archivio, votazione, endpoint, admin, `Info`, test, build di prova sul server.
- **Piano 23b — app 0.17.0:** nucleo, pannello del post-play con la coda ferma, riga della scheda, card admin, testi, test, prova a mano.
- **Release:**
  - tag del plugin, poi manifest e Catalogo;
  - app 0.17.0 obbligatoria, con le note in italiano scritte nella bozza di GitHub;
  - l'idea 7 di `docs/IDEE.md` passa fra le fatte.
