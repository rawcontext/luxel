# Luxel Mac App Store Listing Metadata

This file is the checked-in source of truth for Luxel's Mac App Store product-page metadata. It records the verified public listing as of August 22, 2026 and the complete proposed metadata for the Speech Detection Prompts release. Copy values from this file into an editable App Store Connect draft; do not edit the draft independently.

## Publication state

- Prepared locally on August 22, 2026. Nothing in this change was submitted to or published through App Store Connect.
- No App Store Connect credentials are available in the local environment. The repository's authenticated workflows receive credentials only from GitHub Actions secrets, so private fields and the configured localization set could not be retrieved.
- Apple's public Search API does not expose promotional text, keywords, App Review notes, configured localizations, or draft metadata. Those prior values are therefore recorded as unavailable rather than guessed.
- Before submission, compare every editable App Store Connect field with this file, update the release version/build in the review package, attach the final review video, and record the comparison in GitHub issue #57.

## Apple field rules

These limits were rechecked against Apple's App Store Connect Help on August 22, 2026:

| Field | Limit and rule |
| --- | --- |
| App name | 2–30 characters |
| Subtitle | 30 characters |
| Promotional text | 170 characters |
| Description | 4,000 characters; plain text |
| Keywords | 100 UTF-8 bytes; each keyword longer than two characters; do not repeat the app/company name or use other app/company names |
| What's New | 4,000 characters |
| App Review notes | 4,000 UTF-8 bytes; one shared review field, not storefront-localized |
| Support URL | Full URL; must lead to real contact information |
| Privacy Policy URL | Required for macOS apps |

Authoritative references:

- [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [App Store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)

Run the local validation after every metadata edit:

```sh
bun docs/ux/app-store/validate-listing-metadata.mjs
```

The script validates every declared character count, the keyword byte counts, required locales, HTTPS URLs, and screenshot source paths.

## Verified public baseline

Apple's public Search API was re-fetched for the U.S., Germany, Spain, France, Italy, Japan, Korea, Vietnam, China mainland, Brazil, and Portugal on August 22, 2026.

| Property | Verified value |
| --- | --- |
| Product | Luxel |
| Apple ID | 6800438206 |
| Seller | Raw Context LLC |
| Bundle identifier | `com.rawcontext.luxel` |
| Public version | 1.1.6 |
| Released | August 19, 2026 |
| U.S. price | $9.99 |
| Primary / secondary genre | Photo & Video / Productivity |
| Age rating | 4+ |
| Minimum macOS | 26.0 |
| U.S. subtitle | Screen Recorder & Replay |
| Public description | 2,490 characters; same English value returned in all 11 sampled storefronts |
| Public What's New | Not returned for version 1.1.6 |
| Binary languages | English, French, German, Italian, Japanese, Korean, Portuguese, Simplified Chinese, Spanish, Vietnamese |
| Public product URL | https://apps.apple.com/us/app/luxel/id6800438206 |
| Public Search API | https://itunes.apple.com/lookup?id=6800438206&country=us |

<details>
<summary>Live U.S. description for version 1.1.6 (2,490 characters)</summary>

Record your screen — or save what just happened.

Luxel is a native Mac screen recorder that lives in your menu bar. Capture any display, app window, selected area, or audio-only recording. Add system audio, microphone audio, or your camera when you need them. Then refine, transcribe, and export locally — without watermarks, tracking, or cloud uploads.

CAPTURE WITHOUT BREAKING FOCUS

• Start from the menu bar, global shortcuts, the area picker, Shortcuts, URL actions, or the authenticated command line.
• Record at 1–120 FPS or match your display’s refresh rate.
• Include the cursor, highlight clicks, and capture optional keystroke overlays.
• Add a countdown, pause and resume, or stop automatically after a set duration.
• Select exact regions with resize handles, aspect ratios, size presets, and a precision loupe.
• Keep recording status close in the notch, floating HUD, or menu bar.

SAVE WHAT JUST HAPPENED

Turn on Replay Buffer before a session and Luxel keeps up to five minutes of recent screen activity ready. When something worth saving happens — a bug, a great play, or a fleeting moment — clip it without stopping the buffer.

MAKE EVERY RECORDING CLEARER

Record system audio and microphone audio together. Place a camera overlay anywhere you like, choose its shape and size, remove the background with Cutout, or use Green Screen. Studio Voice can reduce background noise and improve spoken audio during export.

EDIT VIDEO BY EDITING TEXT

Generate a searchable transcript on your Mac, jump to spoken words, separate speakers, and recognize people you have named before. Select words in the transcript and cut them from the recording. Edits are non-destructive, so the original stays safe.

EXPORT FOR ANY HANDOFF

Trim, resize, crop, retime, normalize audio, or adjust its level. Export one format or several at once:

• MP4 (H.264 or HEVC)
• ProRes 422 or ProRes 4444
• WebM (VP9) or MP4 (AV1)
• GIF or APNG
• M4A, ALAC, WAV, CAF, or FLAC

Save reusable presets for fast repeat captures, export directly to a destination, or continue in the editor.

PRIVATE BY DESIGN

Recording, editing, transcription, speaker identification, and export happen on your Mac. Luxel does not upload your content or collect data from the app.

No watermarks. No tracking. No analytics. No ads. No time limits. No export restrictions.

Great for product demos, tutorials, bug reports, QA, async updates, quick GIFs, meeting notes, audio recordings, and automated capture workflows.

</details>

This release replaces that English-only public description with the localized descriptions below.

The current public screenshot order is:

1. `docs/design/app-store-05-menu-bar.png`
2. `docs/design/app-store-01-area-capture.png`
3. `docs/design/app-store-06-transcripts.png`
4. `docs/design/app-store-04-export.png`
5. `docs/design/app-store-03-recording-status.png`
6. `docs/design/app-store-02-editor-trim.png`

Prior promotional text, keywords, App Review notes, private App Privacy answers, and exact App Store Connect localization records were not publicly retrievable. The existing review package for version 1.1.6 is preserved in Git history and summarized in `docs/app-review/information-needed-checklist.md`.

## Locale mapping

| Luxel website/app locale | App Store Connect locale | Storefront language |
| --- | --- | --- |
| `en` | `en-US` | English (U.S.) |
| `de` | `de-DE` | German |
| `es` | `es-ES` | Spanish (Spain) |
| `fr` | `fr-FR` | French |
| `it` | `it` | Italian |
| `ja` | `ja` | Japanese |
| `ko` | `ko` | Korean |
| `vi` | `vi` | Vietnamese |
| `zh-Hans` | `zh-Hans` | Chinese (Simplified) |
| `pt-BR` | `pt-BR` | Portuguese (Brazil) |
| `pt-PT` | `pt-PT` | Portuguese (Portugal) |

## Proposed screenshot order

Use only real Luxel screenshots. Do not add marketing overlays, generated imagery, frames, retouching, text replacement, or resized derivatives. Position 2 is the exact 2064 × 1744 screenshot supplied for this release (SHA-256 `1a8051f2d614d27eb301063db1cf58e9ce3ccac151f81c79eae20dadc167db6c`). The localized captions below are editorial labels for the checked-in plan; App Store Connect has no separate screenshot-caption field, so they are not rendered into the images. If Apple rejects the supplied dimensions, capture the same real settings view again at a currently supported size instead of altering this file.

<!-- APP-STORE-SCREENSHOTS -->
```json
[
  {
    "position": 1,
    "subject": "menu-bar capture",
    "size": "2880x1800",
    "sourcePath": "docs/design/app-store-05-menu-bar.png"
  },
  {
    "position": 2,
    "subject": "Speech Detection Prompts settings",
    "size": "2064x1744",
    "sourcePath": "apps/web/public/screenshots/luxel-settings-speech-detection.png"
  },
  {
    "position": 3,
    "subject": "precise area capture",
    "size": "2880x1800",
    "sourcePath": "docs/design/app-store-01-area-capture.png"
  },
  {
    "position": 4,
    "subject": "local transcripts",
    "size": "2880x1800",
    "sourcePath": "docs/design/app-store-06-transcripts.png"
  },
  {
    "position": 5,
    "subject": "export formats",
    "size": "2880x1800",
    "sourcePath": "docs/design/app-store-04-export.png"
  },
  {
    "position": 6,
    "subject": "recording controls",
    "size": "2880x1800",
    "sourcePath": "docs/design/app-store-03-recording-status.png"
  },
  {
    "position": 7,
    "subject": "non-destructive editor",
    "size": "2880x1800",
    "sourcePath": "docs/design/app-store-02-editor-trim.png"
  }
]
```

## Proposed localized listing

The JSON blocks are deliberately machine-readable so the validator can enforce Apple's limits. New descriptions and captions were authored for each storefront; they are not English fallback values.

### English (U.S.) — `en-US`

<!-- APP-STORE-LOCALE -->
```json
{
  "locale": "en-US",
  "websiteLocale": "en",
  "name": "Luxel",
  "subtitle": "Screen Recorder & Replay",
  "promotionalText": "Optional Speech Detection Prompts listen locally for speech-like audio, save nothing, and record only when you choose Start Recording.",
  "description": "Record your screen — or save what just happened.\n\nLuxel is a native Mac recorder that lives in your menu bar. Capture a display, app window, selected area, or audio-only session. Add system audio, a microphone, and camera. Then edit, transcribe, and export on your Mac — without watermarks, tracking, analytics, ads, or cloud uploads.\n\nSPEECH DETECTION PROMPTS\n\nSpeech Detection Prompts are optional and off by default. When enabled, Luxel analyzes the selected microphone locally while the app is running and available. It looks for sustained speech-like audio — not meetings, calls, participants, or consent — and macOS may show its microphone-in-use indicator.\n\nAudio samples are discarded unless you explicitly choose Start Recording. Listening creates no pre-roll, media file, history item, transcript, sidecar, or cloud upload. A prompt never starts recording automatically. Focus or Do Not Disturb may hide the notification. Detection pauses while Luxel is recording, locked, sleeping, or otherwise unavailable, and it does not work after you quit Luxel.\n\nCAPTURE WITHOUT BREAKING FOCUS\n\nStart from the menu bar, global shortcuts, the area picker, Shortcuts, URL actions, or the authenticated command line. Record a display, window, exact region, or audio-only session at 1–120 FPS. Add a countdown, cursor and click effects, optional keystrokes, microphone audio, system audio, and a camera overlay. Pause, resume, or stop automatically after a chosen duration.\n\nSAVE WHAT JUST HAPPENED\n\nTurn on Replay Buffer before a session to keep up to five minutes of recent screen activity ready. Save a bug, great play, or fleeting moment without stopping the buffer.\n\nEDIT AND TRANSCRIBE LOCALLY\n\nGenerate a searchable transcript on your Mac, jump to spoken words, separate speakers, and cut selected words non-destructively. Trim, resize, crop, retime, normalize audio, or adjust its level. Studio Voice can reduce background noise during export.\n\nEXPORT FOR ANY HANDOFF\n\nExport MP4, ProRes, WebM, AV1, GIF, APNG, M4A, ALAC, WAV, CAF, or FLAC. Save reusable presets, export directly to a destination, or continue in the editor.\n\nPRIVATE BY DESIGN\n\nRecording, listening, editing, transcription, speaker identification, and export happen on your Mac. Luxel does not upload your content or collect data from the app. No account is required.",
  "keywords": "screen recorder,screen capture,audio recorder,replay,transcription,video editor,GIF,WebM",
  "whatsNew": "New: optional Speech Detection Prompts can listen locally for sustained speech-like audio and offer to start an audio-only recording. The feature is off by default, saves nothing while listening, and never records until you explicitly choose Start Recording. This update also includes reliability improvements.",
  "marketingUrl": "https://luxel.media/",
  "supportUrl": "https://luxel.media/support",
  "privacyPolicyUrl": "https://luxel.media/privacy",
  "screenshotCaptions": [
    "Capture from your menu bar",
    "Optional local speech prompts — recording stays your choice",
    "Select the exact area you need",
    "Transcribe and edit on your Mac",
    "Export every format your workflow needs",
    "Keep recording controls close",
    "Refine recordings non-destructively"
  ],
  "counts": { "name": 5, "subtitle": 24, "promotionalText": 134, "description": 2338, "whatsNew": 310, "keywordBytes": 88 }
}
```

### German — `de-DE`

<!-- APP-STORE-LOCALE -->
```json
{
  "locale": "de-DE",
  "websiteLocale": "de",
  "name": "Luxel",
  "subtitle": "Bildschirmaufnahme & Replay",
  "promotionalText": "Optionale Spracherkennungs-Hinweise analysieren Sprache lokal, speichern nichts und nehmen erst nach deiner Wahl „Aufnahme starten“ auf.",
  "description": "Nimm deinen Bildschirm auf — oder sichere, was gerade passiert ist.\n\nLuxel ist ein nativer Mac-Recorder in deiner Menüleiste. Nimm einen Bildschirm, ein App-Fenster, einen ausgewählten Bereich oder nur Audio auf. Füge Systemton, Mikrofon und Kamera hinzu. Bearbeitung, Transkription und Export erfolgen auf deinem Mac — ohne Wasserzeichen, Tracking, Analysen, Werbung oder Cloud-Uploads.\n\nSPRACHERKENNUNGS-HINWEISE\n\nSpracherkennungs-Hinweise sind optional und standardmäßig deaktiviert. Wenn du sie aktivierst, analysiert Luxel das ausgewählte Mikrofon lokal, solange die App läuft und verfügbar ist. Gesucht wird nach anhaltenden sprachähnlichen Geräuschen — nicht nach Meetings, Anrufen, Personen oder Einwilligungen. macOS kann dabei seinen Mikrofonindikator anzeigen.\n\nAudioproben werden verworfen, sofern du nicht ausdrücklich „Aufnahme starten“ wählst. Beim Zuhören entstehen weder Vorlauf noch Mediendatei, Verlaufseintrag, Transkript, Begleitdatei oder Cloud-Upload. Ein Hinweis startet niemals automatisch eine Aufnahme. Fokus oder „Nicht stören“ kann die Mitteilung ausblenden. Die Erkennung pausiert während einer Aufnahme, bei gesperrtem oder schlafendem Mac und wenn Luxel nicht verfügbar ist; nach dem Beenden der App arbeitet sie nicht weiter.\n\nAUFNEHMEN OHNE ABLENKUNG\n\nStarte über die Menüleiste, globale Kurzbefehle, die Bereichsauswahl, Kurzbefehle, URL-Aktionen oder die authentifizierte Kommandozeile. Nimm Bildschirm, Fenster, exakten Bereich oder nur Audio mit 1–120 FPS auf. Ergänze Countdown, Cursor- und Klickeffekte, optionale Tasteneinblendungen, Mikrofon, Systemton und Kamera.\n\nSICHERE, WAS GERADE PASSIERT IST\n\nAktiviere vorab den Replay-Puffer, um bis zu fünf Minuten der letzten Bildschirmaktivität bereitzuhalten und einen Fehler oder flüchtigen Moment nachträglich zu sichern.\n\nLOKAL BEARBEITEN UND TRANSKRIBIEREN\n\nErstelle ein durchsuchbares Transkript auf deinem Mac, springe zu gesprochenen Wörtern, trenne Sprecher und schneide markierte Wörter nicht-destruktiv. Trimme, skaliere, beschneide, ändere das Tempo und optimiere den Ton.\n\nFÜR JEDEN WORKFLOW EXPORTIEREN\n\nExportiere MP4, ProRes, WebM, AV1, GIF, APNG, M4A, ALAC, WAV, CAF oder FLAC. Speichere wiederverwendbare Vorgaben oder exportiere direkt an ein Ziel.\n\nDATENSCHUTZ VON GRUND AUF\n\nAufnahme, Zuhören, Bearbeitung, Transkription, Sprechererkennung und Export finden auf deinem Mac statt. Luxel lädt deine Inhalte nicht hoch und erhebt keine App-Daten. Kein Konto erforderlich.",
  "keywords": "bildschirmaufnahme,audioaufnahme,replay,transkription,videoeditor,GIF,WebM",
  "whatsNew": "Neu: Optionale Spracherkennungs-Hinweise können lokal auf anhaltende sprachähnliche Geräusche achten und eine reine Audioaufnahme anbieten. Die Funktion ist standardmäßig aus, speichert beim Zuhören nichts und nimmt erst auf, wenn du ausdrücklich „Aufnahme starten“ wählst. Außerdem wurden Zuverlässigkeit und Leistung verbessert.",
  "marketingUrl": "https://luxel.media/de/",
  "supportUrl": "https://luxel.media/de/support",
  "privacyPolicyUrl": "https://luxel.media/de/privacy",
  "screenshotCaptions": [
    "Direkt aus der Menüleiste aufnehmen",
    "Optionale lokale Sprachhinweise — du entscheidest über die Aufnahme",
    "Wähle exakt den gewünschten Bereich",
    "Auf dem Mac transkribieren und bearbeiten",
    "In alle Formate deines Workflows exportieren",
    "Aufnahmesteuerung immer in Reichweite",
    "Aufnahmen nicht-destruktiv verfeinern"
  ],
  "counts": { "name": 5, "subtitle": 27, "promotionalText": 136, "description": 2476, "whatsNew": 330, "keywordBytes": 74 }
}
```

### Spanish (Spain) — `es-ES`

<!-- APP-STORE-LOCALE -->
```json
{
  "locale": "es-ES",
  "websiteLocale": "es",
  "name": "Luxel",
  "subtitle": "Grabación de pantalla y Replay",
  "promotionalText": "Los avisos opcionales de voz analizan el audio localmente, no guardan nada y solo graban cuando eliges Iniciar grabación.",
  "description": "Graba tu pantalla o guarda lo que acaba de ocurrir.\n\nLuxel es un grabador nativo para Mac que vive en la barra de menús. Captura una pantalla, una ventana, un área seleccionada o solo audio. Añade el audio del sistema, un micrófono y la cámara. Después, edita, transcribe y exporta en tu Mac, sin marcas de agua, rastreo, analítica, anuncios ni subidas a la nube.\n\nAVISOS DE DETECCIÓN DE VOZ\n\nLos avisos de detección de voz son opcionales y están desactivados de forma predeterminada. Al activarlos, Luxel analiza localmente el micrófono seleccionado mientras la app está abierta y disponible. Busca audio continuado parecido a la voz; no detecta reuniones, llamadas, participantes ni consentimiento. macOS puede mostrar el indicador de uso del micrófono.\n\nLas muestras de audio se descartan salvo que elijas expresamente Iniciar grabación. La escucha no crea pregrabación, archivos multimedia, elementos del historial, transcripciones, archivos auxiliares ni subidas a la nube. Un aviso nunca inicia una grabación automáticamente. Concentración o No molestar pueden ocultar la notificación. La detección se pausa durante una grabación y cuando el Mac está bloqueado, en reposo o no disponible; deja de funcionar al cerrar Luxel.\n\nCAPTURA SIN PERDER LA CONCENTRACIÓN\n\nEmpieza desde la barra de menús, atajos globales, el selector de área, Atajos, acciones URL o la línea de comandos autenticada. Graba una pantalla, ventana, región exacta o solo audio a 1–120 FPS. Añade cuenta atrás, efectos de cursor y clic, teclas opcionales, micrófono, audio del sistema y cámara.\n\nGUARDA LO QUE ACABA DE OCURRIR\n\nActiva Replay Buffer antes de una sesión para mantener disponibles hasta cinco minutos de actividad reciente y guardar después un error o un momento fugaz.\n\nEDITA Y TRANSCRIBE LOCALMENTE\n\nCrea una transcripción con búsqueda en tu Mac, salta a las palabras pronunciadas, separa hablantes y corta palabras sin destruir el original. Recorta, redimensiona, encuadra, cambia la velocidad y ajusta el audio.\n\nEXPORTA PARA CUALQUIER ENTREGA\n\nExporta MP4, ProRes, WebM, AV1, GIF, APNG, M4A, ALAC, WAV, CAF o FLAC. Guarda ajustes reutilizables o exporta directamente a un destino.\n\nPRIVACIDAD DESDE EL DISEÑO\n\nLa grabación, escucha, edición, transcripción, identificación de hablantes y exportación se realizan en tu Mac. Luxel no sube tu contenido ni recopila datos de la app. No requiere cuenta.",
  "keywords": "grabar pantalla,captura,audio,replay,transcripción,editor de vídeo,GIF,WebM",
  "whatsNew": "Novedad: los avisos opcionales de detección de voz pueden buscar localmente audio continuado parecido a la voz y ofrecer una grabación de solo audio. La función está desactivada de forma predeterminada, no guarda nada mientras escucha y solo graba cuando eliges expresamente Iniciar grabación. También incluye mejoras de fiabilidad.",
  "marketingUrl": "https://luxel.media/es/",
  "supportUrl": "https://luxel.media/es/support",
  "privacyPolicyUrl": "https://luxel.media/es/privacy",
  "screenshotCaptions": [
    "Captura desde la barra de menús",
    "Avisos de voz locales y opcionales: tú decides si grabar",
    "Selecciona exactamente el área que necesitas",
    "Transcribe y edita en tu Mac",
    "Exporta en todos los formatos de tu flujo",
    "Mantén cerca los controles de grabación",
    "Perfecciona sin alterar el original"
  ],
  "counts": { "name": 5, "subtitle": 30, "promotionalText": 121, "description": 2390, "whatsNew": 332, "keywordBytes": 77 }
}
```

### French — `fr-FR`

<!-- APP-STORE-LOCALE -->
```json
{
  "locale": "fr-FR",
  "websiteLocale": "fr",
  "name": "Luxel",
  "subtitle": "Capture d’écran et Replay",
  "promotionalText": "Les alertes vocales facultatives analysent le son localement, ne sauvegardent rien et n’enregistrent qu’après votre choix explicite.",
  "description": "Enregistrez votre écran — ou sauvegardez ce qui vient de se passer.\n\nLuxel est un enregistreur Mac natif installé dans la barre des menus. Capturez un écran, une fenêtre, une zone précise ou uniquement l’audio. Ajoutez le son du système, un micro et la caméra. Modifiez, transcrivez et exportez ensuite sur votre Mac, sans filigrane, suivi, analyse, publicité ni envoi dans le cloud.\n\nALERTES DE DÉTECTION VOCALE\n\nLes alertes de détection vocale sont facultatives et désactivées par défaut. Une fois activées, Luxel analyse localement le micro sélectionné tant que l’app fonctionne et reste disponible. Il recherche un son continu ressemblant à de la parole, pas des réunions, appels, participants ou consentements. macOS peut afficher son indicateur d’utilisation du micro.\n\nLes échantillons audio sont supprimés sauf si vous choisissez explicitement Démarrer l’enregistrement. L’écoute ne crée ni pré-enregistrement, fichier multimédia, élément d’historique, transcription, fichier annexe ou envoi cloud. Une alerte ne démarre jamais automatiquement l’enregistrement. Concentration ou Ne pas déranger peut masquer la notification. La détection se met en pause pendant un enregistrement, lorsque le Mac est verrouillé, en veille ou indisponible, et s’arrête quand vous quittez Luxel.\n\nCAPTUREZ SANS VOUS DISTRAIRE\n\nDémarrez depuis la barre des menus, les raccourcis globaux, le sélecteur de zone, Raccourcis, des actions URL ou la ligne de commande authentifiée. Enregistrez un écran, une fenêtre, une zone exacte ou uniquement l’audio à 1–120 i/s. Ajoutez compte à rebours, effets de pointeur et de clic, touches facultatives, micro, son système et caméra.\n\nSAUVEGARDEZ CE QUI VIENT D’ARRIVER\n\nActivez Replay Buffer avant une session pour garder jusqu’à cinq minutes d’activité récente et sauvegarder après coup un bug ou un moment fugace.\n\nMODIFIEZ ET TRANSCRIVEZ LOCALEMENT\n\nCréez une transcription consultable sur votre Mac, accédez aux mots prononcés, séparez les intervenants et coupez des mots sans modifier l’original. Rognez, redimensionnez, recadrez, changez la vitesse et ajustez le son.\n\nEXPORTEZ POUR CHAQUE BESOIN\n\nExportez en MP4, ProRes, WebM, AV1, GIF, APNG, M4A, ALAC, WAV, CAF ou FLAC. Enregistrez des préréglages réutilisables ou exportez directement vers une destination.\n\nCONFIDENTIEL PAR CONCEPTION\n\nEnregistrement, écoute, montage, transcription, identification des intervenants et exportation ont lieu sur votre Mac. Luxel ne téléverse pas votre contenu et ne collecte aucune donnée de l’app. Aucun compte requis.",
  "keywords": "capture écran,enregistreur,audio,replay,transcription,montage vidéo,GIF,WebM",
  "whatsNew": "Nouveau : les alertes facultatives de détection vocale peuvent rechercher localement un son continu ressemblant à de la parole et proposer un enregistrement audio. La fonction est désactivée par défaut, ne sauvegarde rien pendant l’écoute et n’enregistre qu’après votre choix explicite de démarrer. Cette version améliore aussi la fiabilité.",
  "marketingUrl": "https://luxel.media/fr/",
  "supportUrl": "https://luxel.media/fr/support",
  "privacyPolicyUrl": "https://luxel.media/fr/privacy",
  "screenshotCaptions": [
    "Capturez depuis la barre des menus",
    "Alertes vocales locales et facultatives : vous décidez d’enregistrer",
    "Sélectionnez exactement la zone voulue",
    "Transcrivez et montez sur votre Mac",
    "Exportez dans tous les formats utiles",
    "Gardez les commandes d’enregistrement à portée de main",
    "Peaufinez sans altérer l’original"
  ],
  "counts": { "name": 5, "subtitle": 25, "promotionalText": 132, "description": 2539, "whatsNew": 341, "keywordBytes": 78 }
}
```

### Italian — `it`

<!-- APP-STORE-LOCALE -->
```json
{
  "locale": "it",
  "websiteLocale": "it",
  "name": "Luxel",
  "subtitle": "Registrazione schermo e Replay",
  "promotionalText": "Gli avvisi vocali opzionali analizzano l’audio in locale, non salvano nulla e registrano solo quando scegli Avvia registrazione.",
  "description": "Registra lo schermo o salva ciò che è appena successo.\n\nLuxel è un registratore Mac nativo che vive nella barra dei menu. Acquisisci un display, una finestra, un’area selezionata o solo l’audio. Aggiungi audio di sistema, microfono e fotocamera. Poi modifica, trascrivi ed esporta sul Mac, senza filigrane, tracciamento, analisi, pubblicità o caricamenti nel cloud.\n\nAVVISI DI RILEVAMENTO VOCALE\n\nGli avvisi di rilevamento vocale sono opzionali e disattivati per impostazione predefinita. Se li attivi, Luxel analizza in locale il microfono selezionato mentre l’app è in esecuzione e disponibile. Cerca un audio continuo simile alla voce, non riunioni, chiamate, partecipanti o consenso. macOS può mostrare l’indicatore di utilizzo del microfono.\n\nI campioni audio vengono eliminati a meno che tu non scelga esplicitamente Avvia registrazione. L’ascolto non crea pre-registrazioni, file multimediali, elementi della cronologia, trascrizioni, file accessori o caricamenti nel cloud. Un avviso non avvia mai la registrazione automaticamente. Full immersion o Non disturbare possono nascondere la notifica. Il rilevamento si mette in pausa durante una registrazione e quando il Mac è bloccato, in stop o non disponibile; smette di funzionare quando chiudi Luxel.\n\nREGISTRA SENZA PERDERE LA CONCENTRAZIONE\n\nAvvia dalla barra dei menu, dalle scorciatoie globali, dal selettore di area, da Comandi Rapidi, da azioni URL o dalla riga di comando autenticata. Registra un display, una finestra, un’area precisa o solo audio a 1–120 FPS. Aggiungi conto alla rovescia, effetti del puntatore e dei clic, tasti opzionali, microfono, audio di sistema e fotocamera.\n\nSALVA CIÒ CHE È APPENA SUCCESSO\n\nAttiva Replay Buffer prima di una sessione per conservare fino a cinque minuti di attività recente e salvare in seguito un bug o un momento fugace.\n\nMODIFICA E TRASCRIVI IN LOCALE\n\nGenera una trascrizione ricercabile sul Mac, passa alle parole pronunciate, separa le voci e taglia le parole senza alterare l’originale. Rifila, ridimensiona, ritaglia, cambia velocità e regola l’audio.\n\nESPORTA PER OGNI CONSEGNA\n\nEsporta in MP4, ProRes, WebM, AV1, GIF, APNG, M4A, ALAC, WAV, CAF o FLAC. Salva preset riutilizzabili o esporta direttamente verso una destinazione.\n\nPRIVACY FIN DALLA PROGETTAZIONE\n\nRegistrazione, ascolto, modifica, trascrizione, identificazione delle voci ed esportazione avvengono sul Mac. Luxel non carica i tuoi contenuti e non raccoglie dati dall’app. Non serve un account.",
  "keywords": "registra schermo,cattura,audio,replay,trascrizione,editor video,GIF,WebM",
  "whatsNew": "Novità: gli avvisi opzionali di rilevamento vocale possono cercare in locale un audio continuo simile alla voce e proporre una registrazione solo audio. La funzione è disattivata per impostazione predefinita, non salva nulla durante l’ascolto e registra solo quando scegli esplicitamente Avvia registrazione. Sono incluse anche migliorie all’affidabilità.",
  "marketingUrl": "https://luxel.media/it/",
  "supportUrl": "https://luxel.media/it/support",
  "privacyPolicyUrl": "https://luxel.media/it/privacy",
  "screenshotCaptions": [
    "Registra dalla barra dei menu",
    "Avvisi vocali locali e opzionali: registri solo se lo decidi",
    "Seleziona esattamente l’area necessaria",
    "Trascrivi e modifica sul tuo Mac",
    "Esporta in tutti i formati che ti servono",
    "Tieni i controlli di registrazione a portata di mano",
    "Perfeziona senza alterare l’originale"
  ],
  "counts": { "name": 5, "subtitle": 30, "promotionalText": 128, "description": 2477, "whatsNew": 355, "keywordBytes": 72 }
}
```

### Japanese — `ja`

<!-- APP-STORE-LOCALE -->
```json
{
  "locale": "ja",
  "websiteLocale": "ja",
  "name": "Luxel",
  "subtitle": "画面録画とリプレイ",
  "promotionalText": "任意の音声検出通知はMac内だけで音声らしい音を解析。何も保存せず、「録音を開始」を選んだときだけ録音します。",
  "description": "画面を録画。あるいは、たった今起きたことを保存。\n\nLuxelはメニューバーに常駐するMacネイティブのレコーダーです。ディスプレイ、アプリのウインドウ、選択範囲、音声のみを収録できます。システム音声、マイク、カメラも追加可能。ウォーターマーク、トラッキング、解析、広告、クラウドへのアップロードなしで、Mac上で編集、文字起こし、書き出しまで完結します。\n\n音声検出通知\n\n音声検出通知は任意の機能で、初期状態ではオフです。有効にすると、Luxelが起動して利用可能な間、選択したマイクの音をMac内だけで解析し、継続する音声らしい音を探します。会議、通話、参加者、同意の有無を判定する機能ではありません。macOSのマイク使用中インジケータが表示される場合があります。\n\n「録音を開始」を明示的に選ばない限り、音声サンプルは破棄されます。待機中にプリロール、メディアファイル、履歴、文字起こし、サイドカーファイル、クラウドへのアップロードは作成されません。通知から自動で録音が始まることもありません。集中モードやおやすみモードでは通知バナーが表示されない場合があります。録画中、Macのロック中やスリープ中、Luxelを利用できないときは検出を一時停止し、Luxelを終了すると動作しません。\n\n集中を妨げないキャプチャ\n\nメニューバー、グローバルショートカット、範囲選択、ショートカット、URLアクション、認証済みコマンドラインから開始。ディスプレイ、ウインドウ、正確な範囲、音声のみを1〜120 FPSで収録できます。カウントダウン、カーソルやクリックの効果、任意のキー表示、マイク、システム音声、カメラを追加できます。\n\n直前の出来事を保存\n\nセッション前にReplay Bufferを有効にすると、直近最大5分の画面操作を保持し、バグや一瞬の出来事をあとから保存できます。\n\nMac内で編集と文字起こし\n\nMac上で検索できる文字起こしを作成し、発話位置への移動、話者の分離、選択した単語の非破壊カットができます。トリミング、サイズ変更、クロップ、速度変更、音量調整にも対応。\n\n用途に合わせて書き出し\n\nMP4、ProRes、WebM、AV1、GIF、APNG、M4A、ALAC、WAV、CAF、FLACに対応。プリセットの保存や指定先への直接書き出しもできます。\n\nプライバシーを第一に\n\n録画、待機、編集、文字起こし、話者識別、書き出しはMac上で行われます。Luxelがコンテンツをアップロードしたり、アプリからデータを収集したりすることはありません。アカウントも不要です。",
  "keywords": "画面録画,画面収録,音声録音,リプレイ,文字起こし,動画編集,GIF,WebM",
  "whatsNew": "新機能：任意の音声検出通知が、Mac内だけで継続する音声らしい音を検出し、音声のみの録音を提案できるようになりました。初期状態ではオフで、待機中は何も保存しません。「録音を開始」を明示的に選ぶまで録音は始まりません。信頼性も向上しました。",
  "marketingUrl": "https://luxel.media/ja/",
  "supportUrl": "https://luxel.media/ja/support",
  "privacyPolicyUrl": "https://luxel.media/ja/privacy",
  "screenshotCaptions": [
    "メニューバーからすぐにキャプチャ",
    "任意のローカル音声通知。録音するかはあなたが選択",
    "必要な範囲を正確に選択",
    "Mac上で文字起こしと編集",
    "作業に必要な形式へ書き出し",
    "録画コントロールをすぐそばに",
    "元の素材を保ったまま仕上げる"
  ],
  "counts": { "name": 5, "subtitle": 9, "promotionalText": 55, "description": 1097, "whatsNew": 119, "keywordBytes": 89 }
}
```

### Korean — `ko`

<!-- APP-STORE-LOCALE -->
```json
{
  "locale": "ko",
  "websiteLocale": "ko",
  "name": "Luxel",
  "subtitle": "화면 녹화 및 리플레이",
  "promotionalText": "선택형 음성 감지 알림은 Mac에서만 음성 같은 소리를 분석하고 아무것도 저장하지 않으며 사용자가 선택해야 녹음합니다.",
  "description": "화면을 녹화하거나 방금 일어난 일을 저장하세요.\n\nLuxel은 메뉴 막대에 상주하는 Mac 네이티브 레코더입니다. 디스플레이, 앱 윈도우, 선택 영역 또는 오디오만 캡처할 수 있습니다. 시스템 오디오, 마이크 및 카메라를 추가하고 Mac에서 편집, 전사 및 내보내기까지 완료하세요. 워터마크, 추적, 분석, 광고 및 클라우드 업로드가 없습니다.\n\n음성 감지 알림\n\n음성 감지 알림은 선택 사항이며 기본적으로 꺼져 있습니다. 기능을 켜면 Luxel이 실행 중이고 사용 가능한 동안 선택한 마이크를 Mac에서만 분석하여 지속되는 음성 같은 소리를 찾습니다. 회의, 통화, 참가자 또는 동의 여부를 판단하지 않습니다. macOS가 마이크 사용 표시기를 보일 수 있습니다.\n\n사용자가 녹음 시작을 명시적으로 선택하지 않으면 오디오 샘플은 폐기됩니다. 대기 중에는 프리롤, 미디어 파일, 기록 항목, 전사, 사이드카 파일 또는 클라우드 업로드가 생성되지 않습니다. 알림이 자동으로 녹음을 시작하지도 않습니다. 집중 모드 또는 방해금지 모드에서는 알림 배너가 보이지 않을 수 있습니다. Luxel이 녹화 중이거나 Mac이 잠김, 잠자기 또는 사용 불가 상태이면 감지가 일시 정지되며 Luxel을 종료하면 작동하지 않습니다.\n\n집중을 유지하는 캡처\n\n메뉴 막대, 전역 단축키, 영역 선택기, 단축어, URL 동작 또는 인증된 명령줄에서 시작하세요. 디스플레이, 윈도우, 정확한 영역 또는 오디오만 1~120 FPS로 녹화할 수 있습니다. 카운트다운, 포인터 및 클릭 효과, 선택형 키 표시, 마이크, 시스템 오디오 및 카메라를 추가할 수 있습니다.\n\n방금 일어난 일 저장\n\n세션 전에 Replay Buffer를 켜면 최근 화면 활동을 최대 5분까지 준비해 두고 버그나 순간적인 장면을 나중에 저장할 수 있습니다.\n\nMac에서 편집 및 전사\n\n검색 가능한 전사를 만들고, 말한 단어로 이동하고, 화자를 분리하며, 선택한 단어를 원본 손상 없이 잘라낼 수 있습니다. 다듬기, 크기 조절, 자르기, 속도 변경 및 오디오 조절도 지원합니다.\n\n필요한 형식으로 내보내기\n\nMP4, ProRes, WebM, AV1, GIF, APNG, M4A, ALAC, WAV, CAF 또는 FLAC으로 내보내세요. 재사용 가능한 프리셋을 저장하거나 지정한 위치로 바로 내보낼 수 있습니다.\n\n개인정보 보호 중심 설계\n\n녹화, 대기, 편집, 전사, 화자 식별 및 내보내기는 Mac에서 처리됩니다. Luxel은 사용자의 콘텐츠를 업로드하거나 앱 데이터를 수집하지 않습니다. 계정도 필요하지 않습니다.",
  "keywords": "화면녹화,화면캡처,오디오녹음,리플레이,음성전사,동영상편집,GIF,WebM",
  "whatsNew": "새 기능: 선택형 음성 감지 알림이 Mac에서만 지속되는 음성 같은 소리를 찾고 오디오 전용 녹음을 제안할 수 있습니다. 기본적으로 꺼져 있으며 대기 중에는 아무것도 저장하지 않습니다. 사용자가 녹음 시작을 명시적으로 선택하기 전에는 녹음하지 않습니다. 안정성도 개선했습니다.",
  "marketingUrl": "https://luxel.media/ko/",
  "supportUrl": "https://luxel.media/ko/support",
  "privacyPolicyUrl": "https://luxel.media/ko/privacy",
  "screenshotCaptions": [
    "메뉴 막대에서 바로 캡처",
    "선택형 로컬 음성 알림 — 녹음 여부는 사용자가 결정",
    "필요한 영역을 정확하게 선택",
    "Mac에서 전사하고 편집",
    "작업에 필요한 모든 형식으로 내보내기",
    "녹화 제어기를 가까이에",
    "원본을 보존하며 세밀하게 편집"
  ],
  "counts": { "name": 5, "subtitle": 12, "promotionalText": 66, "description": 1265, "whatsNew": 154, "keywordBytes": 92 }
}
```

### Vietnamese — `vi`

<!-- APP-STORE-LOCALE -->
```json
{
  "locale": "vi",
  "websiteLocale": "vi",
  "name": "Luxel",
  "subtitle": "Ghi màn hình và Replay",
  "promotionalText": "Thông báo giọng nói tùy chọn phân tích ngay trên Mac, không lưu gì và chỉ ghi âm khi bạn chọn Bắt đầu ghi.",
  "description": "Ghi màn hình hoặc lưu lại điều vừa xảy ra.\n\nLuxel là trình ghi gốc cho Mac nằm trên thanh menu. Ghi màn hình, cửa sổ ứng dụng, vùng đã chọn hoặc chỉ âm thanh. Thêm âm thanh hệ thống, micrô và camera. Sau đó chỉnh sửa, chép lời và xuất ngay trên Mac mà không có hình mờ, theo dõi, phân tích, quảng cáo hay tải lên đám mây.\n\nTHÔNG BÁO PHÁT HIỆN GIỌNG NÓI\n\nThông báo Phát hiện Giọng nói là tính năng tùy chọn và mặc định tắt. Khi bật, Luxel phân tích micrô đã chọn ngay trên Mac trong lúc ứng dụng đang chạy và sẵn sàng. Tính năng tìm âm thanh liên tục giống giọng nói, không xác định cuộc họp, cuộc gọi, người tham gia hay sự đồng ý. macOS có thể hiển thị chỉ báo micrô đang được sử dụng.\n\nCác mẫu âm thanh bị loại bỏ trừ khi bạn chủ động chọn Bắt đầu ghi. Trong lúc lắng nghe, Luxel không tạo đoạn ghi trước, tệp phương tiện, mục lịch sử, bản chép lời, tệp phụ hay nội dung tải lên đám mây. Thông báo không bao giờ tự động bắt đầu ghi. Tập trung hoặc Không làm phiền có thể ẩn biểu ngữ. Phát hiện tạm dừng khi Luxel đang ghi, Mac bị khóa, ngủ hoặc không sẵn sàng và không hoạt động sau khi bạn thoát Luxel.\n\nGHI MÀ KHÔNG MẤT TẬP TRUNG\n\nBắt đầu từ thanh menu, phím tắt toàn cục, bộ chọn vùng, Phím tắt, tác vụ URL hoặc dòng lệnh đã xác thực. Ghi màn hình, cửa sổ, vùng chính xác hoặc chỉ âm thanh ở 1–120 FPS. Thêm đếm ngược, hiệu ứng con trỏ và cú nhấp, hiển thị phím tùy chọn, micrô, âm thanh hệ thống và camera.\n\nLƯU ĐIỀU VỪA XẢY RA\n\nBật Replay Buffer trước phiên để giữ sẵn tối đa năm phút hoạt động màn hình gần đây và lưu lại lỗi hoặc khoảnh khắc thoáng qua sau đó.\n\nCHỈNH SỬA VÀ CHÉP LỜI CỤC BỘ\n\nTạo bản chép lời có thể tìm kiếm trên Mac, chuyển đến từ đã nói, tách người nói và cắt từ đã chọn mà không phá hủy bản gốc. Cắt, đổi kích thước, xén, đổi tốc độ và chỉnh âm thanh.\n\nXUẤT CHO MỌI QUY TRÌNH\n\nXuất MP4, ProRes, WebM, AV1, GIF, APNG, M4A, ALAC, WAV, CAF hoặc FLAC. Lưu cài đặt sẵn có thể dùng lại hoặc xuất thẳng đến đích.\n\nRIÊNG TƯ NGAY TỪ THIẾT KẾ\n\nGhi, lắng nghe, chỉnh sửa, chép lời, nhận diện người nói và xuất đều diễn ra trên Mac. Luxel không tải nội dung của bạn lên và không thu thập dữ liệu từ ứng dụng. Không cần tài khoản.",
  "keywords": "ghi màn hình,thu âm,replay,chép lời,chỉnh sửa video,GIF,WebM",
  "whatsNew": "Mới: Thông báo Phát hiện Giọng nói tùy chọn có thể tìm âm thanh liên tục giống giọng nói ngay trên Mac và đề nghị bắt đầu bản ghi chỉ âm thanh. Tính năng mặc định tắt, không lưu gì khi lắng nghe và không ghi cho đến khi bạn chủ động chọn Bắt đầu ghi. Bản cập nhật cũng cải thiện độ tin cậy.",
  "marketingUrl": "https://luxel.media/vi/",
  "supportUrl": "https://luxel.media/vi/support",
  "privacyPolicyUrl": "https://luxel.media/vi/privacy",
  "screenshotCaptions": [
    "Ghi ngay từ thanh menu",
    "Thông báo giọng nói cục bộ, tùy chọn — bạn quyết định có ghi hay không",
    "Chọn chính xác vùng bạn cần",
    "Chép lời và chỉnh sửa trên Mac",
    "Xuất mọi định dạng cho quy trình của bạn",
    "Luôn có điều khiển ghi trong tầm tay",
    "Tinh chỉnh mà không làm thay đổi bản gốc"
  ],
  "counts": { "name": 5, "subtitle": 22, "promotionalText": 106, "description": 2146, "whatsNew": 290, "keywordBytes": 70 }
}
```

### Chinese (Simplified) — `zh-Hans`

<!-- APP-STORE-LOCALE -->
```json
{
  "locale": "zh-Hans",
  "websiteLocale": "zh-Hans",
  "name": "Luxel",
  "subtitle": "屏幕录制与回放",
  "promotionalText": "可选的语音检测提醒只在 Mac 本地分析类似语音的声音，不保存任何内容，只有你选择“开始录音”后才会录制。",
  "description": "录制屏幕，或保存刚刚发生的内容。\n\nLuxel 是一款常驻菜单栏的原生 Mac 录制工具。你可以录制显示器、App 窗口、选定区域或纯音频，并加入系统音频、麦克风和摄像头。随后直接在 Mac 上编辑、转写和导出，无水印、无跟踪、无分析、无广告，也不会上传到云端。\n\n语音检测提醒\n\n语音检测提醒是一项可选功能，默认关闭。启用后，Luxel 会在 App 正在运行且可用时，只在本地分析所选麦克风，寻找持续的类似语音的声音。它不会判断会议、通话、参与者或是否获得同意。macOS 可能会显示麦克风正在使用的指示器。\n\n除非你明确选择“开始录音”，否则音频样本会被丢弃。监听时不会创建预录内容、媒体文件、历史记录、转写、附属文件或云端上传。提醒绝不会自动开始录制。专注模式或勿扰模式可能会隐藏通知横幅。Luxel 正在录制、Mac 被锁定、进入睡眠或不可用时，检测会暂停；退出 Luxel 后不会继续运行。\n\n专注录制\n\n可从菜单栏、全局快捷键、区域选择器、快捷指令、URL 操作或已认证的命令行启动。以 1–120 FPS 录制显示器、窗口、精确区域或纯音频。可加入倒计时、指针和点击效果、可选按键显示、麦克风、系统音频和摄像头。\n\n保存刚刚发生的内容\n\n在操作前开启 Replay Buffer，可保留最近最多五分钟的屏幕活动，事后保存错误或转瞬即逝的画面。\n\n在本地编辑和转写\n\n在 Mac 上生成可搜索的转写，跳转到说出的词语、区分说话者，并以非破坏方式剪掉所选词语。还可修剪、调整大小、裁切、变速和调节音频。\n\n适配各种交付方式\n\n导出 MP4、ProRes、WebM、AV1、GIF、APNG、M4A、ALAC、WAV、CAF 或 FLAC。保存可重复使用的预设，或直接导出到指定位置。\n\n隐私融入设计\n\n录制、监听、编辑、转写、说话者识别和导出都在 Mac 上完成。Luxel 不会上传你的内容，也不会从 App 收集数据。无需账户。",
  "keywords": "屏幕录制,屏幕捕捉,音频录制,即时回放,语音转写,视频编辑,GIF,WebM",
  "whatsNew": "新增：可选的语音检测提醒可以只在 Mac 本地寻找持续的类似语音的声音，并建议开始纯音频录制。该功能默认关闭，监听时不保存任何内容；只有你明确选择“开始录音”后才会录制。本次更新还提升了可靠性。",
  "marketingUrl": "https://luxel.media/zh-Hans/",
  "supportUrl": "https://luxel.media/zh-Hans/support",
  "privacyPolicyUrl": "https://luxel.media/zh-Hans/privacy",
  "screenshotCaptions": [
    "从菜单栏立即录制",
    "可选的本地语音提醒——是否录制由你决定",
    "精确选择所需区域",
    "直接在 Mac 上转写和编辑",
    "导出工作流程需要的各种格式",
    "录制控制始终触手可及",
    "以非破坏方式精细编辑"
  ],
  "counts": { "name": 5, "subtitle": 7, "promotionalText": 53, "description": 822, "whatsNew": 97, "keywordBytes": 86 }
}
```

### Portuguese (Brazil) — `pt-BR`

<!-- APP-STORE-LOCALE -->
```json
{
  "locale": "pt-BR",
  "websiteLocale": "pt-BR",
  "name": "Luxel",
  "subtitle": "Gravador de Tela e Replay",
  "promotionalText": "Os alertas de voz opcionais analisam o áudio localmente, não salvam nada e só gravam quando você escolhe Iniciar Gravação.",
  "description": "Grave a tela ou salve o que acabou de acontecer.\n\nLuxel é um gravador nativo para Mac que fica na barra de menus. Capture uma tela, janela de app, área selecionada ou apenas áudio. Adicione o áudio do sistema, microfone e câmera. Depois edite, transcreva e exporte no Mac, sem marca-d’água, rastreamento, análises, anúncios ou uploads para a nuvem.\n\nALERTAS DE DETECÇÃO DE VOZ\n\nOs Alertas de Detecção de Voz são opcionais e vêm desativados. Quando ativados, o Luxel analisa localmente o microfone selecionado enquanto o app está aberto e disponível. Ele procura áudio contínuo parecido com fala, não reuniões, chamadas, participantes ou consentimento. O macOS pode mostrar o indicador de microfone em uso.\n\nAs amostras de áudio são descartadas, a menos que você escolha explicitamente Iniciar Gravação. A escuta não cria pré-gravação, arquivo de mídia, item no histórico, transcrição, arquivo auxiliar nem upload para a nuvem. Um alerta nunca inicia a gravação automaticamente. Foco ou Não Perturbe podem ocultar a notificação. A detecção pausa durante uma gravação e quando o Mac está bloqueado, em repouso ou indisponível; ela não funciona depois que você fecha o Luxel.\n\nCAPTURE SEM PERDER O FOCO\n\nComece pela barra de menus, atalhos globais, seletor de área, Atalhos, ações de URL ou linha de comando autenticada. Grave uma tela, janela, região exata ou apenas áudio em 1–120 FPS. Adicione contagem regressiva, efeitos de cursor e clique, teclas opcionais, microfone, áudio do sistema e câmera.\n\nSALVE O QUE ACABOU DE ACONTECER\n\nAtive o Replay Buffer antes de uma sessão para manter até cinco minutos de atividade recente e salvar depois um bug ou momento passageiro.\n\nEDITE E TRANSCREVA LOCALMENTE\n\nCrie uma transcrição pesquisável no Mac, pule para as palavras faladas, separe vozes e corte palavras sem alterar o original. Apare, redimensione, recorte, mude a velocidade e ajuste o áudio.\n\nEXPORTE PARA QUALQUER ENTREGA\n\nExporte MP4, ProRes, WebM, AV1, GIF, APNG, M4A, ALAC, WAV, CAF ou FLAC. Salve predefinições reutilizáveis ou exporte diretamente para um destino.\n\nPRIVACIDADE DESDE O PROJETO\n\nGravação, escuta, edição, transcrição, identificação de vozes e exportação acontecem no Mac. O Luxel não envia seu conteúdo nem coleta dados do app. Nenhuma conta é necessária.",
  "keywords": "gravar tela,captura,áudio,replay,transcrição,editor de vídeo,GIF,WebM",
  "whatsNew": "Novidade: os Alertas de Detecção de Voz opcionais podem procurar localmente áudio contínuo parecido com fala e oferecer uma gravação somente de áudio. O recurso vem desativado, não salva nada durante a escuta e só grava quando você escolhe explicitamente Iniciar Gravação. Esta atualização também melhora a confiabilidade.",
  "marketingUrl": "https://luxel.media/pt-BR/",
  "supportUrl": "https://luxel.media/pt-BR/support",
  "privacyPolicyUrl": "https://luxel.media/pt-BR/privacy",
  "screenshotCaptions": [
    "Capture direto da barra de menus",
    "Alertas de voz locais e opcionais: você decide se quer gravar",
    "Selecione exatamente a área necessária",
    "Transcreva e edite no Mac",
    "Exporte em todos os formatos do seu fluxo",
    "Mantenha os controles de gravação por perto",
    "Aprimore sem alterar o original"
  ],
  "counts": { "name": 5, "subtitle": 25, "promotionalText": 122, "description": 2280, "whatsNew": 322, "keywordBytes": 73 }
}
```

### Portuguese (Portugal) — `pt-PT`

<!-- APP-STORE-LOCALE -->
```json
{
  "locale": "pt-PT",
  "websiteLocale": "pt-PT",
  "name": "Luxel",
  "subtitle": "Gravação de ecrã e Replay",
  "promotionalText": "Os alertas de voz opcionais analisam localmente, não guardam nada e só gravam quando escolhe Iniciar gravação.",
  "description": "Grave o ecrã ou guarde o que acabou de acontecer.\n\nO Luxel é um gravador nativo para Mac que fica na barra de menus. Capture um ecrã, uma janela de app, uma área selecionada ou apenas áudio. Adicione áudio do sistema, microfone e câmara. Depois, edite, transcreva e exporte no Mac, sem marcas de água, seguimento, análises, publicidade ou envios para a nuvem.\n\nALERTAS DE DETEÇÃO DE VOZ\n\nOs Alertas de Deteção de Voz são opcionais e estão desativados por predefinição. Quando ativados, o Luxel analisa localmente o microfone selecionado enquanto a app está aberta e disponível. Procura áudio contínuo semelhante a fala, não reuniões, chamadas, participantes ou consentimento. O macOS pode mostrar o indicador de microfone em utilização.\n\nAs amostras de áudio são eliminadas, a menos que escolha explicitamente Iniciar gravação. A escuta não cria pré-gravação, ficheiros multimédia, itens no histórico, transcrições, ficheiros auxiliares ou envios para a nuvem. Um alerta nunca inicia uma gravação automaticamente. Concentração ou Não incomodar podem ocultar a notificação. A deteção pausa durante uma gravação e quando o Mac está bloqueado, em repouso ou indisponível; deixa de funcionar quando sai do Luxel.\n\nCAPTURE SEM PERDER A CONCENTRAÇÃO\n\nComece pela barra de menus, atalhos globais, seletor de área, Atalhos, ações URL ou linha de comandos autenticada. Grave um ecrã, uma janela, uma região exata ou apenas áudio a 1–120 FPS. Adicione contagem decrescente, efeitos do cursor e cliques, teclas opcionais, microfone, áudio do sistema e câmara.\n\nGUARDE O QUE ACABOU DE ACONTECER\n\nAtive o Replay Buffer antes de uma sessão para manter disponíveis até cinco minutos de atividade recente e guardar depois um erro ou momento passageiro.\n\nEDITE E TRANSCREVA LOCALMENTE\n\nCrie uma transcrição pesquisável no Mac, salte para as palavras ditas, separe vozes e corte palavras sem alterar o original. Apare, redimensione, recorte, mude a velocidade e ajuste o áudio.\n\nEXPORTE PARA QUALQUER ENTREGA\n\nExporte MP4, ProRes, WebM, AV1, GIF, APNG, M4A, ALAC, WAV, CAF ou FLAC. Guarde predefinições reutilizáveis ou exporte diretamente para um destino.\n\nPRIVACIDADE DESDE A CONCEÇÃO\n\nGravação, escuta, edição, transcrição, identificação de vozes e exportação acontecem no Mac. O Luxel não envia os seus conteúdos nem recolhe dados da app. Não é necessária uma conta.",
  "keywords": "gravar ecrã,captura,áudio,replay,transcrição,edição de vídeo,GIF,WebM",
  "whatsNew": "Novidade: os Alertas de Deteção de Voz opcionais podem procurar localmente áudio contínuo semelhante a fala e propor uma gravação apenas de áudio. A funcionalidade está desativada por predefinição, não guarda nada durante a escuta e só grava quando escolhe explicitamente Iniciar gravação. Esta atualização também melhora a fiabilidade.",
  "marketingUrl": "https://luxel.media/pt-PT/",
  "supportUrl": "https://luxel.media/pt-PT/support",
  "privacyPolicyUrl": "https://luxel.media/pt-PT/privacy",
  "screenshotCaptions": [
    "Capture diretamente da barra de menus",
    "Alertas de voz locais e opcionais: decide se quer gravar",
    "Selecione exatamente a área necessária",
    "Transcreva e edite no Mac",
    "Exporte em todos os formatos do seu fluxo",
    "Mantenha os controlos de gravação por perto",
    "Aperfeiçoe sem alterar o original"
  ],
  "counts": { "name": 5, "subtitle": 25, "promotionalText": 110, "description": 2352, "whatsNew": 336, "keywordBytes": 76 }
}
```

## Shared App Review notes

App Review notes are not a localized storefront field. Use the single English value in `docs/app-review/review-notes.txt`, which stays below Apple's 4,000-byte limit and documents the optional notification-then-microphone permission sequence, local analysis, discarded samples, automatic pauses, explicit recording action, and no-account path.

## App Privacy decision

The private App Store Connect answer could not be retrieved from the local environment. Repository release documentation records the current declaration as **Data Not Collected**. Keep that declaration for this release, subject to confirming it in App Store Connect and completing the final binary/network audit. Apple's App Privacy definition treats data processed only on the device and never sent to a server as not collected. Speech Detection Prompts process microphone samples locally, discard them unless the user explicitly starts the existing audio-only recording workflow, and send neither samples nor detector results to Luxel, Raw Context, analytics providers, or other third parties. The feature therefore adds microphone use but does not add developer data collection.

This conclusion depends on the shipped implementation retaining all of these properties:

- no microphone samples, detector scores, prompt events, analytics, diagnostics, or identifiers leave the Mac;
- listening creates no pre-roll, recording, history item, transcript, sidecar, or cloud upload;
- any audio file exists only after the user explicitly starts recording and remains user-controlled local content;
- no third-party SDK added by this release transmits audio or derived data.

If any of those facts change, stop submission and re-answer App Privacy before release.

## App Store Connect handoff

1. Re-fetch the public listing and record any baseline change.
2. Open an editable macOS version in App Store Connect and confirm the configured localization records match the 11 locale identifiers above.
3. Copy each JSON value exactly. App Review notes come from `docs/app-review/review-notes.txt`.
4. Use the exact Speech Detection screenshot at position 2 without alteration. For any future locale-specific screenshot, run the real app in that locale and capture it again; do not add or replace text in an image.
5. Run `bun docs/ux/app-store/validate-listing-metadata.mjs` and confirm the App Store Connect counters independently.
6. Confirm the App Privacy answer and privacy-policy URL.
7. Save as a draft. Do not publish from this document change.
8. Compare the draft field-for-field with this file and attach evidence to issue #57 before closing it.
