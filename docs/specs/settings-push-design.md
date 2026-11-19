# Conception « réglages poussés » (chantier settings-push) — décisions du 17 nov. 2026

## Motif (ce que le banc a montré)

- Bec3ffa (échelle BACK) laisse les appareils à boucle sans réglages atteignables :
  la doc SDK est formelle, sur la vue de base d'un hôte widget l'app « will never
  receive either the up/down button or up/down swipe events » — donc changer une
  valeur y était impossible avant même l'échelle. Seules les vues poussées
  échappent à la restriction (« Any views pushed on top of the base view… will not
  have these input restrictions »).
- Régle de l'utilisateur, 17 nov. 2026 : « Le back doit être propre et servir
  uniquement à sortir de l'app. »
- Le warning d'ouverture n'a plus d'objet : il enseignait « BACK ne sort pas »,
  règle qui vient de disparaître.

## Décisions de l'utilisateur (17 nov. 2026, brainstorm du soir)

1. BACK jamais surchargé : sur la page de base, BACK appartient à l'OS et sort de
   l'app, sur les deux générations. L'échelle de bec3ffa est retirée.
2. Appui long sur START = page Réglages, partout (boutons comme tactiles ; sur
   tactiles : appui long à l'écran, onHold).
3. La page son/alimentation devient poussée elle aussi ; le pseudo-mode « set »
   disparaît. Une seule page de réglages, un seul code.
4. Le warning disparaît entièrement : l'écran, son menu countdown, le module
   StartWarning, ses 7 vecteurs.
5. La voie tactile directe est gardée sur les tactiles (tap = focus de rangée,
   balayage = changement de valeur sur la page de base — validée au banc epix du
   17 nov.) ; la page poussée est la voie des appareils à boutons.
6. L'icône de la roue dentée quitte le bas à droite et va en haut à droite, à
   côté du point START (choix « à côté du point START » au questionnaire du
   17 nov. — l'utilisateur avait dit « en haut à gauche », l'ancre vraie étant le
   point rouge, le côté suit l'ancre).

## Design

### A. Le geste long (RemoteDelegate.mc)

- Deux amorceurs, une seule action : pousser la page Réglages.
  - Boutons : la DOWN KEY_ENTER horodate déjà startKeyAt (existant). Armer à la
    DOWN une échéance dueLong = t + 700 ms, la même famille de délai que dueTap
    (pas d'objet Timer, pompage par le tick de la vue — la leçon « Too Many
    Timers » de la page 47 du même fichier). À l'échéance, si aucun déclencheur
    n'a été décidé, c'est l'appui long : pousser la page ; la suite onSelect
    consomme le SELECT sans runStart. Appui court : runStart comme aujourd'hui,
    unchanged.
    Ce choix par échéance ne dépend pas de recevoir le UP/ACTION sur la vue de
    base d'un appareil à boucle — l'inconnu n° 1 du banc. Si le UP arrive, il ne
    fait qu'annuler l'échéance plus tôt.
  - Tactile : onHold remplace le focus par rangée (le tap fait le focus, le geste
    long ouvre la page — uniforme avec les boutons).
- Seuil et décision extraits en fonction pure testable (holdingDue(startAt, now))
  — 2 vecteurs unitaires de plus (juste sous le seuil, au seuil).

### B. La page poussée (une vue, un code)

- Nouvelle vue + delegate dans RemoteDelegate.mc (même module que le modèle —
  précédent : ModeDelegate et PowerOffDelegate vivent là et sont poussés de là).
- Contenu : rows(currentModeId) du mode courant + rows("set") (son, alimentation)
  — le modèle Settings.mc ne change pas de forme, rows() garde ses deux familles.
- Host : Menu2, titre de ligne = libellé, sous-titre = valeur courante ; choisir
  une ligne applique le pas suivant par le chemin existant Settings.step →
  pendingSetFrames/dueSet/flushSetting (l'écriture différée et sa attente de
  changement de mode sont gardées telles quelles) et r'ouvre la page à la ligne
  choisie. UP/DOWN déplacent le focus du menu, START change la valeur, BACK
  revient à la page de base (comportement système, non traité).
- Entrées de la page : appui long START (boutons/écran) et l'engrenage à l'écran
  (son tap la pousse). Position de l'icône (décision 6) : `drawBackCue` devient
  la cue du geste réglages et se dessine le long de l'anneau à côté du point
  START (à ~+52°, le long de l'arc, au-dessus du point à +30° ; angle et espace
  à régler au banc), même rayon rr−30 et même taille rr*0.065 qu'aujourd'hui.
  Sa couleur reste la dim permanente d'affordance ; l'ambre « un réglage a le
  focus » tombe — c'était la langue du BACK-focus disparu.
- Conséquences ménagées : la zone de tap de l'engrenage suit l'icône (cible
  ajoutée au hit-test, c'est l'entrée tactile de la page) ; la réserve de
  drawNameArc (« stay clear of … the gear », clamp à 302°) tombe avec l'icône
  partie du bas — le nom de caméra peut descendre plus à droite, en gardant la
  distance au point START ; les commentaires de RemoteView (ligne 756) et les
  tables de watch-app.md sont réécrits.

### C. Retraits

- onBack de RemoteDelegate : méthode supprimée entièrement (le défaut du delegate
  pops/sort) ; le commentaire d'échelle devient une note datée : remplacée le
  17 nov. par BACK pur + page poussée.
- Pseudo-mode « set » : branche id=="set" de applyMode, inSettingsUI() et ses
  branches (runStart, focusRowAt, :441, :644), la comptabilité setReturnMode, le
  dessin rows("set") de RemoteView (il déménage dans la page poussée).
- Warning : drawWarning et le drapeau warnIntro/warnAsked de RemoteView, toutes
  les gardes warnHolds() du delegate, openWarningMenu + WarningMenuDelegate, le
  module StartWarning.mc (et ses propriétés de stockage), les 7 vecteurs
  WarningTest des pilotes de test, les lignes des tables de watch-app.md.

## Régressif attendu

- Suite unitaire : 67 − 7 (warning) + 2 (seuil long-press) = 62 vecteurs, run40
  avec le pilote durci de tests39 (épreuve de disponibilité du simu).
- Gates 9.1/9.3 zéro erreur introduite ; matrice 125 produits ; PRG de banc
  marq + epix ; chargements sans crash.
- Banc utilisateur : marq simu (appui long → page, UP/DOWN changent les valeurs
  dans la page, BACK revient puis sort, plus aucune surcharge de BACK) ; puis
  epix réel (l'appui long à l'écran, la voie tactile inchangée).

## Copie du magasin (à redemander, attente de validation utilisateur)

- La proposition « HOW TO LEAVE THIS APP » du 17 nov. (échelle BACK) est caduque :
  refaire sur « BACK quitte l'app, toujours ; réglages : appui long ».
- Les paragraphes du warning de premier lancement (EN et FR) tombent.
- Captures : fig. 1 (warning) à remplacer par la page réglages poussée ; fig. 5
  (menu sans Exit) déjà prévue ; légendes à l'avenant.

## Risques ou inconnues

1. Le UP/ACTION de KEY_ENTER est-il reçu sur la base d'un hôte widget ? Le design
   par échéance n'en dépend pas ; le banc le dirait seulement pour la nuance.
2. Taille et mémoire : une vue de plus — la matrice de compilation nommerait un
   dépassement de budget ; comparer les tailles de PRG aux chiffres de exit-*.
3. Premier lancement sans warning : l'app s'ouvre directement sur la page d'état
   — c'est ce que l'utilisateur demande ; rien ne l'explique plus à l'écran, la
   fiche magasin porte le mode d'emploi.
