using Levels;
using BLEBarrel;

// La moitiÃ© Â« menu X6 Â» de la suite unitaire : la table du niveau 3 decisee le
// 15 nov. (x6-menu-design.md, decisions B1 + A1). Une table est une donnee,
// pas une fonction : ce que ces vectors pingent est la FORME de la table â€” sa
// taille, ses ids dans l'ordre, ses familles â€” parce que c'est exactement ce
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
// litterale â€” memes ids, meme ordre â€” et rien sous L3 ne bouge : les tailles
// de L2 (11) et de L1 (9) sont epinglees parce que la copie ne doit deplacer
// aucune table d'un niveau inferieur. Le domaine des familles est clos : plus
// aucune rangee, a aucun niveau, ne repond la famille sentinelle "x" â€” la
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
// heritee dans laquelle elle a ete construite â€” le fait qui porte la decision :
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
// modele â€” la chaine du barillet le pose au lien (:3713), le chemin force a la
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

// ---------- Paquet D (x6-menu-design.md, addendum du 15 nov. au soir) ----------
// La regle que les corpus X6a/X6b ont etablie sur l'X6 reel (deposes le 15 nov.) :
// l'X6 ne repond AUCUNE ask legacy, et il acquitte 0x00c8 nos propres trames UCD2
// (execute de plus physiquement - temoin l'utilisateur cooperatif proprietaire).
// Donc sous X6 NOMME au scan (detectedLevel == 3), toute ecriture de l'ancienne
// enveloppe part dans l'enveloppe UCD2, le payload herite tel quel. Le nombre de
// commande du corps est celui que la trame legacy porte deja aux octets 7-8
// (u16 petit-boutiste : 04 00 demarrer, 05 00 arreter, 07 00 modes video,
// 09 00 resolutions), dans le meme ordre d'octets que le corps FILE - ce que
// fait deja ucd2Frame(4) pour le demarrer que la camera a deja acquitte. Sous
// forcage d'un modele de niveau 3, la meme regle vaut : le courant force arme la
// jambe UCD2 comme une liaison reelle (jugement de l'utilisateur du 15 nov. au
// soir, vectors d'au-dessous - le banc avait mesure le melange des deux
// enveloppes et l'avait juge defectueux).
//
// Les octets de rÃ©fÃ©rence ne viennent pas du barillet : ils sont la reponse du
// codec documente tools/insta360_ucd2.py (build_file_command(seq, code, 1, body)),
// genere le 15 nov. au soir pour les deux corps reels ci-dessous - la queue de
// cmdSetVideoSubNormal (code 7) et la queue de cmdSet8k30 (code 9). Le trailer de
// ces trames n'est pas la table ucd2SeqXor (elle n'est juste que pour la longueur
// 25) : c'est le CRC-32 de variante Insta360 (poly 0x04C11DB7, init 0xffffffff,
// sans xor final), que le vector ci-dessous attend calcule sur la trame entiere.

const DREF_SET7 = [
	"55434432010c04011000000007000201000080000008291203c80200d92e5f50",
	"55434432010c04021000000007000201000080000008291203c80200905048ad",
	"55434432010c04031000000007000201000080000008291203c802005785baf9",
	"55434432010c04071000000007000201000080000008291203c80200fccfb0ae",
	"55434432010c04551000000007000201000080000008291203c80200b292dc38",
	"55434432010c04801000000007000201000080000008291203c80200a8786eca",
	"55434432010c04aa1000000007000201000080000008291203c8020046284f7c",
	"55434432010c04fe1000000007000201000080000008291203c802002d94cc14"
];
const DREF_SET9 = [
	"55434432010c0401140000000900020100008000000a011f1204f801a701180791c9989a",
	"55434432010c0402140000000900020100008000000a011f1204f801a70118073c96fe17",
	"55434432010c0403140000000900020100008000000a011f1204f801a7011807ca579c90",
	"55434432010c0407140000000900020100008000000a011f1204f801a70118077c6b9584",
	"55434432010c0455140000000900020100008000000a011f1204f801a701180728d1e79a",
	"55434432010c0480140000000900020100008000000a011f1204f801a7011807c9a55f95",
	"55434432010c04aa140000000900020100008000000a011f1204f801a70118074ea70017",
	"55434432010c04fe140000000900020100008000000a011f1204f801a7011807f7bf7f17"
];

// La porte de l'aiguillage, dans les deux sens : sous X6 nomme au scan, toute
// trame de l'ancienne enveloppe (garde 0x0004 aux octets 4-5) change d'enveloppe ;
// sous forÃ§age d'un modele de niveau 3, la meme famille change d'enveloppe aussi -
// jugement de l'utilisateur du 15 nov. au soir, releve sur le banc (voir les deux
// vectors qui suivent). Les deux ordres de mesure 2023 la changent de toute facon.
// Le vector laisse detectedLevel a sa valeur d'usine a la sortie : les vectors ne
// se passent jamais un etat modifie sans le rendre.
(:test)
function dLegWrapsEveryLegacyFrameUnderDetectedX6(logger) {
	var d = freshLink();
	BLEBarrel.detectedLevel = 3;
	var st = d.onUcd2Leg(BLEBarrel.cmdStartRec);
	var sp = d.onUcd2Leg(BLEBarrel.cmdStopRec);
	var md = d.onUcd2Leg(BLEBarrel.cmdSetVideoSubNormal);
	var rs = d.onUcd2Leg(BLEBarrel.cmdSet8k30);
	BLEBarrel.detectedLevel = 1;
	var fMd = d.onUcd2Leg(BLEBarrel.cmdSetVideoSubNormal);
	var fRs = d.onUcd2Leg(BLEBarrel.cmdSet8k30);
	var stillSt = d.onUcd2Leg(BLEBarrel.cmdStartRec);
	logger.debug("detectedX6 start=" + st.toString() + " stop=" + sp.toString() + " mode=" + md.toString() + " res=" + rs.toString() + " forced mode=" + fMd.toString() + " res=" + fRs.toString() + " startKept=" + stillSt.toString());
	return st && sp && md && rs && !fMd && !fRs && stillSt;
}

// Le fait qui a fait changer la regle (15 nov. au soir, scene simulateur sur le
// modele de montre de l'utilisateur cooperatif, journal simrun-910-fenix847mm.txt) :
// sous forÃ§age X6 devant la X5 du bureau, QUATRE trames UCD2 sont parties (op 4,
// une par appui demarrer) et ZERO n'a recu de reponse, pendant que les ecritures de
// mode partaient en brut et que l'X6 y reagissait visiblement. Un courant qui parle
// deux enveloppes a la fois n'est pas un protocole, c'en est la moitie : le forÃ§age
// d'un modele de niveau 3 arme l'enveloppe UCD2 comme l'arme une liaison reelle de
// ce modele. Le datum du forÃ§age (testModel/testLevel) reste distinct de celui de la
// detection (detectedLevel) - les deux sont rendus l'un apres l'autre ici, et un
// forÃ§age d'un modele de l'ancienne enveloppe (X5, niveau 2) n'ouvre rien.
(:test)
function dForcedLevel3WrapsTheWholeLegacyFamily(logger) {
	var d = freshLink();
	BLEBarrel.detectedLevel = 2;
	BLEBarrel.testModel = "X6";
	BLEBarrel.testLevel = 3;
	var md = d.onUcd2Leg(BLEBarrel.cmdSetVideoSubNormal);
	var rs = d.onUcd2Leg(BLEBarrel.cmdSet8k30);
	var st = d.onUcd2Leg(BLEBarrel.cmdStartRec);
	// Le forÃ§age retire : la porte se referme avec lui, elle ne reste pas ouverte
	// par habitude d'un run precedent.
	BLEBarrel.testModel = "";
	BLEBarrel.testLevel = -1;
	var offMd = d.onUcd2Leg(BLEBarrel.cmdSetVideoSubNormal);
	var offRs = d.onUcd2Leg(BLEBarrel.cmdSet8k30);
	var offSt = d.onUcd2Leg(BLEBarrel.cmdStartRec);
	// Un forÃ§age d'un modele de l'ancienne enveloppe n'ouvre pas la jambe neuve.
	BLEBarrel.testModel = "X5";
	BLEBarrel.testLevel = 2;
	var x5Md = d.onUcd2Leg(BLEBarrel.cmdSetVideoSubNormal);
	BLEBarrel.testModel = "";
	BLEBarrel.testLevel = -1;
	BLEBarrel.detectedLevel = 1;
	logger.debug("forcedX6 mode=" + md.toString() + " res=" + rs.toString() + " start=" + st.toString() + " | off mode=" + offMd.toString() + " res=" + offRs.toString() + " startKept=" + offSt.toString() + " | forcedX5 mode=" + x5Md.toString());
	return md && rs && st && !offMd && !offRs && offSt && !x5Md;
}

// L'autre moitie du meme jugement, a l'endroit ou le courant se casse aujourd'hui :
// l'aiguillage de sendCMD ouvrirait la jambe UCD2 sous forÃ§age de niveau 3, mais
// ucd2Send a sa propre garde, qui lit detectedLevel (:969) et rendrait kind==0 -
// la trame disparaitrait sans jamais partir sur l'air, sans une ligne pour repondre
// de ce rejet (critere 14). L'expediteur donc suit la meme donnee que l'aiguillage :
// sous forÃ§age de niveau 3 l'ecriture d'option est prise comme option; hors de ce
// forÃ§age elle est rejetee comme le pingle deja ucd2LegNamesOnlyStartStop.
// (dev null dans ce vector : transmit repond par sa branche d'absence d'appareil.)
(:test)
function dForcedLevel3OptionWriteIsNotDroppedByTheSender(logger) {
	var d = cleanUcd2Link();
	BLEBarrel.ucd2Armed = true;
	BLEBarrel.detectedLevel = 2;
	BLEBarrel.testModel = "X6";
	BLEBarrel.testLevel = 3;
	BLEBarrel.ucd2TxKind = -1;
	d.ucd2Send(BLEBarrel.cmdSetVideoSubNormal);
	var asked = BLEBarrel.ucd2TxKind == BLEBarrel.retryKindOption;
	BLEBarrel.testModel = "";
	BLEBarrel.testLevel = -1;
	BLEBarrel.ucd2TxKind = -1;
	d.ucd2Send(BLEBarrel.cmdSetVideoSubNormal);
	var dropped = BLEBarrel.ucd2TxKind == -1;
	BLEBarrel.ucd2Armed = false;
	BLEBarrel.detectedLevel = 1;
	BLEBarrel.ucd2TxKind = 0;
	logger.debug("forcedX6 askedAsOption=" + asked.toString() + " | forcingOff dropped=" + dropped.toString());
	return asked && dropped;
}

// L'ask de statut dans la meme regle (jugement de l'utilisateur du 15 nov. au soir,
// apres la rectification D4 : un courant qui parle l'UCD2 ne laisse AUCUNE trame de
// l'ancienne enveloppe sur l'air). La demande d'etat 15 est un corps vide de l'ancienne
// enveloppe (cmdApply, 16 octets, nombre de commande 0f 00 aux octets 7-8) : sous un
// courant UCD2 - camera nommee X6 au scan, ou forÃ§age d'un modele de ce niveau - elle
// change d'enveloppe comme le reste. Sans ces deux donnees elle reste brute : c'est le
// chemin prouve au poignet le 15 nov. Un forÃ§age d'un modele de l'ancienne enveloppe
// (X5, niveau 2) ne l'ouvre pas.
(:test)
function dStatusAskChangesEnvelopeWithTheRun(logger) {
	var d = freshLink();
	BLEBarrel.detectedLevel = 2;
	var raw = d.onUcd2Leg(BLEBarrel.cmdApply);
	BLEBarrel.testModel = "X5";
	BLEBarrel.testLevel = 2;
	var rawX5Forced = d.onUcd2Leg(BLEBarrel.cmdApply);
	BLEBarrel.testModel = "X6";
	BLEBarrel.testLevel = 3;
	var forced = d.onUcd2Leg(BLEBarrel.cmdApply);
	BLEBarrel.testModel = "";
	BLEBarrel.testLevel = -1;
	BLEBarrel.detectedLevel = 3;
	var named = d.onUcd2Leg(BLEBarrel.cmdApply);
	BLEBarrel.detectedLevel = 1;
	logger.debug("plain=" + raw.toString() + " forcedX5=" + rawX5Forced.toString() + " forcedX6=" + forced.toString() + " namedX6=" + named.toString());
	return !raw && !rawX5Forced && forced && named;
}

// Les octets de cette ask encapsulee, contre le codec documente : corps FILE de
// longueur declaree 9 (le corps vide), code 0f 00 repris de la trame legacy, marqueur
// 02, request-id 1, bloc 00 00 80 00, trailer CRC-32 sur la trame entiere - soit 25
// octets, la longueur exacte des deux ordres deja acquittes par la camera. Reference
// generee le 15 nov. au soir par tools/insta360_ucd2.py :
//   build_file_command(seq, 15, 1, b"")
const DREF_ASK15 = [
	"55434432010c0401090000000f0002010000800000ce20348a",
	"55434432010c0402090000000f000201000080000063aff527",
	"55434432010c0403090000000f0002010000800000f8d54a43",
	"55434432010c0407090000000f0002010000800000232276d5",
	"55434432010c0455090000000f0002010000800000a8be7f0c",
	"55434432010c0480090000000f00020100008000002b41866c",
	"55434432010c04aa090000000f0002010000800000188ea32f",
	"55434432010c04fe090000000f00020100008000007e10e8a9"
];

// La fabrique d'un corps vide : cmdApply n'a rien au-dela de l'en-tete de 16 octets,
// donc le payload herite est vide et la trame fait la longueur des deux ordres mesures.
// Le vector ne se contente pas d'une longueur : il compare les octets des huit sequences
// (le trailer n'est pas la table ucd2SeqXor, seulement juste a 25 - un CRC sur la trame
// entiere se sait par la reponse du codec).
(:test)
function dAsk15FrameMatchesTheReferenceCodec(logger) {
	var d = cleanUcd2Link();
	var bad = "";
	for (var i = 0; i < U2SEQS.size(); i++) {
		var seq = U2SEQS[i];
		BLEBarrel.ucd2SeqNo = seq - 1;
		var f = d.ucd2FrameOption(BLEBarrel.cmdApply);
		if (f.size() != 25) {
			bad += " ask15 seq=" + seq.toString() + " len=" + f.size().toString() + " want=25";
		}
		var got = u2hex(f);
		if (!got.equals(DREF_ASK15[i])) {
			bad += " ask15 seq=" + seq.toString() + " got=" + got + " want=" + DREF_ASK15[i];
		}
	}
	logger.debug("frames=" + U2SEQS.size().toString() + " (25)" + (bad.length() == 0 ? " all match the codec" : bad));
	return bad.length() == 0;
}

// L'ask encapsulee n'appartient pas au retry d'ecriture : la demande d'etat possede DEJA
// son propre retry borne (x5StatusDue, x5StatusTries, STATUS_RETRY_MAX - le meme que le
// chemin brut). L'armer deux fois sur une seule trame est exactement le orage de retries
// que l'accompagnement du 15 nov. a supprime. L'expediteur donc marque la trame comme
// une ask, et ce marqueur ne s'etend pas a l'ecriture d'option voisine - sans quoi un
// start perdrait son retry par heredite d'une ask precedente.
(:test)
function dAskOnTheUcd2LegIsNotOwnedByTheWriteRetry(logger) {
	var d = cleanUcd2Link();
	BLEBarrel.ucd2Armed = true;
	BLEBarrel.detectedLevel = 2;
	BLEBarrel.testModel = "X6";
	BLEBarrel.testLevel = 3;
	d.ucd2Send(BLEBarrel.cmdApply);
	var askMarked = BLEBarrel.ucd2TxAsk;
	var askAsOption = BLEBarrel.ucd2TxKind == BLEBarrel.retryKindOption;
	d.ucd2Send(BLEBarrel.cmdSetVideoSubNormal);
	var writeMarked = BLEBarrel.ucd2TxAsk;
	BLEBarrel.testModel = "";
	BLEBarrel.testLevel = -1;
	BLEBarrel.ucd2Armed = false;
	BLEBarrel.detectedLevel = 1;
	BLEBarrel.ucd2TxKind = 0;
	logger.debug("ask framedAsOption=" + askAsOption.toString() + " askMarked=" + askMarked.toString() + " optionWriteMarked=" + writeMarked.toString());
	return askAsOption && askMarked && !writeMarked;
}

// La fabrique : le corps FILE porte le nombre de commande que la trame legacy
// porte aux octets 6-7, puis le marqueur, le request-id et le bloc de flags
// comme ucd2Frame(), puis la queue legacy recopiee telle quelle (le payload est
// herite - c'est la rege de l'utilisateur, l'enveloppe seule change). La
// longueur declaree est 9 + payload, et le trailer est le CRC calcule sur la
// trame entiere - la table ucd2SeqXor ne vaut que pour la longueur 25, elle ne
// peut pas servir ici. Les sequences sont celles de U2SEQS, le compteur est
// pose par la fabrique elle-meme (transmit ne doit plus y toucher : le trailer
// d'un seq reprise apres le CRC ne serait plus le bon).
(:test)
function dOptionFramesMatchTheReferenceCodec(logger) {
	var d = cleanUcd2Link();
	var bad = "";
	for (var i = 0; i < U2SEQS.size(); i++) {
		var seq = U2SEQS[i];
		BLEBarrel.ucd2SeqNo = seq - 1;
		var f7 = d.ucd2FrameOption(BLEBarrel.cmdSetVideoSubNormal);
		if (f7.size() != 32) {
			bad += " set7 seq=" + seq.toString() + " len=" + f7.size().toString() + " want=32";
		}
		var got7 = u2hex(f7);
		if (!got7.equals(DREF_SET7[i])) {
			bad += " set7 seq=" + seq.toString() + " got=" + got7 + " want=" + DREF_SET7[i];
		}
		BLEBarrel.ucd2SeqNo = seq - 1;
		var f9 = d.ucd2FrameOption(BLEBarrel.cmdSet8k30);
		if (f9.size() != 36) {
			bad += " set9 seq=" + seq.toString() + " len=" + f9.size().toString() + " want=36";
		}
		var got9 = u2hex(f9);
		if (!got9.equals(DREF_SET9[i])) {
			bad += " set9 seq=" + seq.toString() + " got=" + got9 + " want=" + DREF_SET9[i];
		}
	}
	logger.debug("frames=" + U2SEQS.size().toString() + "x2 (32,36)" + (bad.length() == 0 ? " all match the codec" : bad));
	return bad.length() == 0;
}

// L'accompagnement demande par l'utilisateur (15 nov.) : un X6 nomme au scan ne
// repond AUCUNE ask legacy (les deux corpus, zero trame legacy en RX). La demande
// d'etat 15 est la seule ask que le courant emettait encore sous X6 detecte (les
// asks auth et carte ont deja leur garde ucd2Armed) : ici elle est refusee, et le
// refus repond par la donnee marquee + la ligne, jamais par une absence (critere
// 14). La donnee marquee est de portee du lien : le bond suivant la remet a faux
// (:1922, :3806), une autre camera redemande pour elle-meme. Le courant FORCE
// n'est pas un X6 nomme : il demande encore, et depuis le jugement du 15 nov. au
// soir il demande dans l'enveloppe que le courant parle (le vector d'au-dessus).
// sortante (un Device ne se construit pas en unitaire) ; il epingle que la marque
// du refus vient de la regle X6 nomme, et qu'aucun timer n'est arme.
(:test)
function dStatusAskRefusedUnderNamedX6(logger) {
	var d = freshLink();
	BLEBarrel.detectedLevel = 3;
	d.askCamStatus();
	var marked = BLEBarrel.x5StatusAsked;
	var noTimer = BLEBarrel.x5StatusDue == null;
	var triesKept = BLEBarrel.x5StatusTries == 0;
	// Le meme appel, detection d'une X5 : la regle ne marque rien (et l'appareil
	// absent termine la course comme avant) - la marque vient bien du nom X6.
	var e = freshLink();
	BLEBarrel.detectedLevel = 1;
	e.askCamStatus();
	var untouched = !BLEBarrel.x5StatusAsked && BLEBarrel.x5StatusDue == null;
	BLEBarrel.x5StatusAsked = false;
	BLEBarrel.x5StatusDue = null;
	BLEBarrel.x5StatusTries = 0;
	logger.debug("namedX6 marked=" + marked.toString() + " noTimer=" + noTimer.toString() + " triesKept=" + triesKept.toString() + " x5detection untouched=" + untouched.toString());
	return marked && noTimer && triesKept && untouched;
}

// Ce que la reponse a une ecriture d'option peut et doit faire : fermer son
// retry (le 0x00c8 est l'acquit d'acceptation, le meme que start/stop), et ne
// RIEN deplacer dans la machine d'enregistrement. Le cas de risque est nomme :
// une reponse d'option qui croise un start encore en attente ne doit pas le
// declarer Shooting. Le pendant est epingle dans la foulÃ©e : remise en jambe
// start, la meme trame c8 deplace bien l'etat - la garde ne s'etend pas.
// (dev null dans ce vector : transmit repond par sa branche d'absence d'appareil
// et le retry n'est pas arme - c'est le comportement de la jambe heritee, pas de
// l'option ; ce qui est demande ici est l'aiguillage et la garde.)
(:test)
function dOptionAnswerClosesItsRetryAndMovesNothing(logger) {
	var d = cleanUcd2Link();
	BLEBarrel.ucd2Armed = true;
	BLEBarrel.detectedLevel = 3;
	d.ucd2Send(BLEBarrel.cmdSetVideoSubNormal);
	var asked = BLEBarrel.ucd2TxKind == BLEBarrel.retryKindOption;
	BLEBarrel.recState = BLEBarrel.stateStarting;
	BLEBarrel.mMessage = "Starting";
	d.onCharacteristicChanged(null, u2f(9, BLEBarrel.ucd2TypeFile, 0x42, 0xc8, 0x00, u2fileBody()));
	var kept = BLEBarrel.recState == BLEBarrel.stateStarting && BLEBarrel.mMessage.equals("Starting");
	BLEBarrel.recState = BLEBarrel.stateStarting;
	BLEBarrel.mMessage = "Starting";
	BLEBarrel.ucd2TxKind = BLEBarrel.retryKindStart;
	d.onCharacteristicChanged(null, u2f(9, BLEBarrel.ucd2TypeFile, 0x43, 0xc8, 0x00, u2fileBody()));
	var moves = BLEBarrel.recState == BLEBarrel.stateStartRec;
	BLEBarrel.ucd2Armed = false;
	BLEBarrel.detectedLevel = 1;
	BLEBarrel.ucd2TxKind = 0;
	logger.debug("askedAsOption=" + asked.toString() + " answerKeptState=" + kept.toString() + " startAnswerStillMoves=" + moves.toString());
	return asked && kept && moves;
}

// Le datum du forçage effacé doit dire « pas de forçage », entièrement. La revue
// nommée du 15 nov. a trouvé le site du « Force model » du menu principal (celui
// que l'utilisateur atteint) posant testModel au modèle détecté pour le choix
// « off » : hookForced() restait vrai sur un courant ordinaire, le plafond de
// l'axe comptait ses écritures, et passé le plafond TOUTES les écritures de la
// caméra possédée étaient refusées avec « [hook] refused ». Le datum est nommé
// une fois (BleDevice.clearForcing, BLEBarrel :3190) ; ce vector épingle la
// donnée, le
// chemin du menu la présente par un appel.
(:test)
function eClearForcingEndsTheCeilingDatum(logger) {
	var d = freshLink();
	BLEBarrel.testModel = "X6";
	BLEBarrel.testLevel = 3;
	var forcedBefore = d.hookForced();
	var counted = !d.hookCeiling() && BLEBarrel.hookSent == 1;
	d.clearForcing();
	var forcedAfter = d.hookForced();
	var ceilingQuiet = !d.hookCeiling() && !d.hookForced() && BLEBarrel.hookSent == 0;
	logger.debug("forcedBefore=" + forcedBefore.toString() + " counted=" + counted.toString() + " forcedAfter=" + forcedAfter.toString() + " ceilingQuiet=" + ceilingQuiet.toString());
	return forcedBefore && counted && !forcedAfter && ceilingQuiet;
}

// Le pendant de dOptionAnswerClosesItsRetryAndMovesNothing, côté retry : la
// réponse 0x00c8 à une écriture d'option fermait TOUT retry armé, y compris
// celui d'un départ en vol - l'anneau restait « Démarrage… » sans rien d'armé
// ni de ligne pour répondre du refus (critère 14 ; le risque du corpus X6b est
// nommé par le code). Ce qui croise ferme le retry DE L'ÉCRITURE QUI A CROISÉ
// (ucd2TxKind), jamais un autre. Le vector arme un retry de départ, fait
// croiser une acquit d'option, et exige que le départ reste armé.
(:test)
function eOptionAnswerKeepsAnotherWritesRetryArmed(logger) {
	var d = freshLink();
	BLEBarrel.detectedLevel = 3;
	BLEBarrel.ucd2Armed = true;
	BLEBarrel.recState = BLEBarrel.stateStarting;
	d.scheduleRetry(BLEBarrel.retryKindStart);
	var armed = d.retryKind == BLEBarrel.retryKindStart && d.retryDue != null;
	BLEBarrel.ucd2TxKind = BLEBarrel.retryKindOption;
	d.onUcd2Frame();
	var keptArmed = d.retryKind == BLEBarrel.retryKindStart && d.retryDue != null;
	// Le pendant exact : quand l'acquit fermé est bien celui de l'option, son
	// retry se ferme - la garde ne s'étend pas à son propre type. Le second
	// appel nomme ucd2TxKind au départ (plus à l'option) pour que l'aiguillage
	// prenne la route où le retry armé se ferme.
	d.scheduleRetry(BLEBarrel.retryKindOption);
	BLEBarrel.ucd2TxKind = BLEBarrel.retryKindStart;
	d.onUcd2Frame();
	var ownClosed = d.retryKind == 0 && d.retryDue == null;
	d.retryDue = null;
	d.retryKind = 0;
	BLEBarrel.ucd2TxKind = 0;
	BLEBarrel.ucd2Armed = false;
	BLEBarrel.detectedLevel = 1;
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	logger.debug("armed=" + armed.toString() + " optionAnswerKeptStartRetry=" + keptArmed.toString() + " ownOptionRetryClosed=" + ownClosed.toString());
	return armed && keptArmed && ownClosed;
}

// La combinaison que la revue a demandée de nommer : une liaison que le scan a
// NOMMÉE X6, forcée vers un modèle de l'ancienne enveloppe. La refus de la ask
// 15 répond de ce que la caméra EST (le nom lu au scan), jamais de ce que le
// banc prétend : la ask legs n'a aucune réponse sur cette liaison sous aucun
// modèle en force. Le pendant reste prouvé ailleurs : un courant forcé vers le
// niveau 3 sur une liaison qui ne nomme pas X6 demande, dans l'enveloppe qu'il
// parle (dStatusAskChangesEnvelopeWithTheRun). Ici la marque tombe, aucun timer
// n'est armé, et le compteur d'essais de la ask ne bouge pas.
(:test)
function eForcedDownOnNamedX6StillRefusesTheAsk(logger) {
	var d = freshLink();
	BLEBarrel.detectedLevel = 3;
	BLEBarrel.testModel = "X5";
	BLEBarrel.testLevel = 2;
	d.askCamStatus();
	var marked = BLEBarrel.x5StatusAsked;
	var noTimer = BLEBarrel.x5StatusDue == null;
	var triesKept = BLEBarrel.x5StatusTries == 0;
	BLEBarrel.testModel = "";
	BLEBarrel.testLevel = -1;
	BLEBarrel.x5StatusAsked = false;
	BLEBarrel.x5StatusTries = 0;
	logger.debug("namedX6 forcedDown marked=" + marked.toString() + " noTimer=" + noTimer.toString() + " triesKept=" + triesKept.toString());
	return marked && noTimer && triesKept;
}
