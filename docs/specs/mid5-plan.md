# Chantier MID5 — glance passif statique (branche x5-integration, PR #3)

Decision: le glance devient passif-statique. Tranchant 5 501 o mesurés (marq) au lieu
de 58 402 o ; démarrage prouvé en sonde sur marqexpedition ET epix2pro51mm. La passive
complète sans getGlanceView est refusée : non ajoutable à la boucle sur l'epix pro Gen 2
réelle (banc utilisateur 17 nov.) + doc API>=4.

## Etapes

- [x] 1. GlanceView.mc : import BLEBarret retiré, texte statique, words de decision (remplace 152/154/155 cote vue)
- [x] 2. Main.mc onStart : retirer les 3 lignes BLE + l'appel gpsSync() (words deplace avec l'appel)
- [x] 3. Main.mc getInitialView : construction paresseuse du delegate + open + gpsSync() ; mots sur la regle
- [x] 4. Main.mc onStop : garde `if (bleDevice != null)` sur close()
- [x] 5. Main.mc bloc 119-164 : recrire les words des items 152/154/155 (donnees edge1040 conservees comme historique, reference BLEBarrel corrgee 381 -> 788 au retrait)
- [x] 6. BLEBarrel.mc :788 : retirer (:glance) devant class BleDevice + note courte
- [x] 7. Gates 91/93 faites (int=0, int93=0) ; matrice 125/125 OK (compilematrix-930.csv)
- [x] 8. Suite unitaire run36 : 67/67 PASSED (oneremote-tests-run36-mid5.log). Nota : les 2 echecs precedents venaient de la fenetre simu manipulee en cours de course, pas du code.
- [x] 9. Simu marq + epix avec binaires finaux : aucun crash (silence = vivant sans traceurs ; vitalite prounee par la sonde tracee)
- [x] 10. Commit 673b881 (3 fichiers sources seulement) + push 4a0dbb1..673b881 -> app-overhaul
- [/] 11. Reste au banc utilisateur : tap sur le glance -> app complete -> connexion camera (mid5-epix2pro51mm.prg dans passive-test) ; numerotation Cahier a faire par l'utilisateur

## Interdits herites
- Jamais `commit -am` ; jamais les barrels.jungle ; chiffres de serial caches « X5 R3M073 ».
- Ne pas toucher au manifeste (type=widget confirme identique, hash 827B0A9D3864).
