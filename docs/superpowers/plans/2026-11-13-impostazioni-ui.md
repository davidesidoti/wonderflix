# Piano: Impostazioni, nuova UI

Spec: `docs/superpowers/specs/2026-11-13-impostazioni-ui-design.md` (le
"decisioni" citate sotto sono quelle della spec). Bozze:
`docs/superpowers/specs/2026-11-13-impostazioni-bozze/impostazioni.html`.
Worktree `.claude/worktrees/impostazioni-ui`, branch `impostazioni-ui`.
Un compito alla volta (toccano gli stessi file), un commit per compito.

Comandi (da `app/`, Git Bash, prima `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`):
`flutter gen-l10n`, `flutter analyze`, `flutter test test/features/settings`
(e `flutter test` intero alla fine di ogni compito).

## Task 1: Kit delle righe e testi

- `lib/features/settings/settings_kit.dart`:
  - `enum SettingsScope { device, account, jellyfin }` e
    `SettingsSectionTitle(title, {scope, key})`: Bebas 24, padding top 32
    bottom 12, a destra icona (Lucide `monitor` / `cloud`) e testo muted 12.
    Il testo di `device` dipende dalla piattaforma: PC "Questo PC", web
    "Questo dispositivo", TV "Questa TV".
  - `SettingsRow({label, hint, trailing, onTap, indent = 0})`: etichetta e
    aiuto a sinistra, `trailing` a destra, padding 14×11 (+ indent a
    sinistra). Nello stretto, se `trailing` è largo (parametro
    `wideTrailing: true`), va sotto l'etichetta.
  - `SettingsSwitchRow({key, label, hint, value, onChanged, indent})`: la
    chiave va sullo `Switch` (i test di oggi cercano `SwitchListTile` per
    chiave: aggiornarli a `Switch`/riga), tutta la riga attiva (InkWell);
    `onChanged == null` = disattivata (opacità 0.45).
  - `SettingsDropdown<T>({key, value, items, onChanged})`: `DropdownButton`
    dentro `DropdownButtonHideUnderline`, riquadro bordo `WfColors.border`,
    raggio 6, sfondo `WfColors.surface`, padding orizzontale 10; dentro
    `TvFocusBorder`. La chiave resta sul `DropdownButton`.
  - Le righe si mettono in `AdminList` (`features/admin/admin_kit.dart`).
- Tutti i testi nuovi della spec in `l10n/app_it.arb` e `app_en.arb`
  (anche quelli TV: una spiegazione per riga TV, "Indietro per chiudere",
  "Non caricate, riprova", "Vale solo su questa TV", "Salvate sul tuo
  account: valgono in tutti i client Jellyfin", nome della riga
  Aggiornamento). `settingsQuickConnect` cambia valore.
- Test: `test/features/settings/settings_kit_test.dart`.

## Task 2: Sezioni come righe, nuovo ordine

- `settings_screen.dart`: sezioni nell'ordine e con gli id della decisione
  1, titolo con `SettingsSectionTitle` e scope. Il segmentato della lingua
  esce dal file e va nella sezione App.
- `player_settings_section.dart` → sezione Riproduzione: qualità (riga con
  `SettingsDropdown`, aiuto `settingsQualityHint`), prossimo episodio, salta
  intro, decodifica hardware (non web, aiuto) in un `AdminList`; sotto la
  nota "Le modifiche valgono dal prossimo video.". Niente dimensione dei
  sottotitoli. Su TV questo widget non si usa più dopo il compito 7: fino
  ad allora resta com'è per la TV (ramo `tv`).
- `language_settings_section.dart` → sezione Audio e sottotitoli: tre righe
  con `SettingsDropdown` + riga Dimensione (segmentato, aiuto
  `settingsSubtitleSizeHint`, `wideTrailing`). Via `settingsLanguagesHint`.
- `appearance_settings_section.dart` → sezione App: riga Lingua dell'app
  (segmentato) e riga Animazioni (segmentato, aiuto di oggi).
- `discord_settings_section.dart`: righe, le due dipendenti con indent 20.
- `home_settings_section.dart`: via `homeRowsAllPcs` (scope nel titolo).
- `support_section.dart`: invariato salvo l'aiuto.
- TV: finché non c'è il compito 7 la TV deve funzionare come oggi (stesse
  voci: lingua, player, lingue di riproduzione, versione, aggiornamento).
- Aggiornare `settings_test.dart` e gli altri test toccati.

## Task 3: Navigazione

- `settings_nav.dart`: `SettingsRail` (largo, 208 px, come `AdminRail`:
  titolo Bebas, voci icona+nome, separatori tra gruppi, versione in fondo)
  e `SettingsSectionStrip` (stretto, fila orizzontale fissa, voce accesa
  tenuta in vista). Entrambe ricevono le sezioni visibili, la sezione
  accesa e `onSelect`.
- `SettingsScreen`: una `GlobalKey` per titolo di sezione; `section` accetta
  ogni id; scroll spy su `_scroll` (voce = ultima sezione il cui titolo è
  sopra un terzo dell'altezza; in fondo l'ultima). Nel largo
  `Row[SettingsRail, Expanded(scroll)]`, titolo grande solo nello stretto;
  nello stretto `Column[strip, Expanded(scroll)]` sempre presente (vedi
  gotcha sulle ListView ricreate). TV invariata.
- `openHomeSettings` resta. Test: clic su una voce scorre; scorrendo la voce
  accesa cambia; `?section=playback` apre lì; nello stretto c'è la fila.

## Task 4: Notifiche a gruppi

Decisione 4 in `notifications_settings_section.dart`. Test: conteggio,
interruttore del gruppo (accende gli spenti / spegne tutti), un errore =
un avviso, gruppo da un tipo senza freccia, aperti/chiusi iniziali nel
largo e nello stretto, chiavi `notification-pref-<tipo>` sulle righe.

## Task 5: Anteprima dei sottotitoli

`lib/features/settings/subtitle_preview.dart` (decisione 5) e posto nella
sezione Audio e sottotitoli (a destra nel largo se la larghezza lo
permette, sotto altrimenti). Test: la grandezza del testo segue la scala.

## Task 6: Tessera dell'account

Decisione 7 in `account_settings_section.dart` (+ eventuale
`account_card.dart`). Test: tocco sull'avatar apre il dialogo, niente
bottone "Cambia immagine", "Autorizza un dispositivo", Esci dopo i contatti
e con lo stile di errore, layout stretto.

## Task 7: TV

`lib/features/settings/tv_settings_body.dart` (+ `tv_choice_panel.dart`),
decisione 8; `SettingsScreen` sulla TV mostra solo `TvSettingsBody`.
Rimuovere dal resto della pagina i rami `tv` diventati inutili. Test con
`FormFactorScope(tv: true)`: Su/Giù, OK sugli interruttori, pannello (OK
cambia, Indietro no, focus torna), anteprima nel pannello della dimensione,
riga aggiornamento, niente decodifica hardware, errore lingue.

## Task 8: Chiusura

Review dell'intero ramo, `flutter gen-l10n && flutter analyze && flutter
test`, riga nel checklist di `docs/RELEASING.md`, build Windows di prova e
APK TV.
