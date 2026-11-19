# « Réglages poussés » (settings-push) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre les réglages atteignables sur les deux générations — appui long sur START pousse une page de réglages — avec BACK pur (sortie, jamais surchargé) et sans l'écran d'avertissement de premier lancement.

**Architecture:** Une seule page de réglages poussée (`Ui.pushView`, le précédent `ModeDelegate`/`PowerOffDelegate` du même fichier) qui sert les rangées du mode courant plus celles du son/alimentation ; le geste long sur boutons est une échéance `dueLong` de plus dans le pump `pumpDue` déjà en place ; la page de base garde la voie tactile directe. Le pseudo-mode « set » et le module `StartWarning` disparaissent.

**Tech Stack:** Monkey C (Connect IQ SDK 9.1.0 pour les gates, 9.3.0 pour la matrice), pilote de tests `testsNN.ps1` durci (modèle `C:\Users\greg\git\int-x5-build\tests39.ps1` : épreuve de disponibilité du simulateur avant les chunks).

**Spec:** `C:\Users\greg\git\int-x5-build\settings-push-design.md` (les 6 décisions du 17 nov. 2026 — l'utilisateur a validé le document, décisions 1-6 comprises).

## Global Constraints

- Tout le travail se fait dans la worktree `C:\Users\greg\git\int-x5`, branche `x5-integration`, poussée par `git push origin HEAD:app-overhaul`. HEAD de départ : `bec3ffa`. Chaque task pousse son commit immédiatement après l'avoir fait.
- Ne jamais committer `OneR remote/barrels.jungle`, `OneR remote DF/barrels.jungle`, `OneR remote/.vscode/settings.json`. `git add` avec chemins explicites, jamais `commit -am`. Message de commit écrit dans un fichier et appliqué par `git commit -F` (le 17 nov., les guillemets imbriqués en ligne de commande ont cassé l'argument).
- Les commentaires de décision du code portent la date (« decision of 17 nov. 2026 ») ; les numéros de Cahier restent à la charge de l'utilisateur — ne rien numéroter.
- Plus jamais d'appel à `System.exit()` nulle part dans l'app (état depuis exit-0, à préserver).
- Jamais de compilation en parallèle d'une session simulateur vivante ; séquentiel strict (leçon run36). Ne pas toucher la fenêtre du simulateur pendant les runs.
- Les pilotes de suite unitaire vivent dans `C:\Users\greg\git\int-x5-build` (hors dépôt, non commités) ; un nouveau numéro à chaque fois que le jeu de vecteurs change.
- La copie de la fiche magasin (`docs/store-listing-1.0.0.md`) ne se touche qu'avec validation explicite de l'utilisateur, mot pour mot.
- Les vecteurs unitaires existants ne touchent que `rows("set")[0]` (SOUND) et `Settings.focus` — ne pas changer cette emprise.

## Review Focus

1. **Appui long pendant une écriture caméra en vol** (enregistrement, STARTING/STOPPING) — la page doit s'ouvrir sans trahir l'état : aucune trame de shutter au geste, les changements de valeur suivent la règle de déferral existante (`settingMayGo`/`dueSet`). Banc marq du Task 4.
2. **Relâchement juste sous le seuil** — un appui relâché avant 700 ms ne doit jamais ouvrir la page : le bras `dueLong` s'annule au relâchement, sinon chaque appui-court suivi d'un pompage tardif ouvrirait la page par erreur. La branche `onKeyReleased` du Task 4, puis le banc marq (un tap START déclenche, ne page pas).
3. **Appui long pendant qu'un menu est déjà devant** (menu Mode, force model) — le geste appartient à la vue de base ; rien ne doit se passer derrière un menu ouvert. Banc du Task 4.
4. **Le petit écran : engrenage déplacé en haut à droite** — à l'angle des plus petits cadrans (approachs7042mm), l'icône ne doit ni chevaucher le point START ni mordre l'arc du nom de caméra ; la réserve de `drawNameArc` tombe mais la marge au point START reste. Chargement + regard sur l'écran au Task 5.
5. **Tap engrenage pendant la recherche de lien** (UI_SEARCHING / NOT_FOUND) — la page s'ouvre quand même ; l'écriture d'une valeur attend `settingMayGo` comme partout. Banc épix du Task 3.

---

### Task 1: Couper l'avertissement de premier lancement entièrement

**Files:**
- Delete: `OneR remote/source/StartWarning.mc`, `OneR remote/test/WarningTest.mc`
- Modify: `OneR remote/source/RemoteDelegate.mc` (la fonction `warnHolds` :124-128 et ses huit gardes : :136 onSelect, :228 onTap, :236 onHold, :259 onKeyPressed, :282 onBack, :336 onUp, :350 onDown, :471 onMenu ; `openWarningMenu` :522-546 et son `WarningMenuDelegate`, le renouvellement de countdown :815-818 ; le `using StartWarning` :10)
- Modify: `OneR remote/source/RemoteView.mc` (le `using StartWarning` :13, le drapeau `warnAsked`/`warnIntro` :331-338, `drawWarning` :1028+ ; le champ `warnIntro` est défini sur la classe d'application — grep `warnIntro` pour le site de définition)
- Modify: `docs/x5-pr-app/watch-app.md` (les lignes du warning des tables features/quirks)
- Test: le pilote — créer `C:\Users\greg\git\x5-build\tests40.ps1` (copier `tests39.ps1`, retirer les 7 noms WarningTest, journal `oneremote-tests-run40-warning.log`) — hors dépôt.

**Interfaces:**
- Consumes: rien de nouveau.
- Produces: plus aucun `warnHolds` (les handlers gardent leur corps, moins la garde) ; plus aucune référence à `StartWarning` ; la suite attendue est de 60 vecteurs.

- [ ] **Step 1:** grep d'emprise avant coupe : `StartWarning|warnIntro|warnHolds|drawWarning|WarningTest` dans `OneR remote/` et `docs/` — noter les sites ; les supprimer tous (fichiers, gardes, drapeaux, menu, champ).
- [ ] **Step 2:** Vérifier le vide : `grep "StartWarning\|warnHolds\|warnIntro"` dans `OneR remote/source` et `OneR remote/test` → aucune réponse.
- [ ] **Step 3:** Régressif, séquentiel strict : gates 9.1/9.3 (`gate91int.ps1`, `gate93int.ps1` — attendu `int=0`/`int93=0`), matrice (`compilematrix.ps1` — attendu 125/125 OK), suite (`tests40.ps1` — attendu 60/60, 4 chunks : 15+15+15+15), chargements sans crash via le motif `loadone.ps1` sur marqexpedition puis epix2pro51mm (PRG de tâche construits par le motif `exitrealbuild.py`, nommés `t1-real-<device>.prg`).
- [ ] **Step 4:** watch-app.md à l'heure du jour (lignes warning retirées, note datée de la coupe).
- [ ] **Step 5:** Commit : message fichier + `git commit -F` ; `git add "OneR remote/source/RemoteDelegate.mc" "OneR remote/source/RemoteView.mc" "docs/x5-pr-app/watch-app.md"` et le retrait de `git rm "OneR remote/source/StartWarning.mc" "OneR remote/test/WarningTest.mc"`.

### Task 2: BACK pur — supprimer l'échelle de bec3ffa

**Files:**
- Modify: `OneR remote/source/RemoteDelegate.mc` (suppression de la méthode `onBack` :278-290 entière ; le bloc de commentaire :264-277 devient une note datée : remplacée le 17 nov. au soir par BACK pur + page poussée — l'échelle n'aura pas vécu plus d'un commit)

**Interfaces:**
- Consumes: rien de nouveau.
- Produces: aucun `onBack` surcharge dans l'app ; le delegate hérite du comportement système (pop d'une vue poussée, sortie depuis la vue racine).

- [ ] **Step 1:** grep `onBack` dans `OneR remote/test/` — aucun vecteur ne nomme l'échelle (vérifié le 17 nov., à confirmer par le grep) ; s'il y en avait un, le retirer du pilote et du test.
- [ ] **Step 2:** Supprimer la méthode, remplacer le commentaire par la note datée (une phrase sur le pourquoi : la doc SDK nomme BACK non réclamé sur la vue racine comme seule sortie propre des appareils à boucle ; c'est maintenant le seul chemin, partout).
- [ ] **Step 3:** Régressif : gates int=0, matrice 125/125, `tests40.ps1` 60/60, chargements `t2-real-*` sans crash.
- [ ] **Step 4:** Commit (mêmes chemins explicites, hors watch-app.md si rien n'y change — la table « Exit » a déjà été mise à jour par exit-0 ; ajouter la ligne « BACK n'est jamais surchargé »).

### Task 3: La page de réglages poussée ; le pseudo-mode « set » disparaît

**Files:**
- Modify: `OneR remote/source/RemoteDelegate.mc` : retirer `inSettingsUI` :34-37, `setReturnMode`/`setReturnLabel` :43-44, la branche `id.equals("set")` de `applyMode` :560-572, l'entrée `out.add(["Settings", "set"])` de `modeList` :77, la branche `inSettingsUI()` de `runStart` :195-202 (le `:power` y court : c'est la rangée de la page, plus de la base), les branches `inSettingsUI()` :441 et :644, l'appel de rangée `rows("set")` dans `focusRowAt` :247-250. Ajouter : `function openSettingsPage()` au niveau fichier + la classe `SettingsPageView`/`SettingsPageDelegate` (Menu2, modèle `ModeDelegate`) dans le même fichier. Extraire le corps de `stepFocused` :293-304 en `hidden function stepRow(id, row)` au niveau fichier, appelé par `stepFocused` (vue de base, voie tactile moderne) et par la page.
- Modify: `OneR remote/source/RemoteView.mc` : retirer la branche de dessin de la page « set » et la ligne `startCue = inSettingsUI() ? null : ...` :426 (le cue redevient `BLEBarrel.videoMode ? C_RED : C_TEXT` sans condition) ; publier la position du centre de l'engrenage dessiné dans un champ de module pour le hit-test.
- Modify: `OneR remote/test/UiTest.mc:70-83` — `tapIsNotStartButKeyIs` : remplacer l'emprise « set » par `BLEBarrel.recState = BLEBarrel.stateStarting;` (la branche UI_STARTING de runStart répond true sans trame — sans effets de bord, le but d'origine de l'emprise) ; assertions inchangées.
- Test: le jeu compte toujours 60 vecteurs ; pilote `tests40.ps1` réutilisé (même nom de vecteur).

**Interfaces:**
- Consumes: `Settings.rows(id)`/`step(id, row, dir)`/`key`/`label`/`frames` — inchangés de forme ; `pumpDue` (la page écrit par `pendingSetFrames`/`pendingSetKey`/`dueSet` déjà pompés).
- Produces: `openSettingsPage()` — fonction de module dans `RemoteDelegate.mc`, sans argument, renvoie void ; c'est l'action unique du geste long (Task 4) et du tap d'engrenage (ce task). `stepRow(id, row)` — hidden fichier, mêmes écritures différées que `stepFocused`.
- La page nomme l'id par famille : `step(currentModeId, row)` pour les rangées du mode, `step("set", row)` pour son/alimentation — avant, la page était pseudo-mode et passait « set » partout par construction (nuance à ne pas rater).
- Entrées de la page dans ce task : le tap de l'engrenage (cible de hit ajoutée : le centre publié par RemoteView, rayon ~rr*0.09 — la zone suit l'icône, qui bougera au Task 5) et `onHold` à l'écran (l'ancien focus par rangée cède au geste, uniforme avec les boutons). Le tap sur rangée garde le focus (voix tactile moderne).
- `Settings.rows("set")` et la branche `id.equals("set")` de `Settings.frames` restent : c'est la famille de la page, plus le pseudo-mode.

- [ ] **Step 1:** Implémenter la page (`SettingsPageDelegate` : UP/DOWN = focus du menu, choix d'une ligne = `stepRow` de la famille de la rangée puis r'ouverture de la page à la ligne choisie ; la ligne `:power` appelle `confirmPowerOff(dev)` comme aujourd'hui :199) et `openSettingsPage()`.
- [ ] **Step 2:** Couper le pseudo-mode (liste des sites ci-dessus) ; adapter UiTest:70-83.
- [ ] **Step 3:** Vérifier le vide : grep `inSettingsUI|setReturnMode|"set"]` — `rows("set")` et la branche frames restent seuls répondants.
- [ ] **Step 4:** Régressif : gates int=0, matrice 125/125, `tests40.ps1` 60/60, chargements `t3-real-*` sans crash. Banc épix (simu) : tap engrenage → page ; changer son et valeur de mode ; BACK revient à la base, BACK sort ; tap rangée puis balayage toujours verts ; ouvrir la page pendant UI_SEARCHING et changer une valeur — Review Focus 5.
- [ ] **Step 5:** watch-app.md : la page réglages décrite comme vue poussée, les entrées, le retrait du pseudo-mode. Commit.

### Task 4: L'appui long sur START (boutons) — seuil testable, bras dans le pump

**Files:**
- Modify: `OneR remote/source/RemoteDelegate.mc` : constante de module `LONG_PRESS_MS = 700` et `function holdingDue(startAt, now) as Lang.Boolean` au niveau fichier (non hidden, testable — la même forme que `inSettingsUI` avant sa coupe) ; dans `onKeyPressed` :258-262, armer `dueLong = startKeyAt + LONG_PRESS_MS` sur KEY_ENTER ; dans `pumpDue` :391-408, une jambe `dueLong` après les trois autres : à échéance, `dueLong = null` puis `openSettingsPage()` ; `onSelect` :135-146 et `runStart` court-circuités si le long a déjà été servi (drapeau `longFired`, posé par la jambe, levé au SELECT consommé) ; un `onKeyReleased` KEY_ENTER qui annule `dueLong` quand le relâchement précède l'échéance.
- Test: Modify `OneR remote/test/UiTest.mc` — deux vecteurs nouveaux.

**Interfaces:**
- Consumes: `openSettingsPage()` (Task 3).
- Produces: `holdingDue(startAt as Lang.Number, now as Lang.Number) as Lang.Boolean` — pure, seule règle du seuil ; suite attendue 62 vecteurs.

- [ ] **Step 1: Write the failing tests** — dans `UiTest.mc`, à la suite des vecteurs de seuil existants :

```
(:test)
function holdAtThresholdFires(logger) {
    return holdingDue(1000, 1000 + 700) == true;
}
(:test)
function holdJustUnderThresholdDoesNotFire(logger) {
    return holdingDue(1000, 1000 + 699) == false;
}
```

- [ ] **Step 2:** Créer `tests41.ps1` (62 noms : les 60 plus les deux nouveaux, journal `oneremote-tests-run41-longpress.log`) ; courir — attendu : échec de compilation du vecteur (`holdingDue` inconnu), trace « Unable to resolve holdingDue ».
- [ ] **Step 3:** Implémenter `LONG_PRESS_MS`/`holdingDue` (un seul comparatif `now - startAt >= LONG_PRESS_MS`) puis câbler la jambe `dueLong` dans `pumpDue` et l'appel depuis `onKeyPressed`.
- [ ] **Step 4:** Run `tests41.ps1` — attendu 62/62.
- [ ] **Step 5:** Régressif complet : gates int=0, matrice 125/125, chargements `t4-real-marqexpedition`/`t4-real-epix2pro51mm` sans crash. Banc marq (simu, decisive pour l'utilisateur) : appui court START = déclencheur comme avant ; appui long = page ; la page fonctionne UP/DOWN/START ; BACK revient puis sort ; appui relâché à 400 ms ne page pas (Review Focus 2) ; appui long pendant enregistrement — aucune trame de shutter au geste (Review Focus 1) ; appui long avec le menu Mode devant — rien derrière (Review Focus 3).
- [ ] **Step 6:** watch-app.md : le geste nommé. Commit.

### Task 5: L'engrenage déménage en haut à droite, à côté du point START

**Files:**
- Modify: `OneR remote/source/RemoteView.mc` : `drawBackCue` :789-796 devient `drawSettingsCue` — le long de l'anneau à ~+52° (angle de départ, ajustable au banc), rayon `rr - 30`, taille `rr * 0.065` inchangés ; couleur `C_DIM` permanente (l'ambre `Settings.focus > 0` tombe — langue du BACK-focus disparu) ; publier le centre dessiné pour le hit-test ; retirer la réserve engrenage de `drawNameArc` :766 (« stay clear of … the gear », le clamp `deg > 324 - 22`) en gardant la marge au point START (le clamp côté dots `lastDot + 22` reste) ; le commentaire :756-757 à l'heure du jour.
- Modify: `OneR remote/source/RemoteDelegate.mc` : la cible de tap de l'engrenage (Task 3) lit le centre publié par RemoteView — le déplacement de l'icône déplace la cible sans changer son rayon.

**Interfaces:**
- Consumes: le centre publié par le Task 3, `openSettingsPage()`.
- Produces: rien pour les tasks suivants.

- [ ] **Step 1:** Redessiner à la nouvelle position (la position du point START +30° est la seule ancre ; l'espacement angulaire se règle au banc, documenter l'angle final dans le commentaire).
- [ ] **Step 2:** Suivre la cible de tap ; vérifier le grep `drawBackCue` — plus aucun répondant.
- [ ] **Step 3:** Régressif : gates int=0, matrice 125/125, chargement `t5-real-approachs7042mm` sans crash plus regards épix/marq (le plus petit écran, Review Focus 4 — l'icône ne chevauche ni le point ni l'arc du nom).
- [ ] **Step 4:** watch-app.md (position et sens de l'icône) + note pour la refonte de la capture 1/5 dans la liste des captures à faire. Commit.

### Task 6: Régressif final sur le rendu, et la proposition de copie magasin

**Files:**
- Create: `C:\Users\greg\git\int-x5-build\sp-realbuild.py` (le motif `exitrealbuild.py`, sorties `sp-real-marqexpedition.prg` et `sp-real-epix2pro51mm.prg`).
- Pas de changement de source sauf défaut trouvé ; pas de touche à `docs/store-listing-1.0.0.md` sans validation.

**Interfaces:**
- Consumes: tout le rendu des tasks 1-5.
- Produces: les binaires de banc de l'utilisateur et la copie proposée (chat seulement).

- [ ] **Step 1:** Sur HEAD rendu : gates 9.1/9.3, matrice 125/125, `tests41.ps1` 62/62 (le pilote durci fait l'épreuve de disponibilité — pas de faux bloquants), `sp-realbuild.py`, chargements `loadone.ps1` marq 90 s + epix 120 s sans crash.
- [ ] **Step 2:** Vérifier que les cinq commits des tasks sont bien poussés (`git status -sb` — la branche à jour avec `origin/app-overhaul`).
- [ ] **Step 3:** Écrire la proposition de copie pour la fiche (le bloc « HOW TO LEAVE THIS APP » refait sur « BACK quitte l'app, toujours », l'appui long pour les réglages, les paragraphes du warning EN/FR retirés, les miroirs FR, les légendes des figures 1 et 5) dans le chat — ne rien écrire dans le fichier avant le mot de l'utilisateur.
- [ ] **Step 4:** Rappeler à l'utilisateur ses deux devoirs de banc (marq : gestes complets ; épix réel : appui long à l'écran, voie tactile inchangée) et la liste des captures à refaire.

---

## Self-review (faite par l'auteur du plan)

- Couverture de la spec : décision 1 (BACK pur) → Task 2 ; décision 2 (appui long partout) → Tasks 3-4 (écran : onHold au Task 3, boutons au Task 4) ; décision 3 (page son/alimentation poussée, pseudo-mode mort) → Task 3 ; décision 4 (warning coupé) → Task 1 ; décision 5 (voie tactile gardée) → Task 3 (stepFocused conservé, UiTest ajusté) ; décision 6 (icône à côté du point START) → Task 5. Les trois risques du doc de conception (UP jamais requis, taille, ouverture directe) sont tenus : le design par échéance ne dépend pas du UP ; les tailles de PRG sont lues à chaque matrice ; l'ouverture directe est l'état voulu, la fiche magasin porte le mode d'emploi (Task 6).
- Types cohérents : `openSettingsPage()` sans argument partout ; `holdingDue(startAt, now)` nommé pareil au test et à l'implémentation ; `stepRow(id, row)` nommé pareil aux deux appelants.
- Le vecteur UiTest ajusté garde son nom et ses assertions — le compte ne bouge qu'aux tasks 1 (-7) et 4 (+2).
