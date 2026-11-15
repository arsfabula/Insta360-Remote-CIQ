using Levels;

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
