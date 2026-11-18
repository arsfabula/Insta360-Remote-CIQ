# Fiche magasin — Insta360 Remote 1.0.0

Page : https://apps-developer.garmin.com/apps/bb53f4bb-6c8c-4369-bca9-84cc09b25526
Textes : anglais (principal), puis français. Sections « description » et « what's new »
à coller telles quelles dans le formulaire du développeur.
Ce fichier n'est pas la fiche publiée : il en est la source versionnée.

Faits vérifiés dans le code à `bd347f7` (128 produits, 128 OK en 9.3.0) : commandes et
textes d'écran dans `OneR remote/source/RemoteDelegate.mc` / `RemoteView.mc` /
`Settings.mc` / `Levels.mc` (la liste nommait encore `StartWarning.mc` : l'écran est
coupé depuis le 17 nov. 2026, voir la note de chantier en fin de fichier). Le crédit
suit la formule du dépôt (`@no84by`, auteur du PR d'origine et du travail de protocole).

---

## 1. Description (EN)

**MAJOR UPDATE — READ FIRST: HOW TO QUIT THIS APP**

* BACK on the watch does not close it.
* To leave it: press **MENU**, then choose **Exit app**.
* As a safety, the first few starts show a warning about this behaviour.

**WHAT IT DOES**

* Controls an Insta360 camera from your Garmin watch over Bluetooth: **X6, X5, X4 / X4 Air, X3 / X2 / ONE series**. The GO and Ace series are not supported.
* Supports multiple shooting modes and settings.
* GPS overlay is supported. Activate it in the menu.
* Connects to the first Insta360 camera it sees. No pairing needed.

**HOW TO DRIVE IT**

* **UP / DOWN / SWIPE** — change mode, or change the value of the focused setting.
* **START** — start recording / take the photo; while recording, stop it. On the "No camera" screen it starts a new search.
* **BACK** — move the settings focus (mode → settings rows → mode).
* **MENU** — app menu: mode list, GPS on/off, Force model, Exit app.
* While recording: **UP** adds a highlight, **DOWN** = Track That.
* Touch models: tap a row to focus it, swipe to change it, tap the middle to start.
* The Settings page can power the camera off.

**GOOD TO KNOW**

* If the camera asks for permission, accept on the camera (the watch says "Allow on camera").
* If the camera is already recording, the app will switch to recording mode.
* X6 support is experimental. Please use the "Contact developer" link to report bugs.

**CREDIT**
This version is a rebuild, and it stands on the original app and its protocol work by
**@no84by** — much of what works here works because of him.

---

## 2. What's New (EN, 1.0.0)

* The app has been rebuilt: new screen with a status ring, mode dots, and the camera's settings column on the watch.
* **Insta360 X6 support** — experimental.
* The camera model is recognised by its name; MENU → **Force model** lets you try another model's functions. **Use at your own risk!**
* A first-run notice explains how to quit the app.
* While recording you can **highlight** (UP) and **Track That** (DOWN).
* Reliability: out-of-memory and start-up fixes.
* 13 older devices whose memory cannot hold this app were taken off the supported list.
* Thanks to **@no84by**, for the UI and his additions to the understanding of the communication protocol.

---

## 3. Description (FR)

**MISE À JOUR IMPORTANTE — LISEZ D'ABORD : COMMENT QUITTER CETTE APPLICATION**

* La touche BACK de la montre ne la ferme pas.
* Pour la quitter : appuyer sur **MENU**, puis choisir **Exit app**.
* Par sécurité, les premiers démarrages affichent un avertissement à ce sujet.

**CE QU'ELLE FAIT**

* Pilote une caméra Insta360 depuis votre montre Garmin, en Bluetooth : **X6, X5, X4 / X4 Air, gammes X3 / X2 / ONE**. Les gammes GO et Ace ne sont pas prises en charge.
* Prend en charge plusieurs modes de prise de vue et plusieurs réglages.
* L'overlay GPS est pris en charge. Activez-le dans le menu.
* Se connecte à la première caméra Insta360 qu'il voit. Aucun appairage nécessaire.

**COMMENT ON L'UTILISE**

* **UP / DOWN / BALAYAGE** — changer de mode, ou changer la valeur du réglage sélectionné.
* **START** — démarrer l'enregistrement / déclencher la photo ; pendant l'enregistrement, l'arrêter. Sur l'écran « No camera », relance une recherche.
* **BACK** — déplace la sélection des réglages (mode → lignes de réglage → mode).
* **MENU** — menu de l'application : liste des modes, GPS on/off, Force model, Exit app.
* Pendant l'enregistrement : **UP** ajoute un repère (highlight), **DOWN** = Track That.
* Modèles tactiles : toucher une ligne pour la sélectionner, balayer pour changer, toucher le centre pour démarrer.
* La page Settings peut éteindre la caméra.

**BON À SAVOIR**

* Si la caméra demande l'autorisation, acceptez sur la caméra (la montre affiche « Allow on camera »).
* Si la caméra enregistre déjà, l'application bascule en mode enregistrement.
* La prise en charge du X6 est expérimentale. Merci d'utiliser le lien « Contact developer » pour signaler les problèmes.

**CRÉDIT**
Cette version est une reconstruction, qui repose sur l'application d'origine et le travail
de protocole de **@no84by** — beaucoup de ce qui fonctionne ici vient de lui.

---

## 4. What's New (FR, 1.0.0)

* L'application a été reconstruite : nouvel écran avec anneau d'état, points de modes et colonne des réglages de la caméra sur la montre.
* **Prise en charge de l'Insta360 X6** — expérimentale.
* Le modèle de caméra est reconnu par son nom ; MENU → **Force model** permet d'essayer les fonctions d'un autre modèle. **À vos risques !**
* Un avis de premier lancement explique comment quitter l'application.
* Pendant l'enregistrement : **highlight** (UP) et **Track That** (DOWN).
* Fiabilité : corrections de mémoire insuffisante et de démarrage.
* 13 anciens appareils dont la mémoire ne peut pas héberger cette application ont été retirés de la liste des produits pris en charge.
* Merci à **@no84by**, pour l'interface et ses contributions à la compréhension du protocole de communication.

---

## 5. Captures d'écran — ce qu'il faut shooter

Formats à respecter (vérifiés le 16 nov. dans les consignes Garmin et les retours du
forum développeur) : image de couverture 500×500 px max 300 Ko ; captures d'écran
JPG/PNG **max 150 Ko chacune** ; image « hero » 1440×720 px ; icône sur appareil
128×128 px. Le site du magasin **déforme les images qui ne sont pas carrées** : garder un
carré (l'appareil rond centré dedans), jamais l'écran étiré.

Série proposée, dans l'ordre où le magasin les montre (6 images) :

1. **Écran d'accueil lié** — anneau vert, mode courant, colonne de réglages. Légende :
   « Les modes et les réglages de la caméra, sur la montre ».
2. **Enregistrement en cours** — anneau rouge, chrono, repères UP/DOWN. Légende :
   « START arrête ; UP ajoute un repère, DOWN = Track That ».
3. **Page Settings** — valeurs confirmées / grises, « Power off camera ». Légende :
   « Chaque réglage n'est actif qu'après confirmation de la caméra ».
4. **Écran de connexion** — « Insta360 Remote v1.0.0 » sous l'anneau. Légende :
   « La version s'affiche sur l'écran de connexion ».
5. **MENU de l'application** — liste des modes, « GPS overlay », « Force model »,
   « Exit app ». Légende : « MENU : modes, GPS, Force model, Exit app ».
6. **Un modèle rectangulaire** (Edge ou forerunner large) pour montrer que l'interface
   s'adapte. Légende : « Même commande sur les formats rectangulaires ».

À faire aussi : l'**avertissement de premier lancement** en 7e image si tu veux que
l'utilisateur voie ce qu'il rencontre en premier (il est déjà décrit en tête de fiche).

> Note de chantier (17 nov. 2026, plan settings-push — les textes 1 à 4 ci-dessus
> n'ont PAS été touchés : ils attendent la validation mot à mot de l'auteur, la
> proposition est dans l'échange du 17 nov. au soir). Ce qui est sûr dans le code
> rendu : le warning de premier lancement n'existe plus (l'app s'ouvre sur l'état
> de la caméra), BACK sort de l'app partout sans jamais rien d'autre, le MENU ne
> porte plus « Exit app » ni d'entrée « Settings », l'entrée des réglages est
> l'appui long (START / écran) ou le tap de la roue dentée — dessinée en haut à
> droite à côté du point START. Captures : le 1 se reshoote (roue dentée en haut
> à droite), le 3 se reshoote en page poussée (Menu2 au-dessus de l'état,
> sous-titres = valeurs), le 5 se reshoote sans « Exit app », la 7e image
> proposée ne se shoote plus.
>
> État au 18 nov. au soir (ruling de l'auteur) : les deux modèles nouveaux
> (Instinct 3 Solar 45 mm, Instinct E) sont validés au banc simulateur par
> l'auteur, « tout ok » ; `instincte40mm` n'est pas benché à part — même famille
> que le 45 mm, validé par la matrice seulement. Toutes les captures de la série
> ont été retournées par l'auteur sur le nouveau design. Règle de caviardage
> posée par l'auteur : sur toute image, le numéro de série de la caméra est
> remplacé par « R3M073 » — la vraie suffixe est la clé de wake de la caméra et
> ne doit jamais paraître dans un fichier public (même règle que tools.md).

Contrainte physique : les écrans 1, 2, 3, 5, 6 supposent une **caméra réellement liée**.
En atelier, le lien ne se fait que si la caméra est éveillée et accepte l'appairage côté
écran. Sans caméra, seul l'écran de connexion (4) est atteignable.
