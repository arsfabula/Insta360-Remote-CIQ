using Levels;
using BLEBarrel;

// La moitié « menu X6 » de la suite unitaire : la table du niveau 3 decisee le
// 15 nov. (x6-menu-design.md, decisions B1 + A1). Une table est une donnee,
// pas une fonction : ce que ces vectors pingent est la FORME de la table — sa
// taille, ses ids dans l'ordre, ses familles — parce que c'est exactement ce
// que le banc lira (le menu construit ses items a travers rowsMain/rowsRes).
// Les deux vectors visent la table attendue, pas l'actuelle : ils sont ecrits
// avant la reecriture de rowsMainL3/rowsResL3 (rouge voulu, TDD).

// Les ids d'une rangee, dans l'ordre, joints par des virgules : une seule
// chaine comparee egalite par egalite, parce que la liste ET son ordre sont le
// meme fait. Un helper du fichier de test, hors de la production.
function idsOf(rows) {
	var s = "";
	for (var i = 0; i < rows.size(); i++) {
		s += rows[i][Levels.RID] + ",";
	}
	return s;
}

// La table L3 est la table L2 sans la rangee Burst ("p3") : la page produit X6
// (14-nov) nomme le meme jeu de modes que la X5, sans Burst. La copie est
// litterale — memes ids, meme ordre — et rien sous L3 ne bouge : les tailles
// de L2 (11) et de L1 (9) sont epinglees parce que la copie ne doit deplacer
// aucune table d'un niveau inferieur. Le domaine des familles est clos : plus
// aucune rangee, a aucun niveau, ne repond la famille sentinelle "x" — la
// ligne placeholder du niveau 3 disparait avec ce change. Et "v0" de L3 garde
// sub=1 : sans lui le sous-menu Resolution ne s'ouvrirait pas sur un X6.
(:test)
function x6TableIsL2MinusBurst(logger) {
	var l2 = Levels.rowsMain(2);
	var l3 = Levels.rowsMain(3);
	var bad = "";
	if (l2.size() != 11) {
		bad += " l2size=" + l2.size().toString() + " want=11";
	}
	if (Levels.rowsMain(1).size() != 9) {
		bad += " l1size=" + Levels.rowsMain(1).size().toString() + " want=9";
	}
	if (l3.size() != l2.size() - 1) {
		bad += " l3size=" + l3.size().toString() + " want=" + (l2.size() - 1).toString();
	}
	// La liste attendue : les ids de L2, "p3" retire, dans l'ordre de L2.
	var want = "";
	for (var i = 0; i < l2.size(); i++) {
		var id = l2[i][Levels.RID];
		if (!id.equals("p3")) {
			want += id + ",";
		}
	}
	var got = idsOf(l3);
	if (!got.equals(want)) {
		bad += " l3ids=[" + got + "] want=[" + want + "]";
	}
	// La famille "x" n'existe plus : aucune rangee d'aucun niveau, dans les
	// deux chaines, ne la nomme. (La garde lit RFAM ; une rangee "x" surviving
	// ailleurs serait une selection sans trame possible.)
	for (var level = 0; level <= 3; level++) {
		var chains = [Levels.rowsMain(level), Levels.rowsRes(level)];
		for (var c = 0; c < 2; c++) {
			var rows = chains[c];
			for (var k = 0; k < rows.size(); k++) {
				if (rows[k][Levels.RFAM].equals("x")) {
					bad += " famX level=" + level.toString() + " chain=" + c.toString() + " id=" + rows[k][Levels.RID];
				}
			}
		}
	}
	// "v0" de L3 ouvre toujours le sous-menu Resolution.
	var v0sub = -1;
	for (var j = 0; j < l3.size(); j++) {
		if (l3[j][Levels.RID].equals("v0")) {
			v0sub = l3[j][Levels.RSUB];
		}
	}
	if (v0sub != 1) {
		bad += " v0sub=" + v0sub.toString() + " want=1";
	}
	logger.debug("l2=" + l2.size().toString() + " l3=" + l3.size().toString() + " v0sub=" + v0sub.toString() + (bad.length() == 0 ? " : L3 = L2 moins p3, aucune famille x" : " :" + bad));
	return bad.length() == 0;
}

// Les six resolutions de L3 sont la copie litterale de L2 : la decision du
// 15 nov. arme le menu X6 avec les numeros herites de la X5, ligne par ligne ;
// aucun numero X6 propre n'entre avant la premiere mesure (un log utilisateur).
// Une taille ou un ordre qui diverge ici serait un numero pose sans mesure.
(:test)
function x6ResTableIsLiteralInheritance(logger) {
	var l2 = Levels.rowsRes(2);
	var l3 = Levels.rowsRes(3);
	var bad = "";
	if (l3.size() != l2.size()) {
		bad += " resL3size=" + l3.size().toString() + " want=" + l2.size().toString();
	} else {
		for (var i = 0; i < l2.size(); i++) {
			if (!l3[i][Levels.RID].equals(l2[i][Levels.RID])) {
				bad += " at=" + i.toString() + " got=" + l3[i][Levels.RID] + " want=" + l2[i][Levels.RID];
			}
		}
	}
	logger.debug("resL2=" + idsOf(l2) + " resL3=" + idsOf(l3) + (bad.length() == 0 ? " : copie litterale" : " :" + bad));
	return bad.length() == 0;
}

// L'aiguillage A1 : ce qui change d'enveloppe et ce qui ne change pas. Seules
// les deux trames mesurees sur un X6 en 2023 (demarrer, arreter) voyagent vers
// la jambe UCD2 ; toute autre trame, une option par exemple, garde la forme
// heritee dans laquelle elle a ete construite — le fait qui porte la decision :
// un X6 repond aux asks de l'ancienne enveloppe par des trames UCD2 du meme
// flux (corpus X6a/X6b, BLEBarrel.mc:3362-3364, PROTOCOL_APK L409-412).
// La seconde moitie du vector epingle le comportement existant a ne pas casser
// (Review Focus 3) : ucd2Send ignore toujours tout declencheur hors start/stop.
// Le vector reste sans appareil : la jambe UCD2 sort a kind==0 (:938-940) avant
// tout transmit. Ne pas epingler txUcd2 : ucd2Send le remet lui-meme a false
// apres un vrai envoi (:948-951), il ne discrimine rien.
(:test)
function ucd2LegNamesOnlyStartStop(logger) {
	// Les questions de la jambe UCD2 vivent dans la classe BleDevice du barillet
	// (comme ucd2Frame/ucd2Send, :900/:928) : le vector les pose a travers un
	// lien propre, comme Ucd2Test le fait deja.
	var d = freshLink();
	var t1 = d.onUcd2Leg(BLEBarrel.cmdStartRec);
	var t2 = d.onUcd2Leg(BLEBarrel.cmdStopRec);
	var f1 = d.onUcd2Leg(BLEBarrel.cmdSet8k30);
	var f2 = d.onUcd2Leg(BLEBarrel.cmdSetPhotoSubBurst);
	var seq0 = BLEBarrel.ucd2SeqNo;
	BLEBarrel.ucd2Armed = true;
	BLEBarrel.ucd2TxKind = -1;
	d.ucd2Send(BLEBarrel.cmdSet8k30);
	var kindKept = BLEBarrel.ucd2TxKind == -1;
	var seqKept = BLEBarrel.ucd2SeqNo == seq0;
	BLEBarrel.ucd2Armed = false;
	BLEBarrel.ucd2TxKind = 0;
	logger.debug("start=" + t1.toString() + " stop=" + t2.toString() + " res=" + f1.toString() + " burst=" + f2.toString() + " armedSendKindKept=" + kindKept.toString() + " seqKept=" + seqKept.toString());
	return t1 && t2 && !f1 && !f2 && kindKept && seqKept;
}

// La selection ne doit jamais eteindre l'armement UCD2 d'un courant dont le
// niveau repond ses propres lignes (X6, niveau 3) : l'armement est du cote du
// modele — la chaine du barillet le pose au lien (:3713), le chemin force a la
// choice (InputDelegate:607). Hors de ce niveau, la remise a zero heritee
// reste : un X5 ou un X3 qui recoit une selection retourne a son envelope.
(:test)
function keepsUcd2OnlyAtX6Level(logger) {
	var k3 = Levels.keepsUcd2AfterSelection(3);
	var k0 = Levels.keepsUcd2AfterSelection(0);
	var k1 = Levels.keepsUcd2AfterSelection(1);
	var k2 = Levels.keepsUcd2AfterSelection(2);
	logger.debug("keep 3=" + k3.toString() + " 0=" + k0.toString() + " 1=" + k1.toString() + " 2=" + k2.toString());
	return k3 && !k0 && !k1 && !k2;
}
