# Chantier exit-0 : sortie par BACK partout (decision du 17 nov. 2026, acceptee par l'utilisateur)

## Motif (donnees)
- Marq sim (17 nov., logs utilisateur) : `Sys.exit()` est un no-op du firmware sur les
  appareils a hebergement widget (40 produits du manifeste, table SDK heberge=widget) ;
  le handler continue apres l'appel — `[res] exit -> none` / `[refused] exit writes
  nothing` = chute vers applyMode("exit"), puis popView.
- Forum Garmin (ingex Garmin) : no-op documente sur appareils sans glances ; pop de la
  vue racine interdit pour les widgets ; seule sortie propre = BACK non consomme sur la
  vue racine.
- L'utilisateur a verifie lui-meme : BACK sort de l'app pendant le warning (return false
  = mecanisme standard), mais en READY avec reglages le BACK cyclait sans fin.

## Decisions acceptees (question du 17 nov.)
1. Echelle de BACK sur les DEUX generations : rangee -> rangee au-dessus -> Mode ->
   sortie propre (remplace le cycle infini `focus+1 mod (n+1)`).
2. Ligne "Exit app" masquee PARTOUT (warning, menu principal, page reglages), sur toutes
   les generations ; la sortie n'est plus que BACK. Suppression des trois sites
   Sys.exit() de l'app.

## Checklist
- [x] 1. Settings.mc : retirer la rangee exit (:exit) de la table rows. FAIT
- [x] 2. RemoteDelegate.mc : retirer les 3 sites exit + mots de decision datee. FAIT
- [x] 3. onBack : echelle rangee->Mode->sortie ; commentaire a jour. FAIT
- [x] 4. References mortes menagees (legendes, couleur rangee, double-tap, watch-app.md,
  texte du warning ramene aux 2 phrases vraies — accord utilisateur du 17 nov.). FAIT
- [x] 5. Regression : gates int=0/int93=0, matrice 125/125 OK, run37 67/67 (le 1er essai
  s'etait accroche sur une session simu morte, pas le code : re-run immediat au vert),
  chargements marq+epix sur exit-real-*.prg sans crash. run38 = faux echec d.environnement
  (simulateur mort avant les chunks, 5x Unable to connect). run39 au vert 67/67 avec le
  pilotage durci (tests39.ps1 : epreuve de disponibilite du simu avant les chunks).
- [x] 6. Commit bec3ffa (4 fichiers : RemoteDelegate, RemoteView, Settings, watch-app.md)
  + push 673b881..bec3ffa -> app-overhaul. FAIT
- [ ] 7. Banc utilisateur simu marq avec exit-test\exit-real-marqexpedition.prg : BACK
  rangee->Mode->sortie ; plus aucune ligne Exit dans les 3 menus ; warning a 2 lignes.
  Puis banc reel epix (inchange par ailleurs).
- [ ] 8. Copie fiche magasin : 6 places citent Exit app — proposition faite au user le
  17 nov., en attente d'accord ; puis refaire la capture 5 (menu sans Exit).
