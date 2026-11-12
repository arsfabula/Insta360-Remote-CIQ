using Toybox.Test;
using Toybox.System;
using Toybox.Time;
using Toybox.Application;
using Toybox.BluetoothLowEnergy;
using BLEBarrel;

// The UCD2 envelope half of the unit suite: the envelope an X6, a Luna Ultra or a
// Luna Pro speaks (PROTOCOL_APK section 9, the "ucd2": true cameras of
// assets/ins_config_files/phoneApp/<dir>/basic/business.json). No such camera has
// ever sat on this bench - the X5 fw 1.13.21 is the only one there - so nothing
// here is a recording of our own wire. The authority is named per vector and it
// is always a documented one:
//   * the layout, the request shape and the trailer: tools/insta360_ucd2.py, the
//     codec ported from Ripwords/insta360-luna-ultra-desktop (itself ported from
//     diamondfsd/luna-ai-cut) and checked against bytes a real camera sent;
//   * the framing verdicts of the two watch corpora over an X6 (OneRremote
//     X6a.TXT, X6b.TXT, 363 RX notifications) as they are written in
//     PROTOCOL_APK 15 (the L397-412 block): every notification is 20 octets, a
//     pushed UCD2 frame declares want=25 and only 20 arrive, the next
//     notification is a new head (68 of them, no continuation anywhere), a
//     headless continuation does exist elsewhere (verdict C), and a legacy ask
//     can be answered in UCD2 in the same stream.
// The two questions that stay open for want of a camera on the bench are written
// at the end of this file, not asserted here.

// The reference bytes, as tools/insta360_ucd2.py builds them:
// build_file_command(seq, code, request_id=1) - a FILE frame whose body is the
// fixed nine (code:u16 | 0x02 | request_id:u16 | 0x8000:u32) with the CRC-32
// variant of Insta360 as its trailer. Generated on 12 nov. 2026 with the tool in
// this repository, python -c "import insta360_ucd2 as u; ...", for the sequences
// below. They are the answer of the codec, not of this barrel.
const U2REF_START = [
	"55434432010c040109000000040002010000800000c037f43e",
	"55434432010c0402090000000400020100008000006db83593",
	"55434432010c040309000000040002010000800000f6c28af7",
	"55434432010c0407090000000400020100008000002d35b661",
	"55434432010c045509000000040002010000800000a6a9bfb8",
	"55434432010c048009000000040002010000800000255646d8",
	"55434432010c04aa090000000400020100008000001699639b",
	"55434432010c04fe090000000400020100008000007007281d"
];
const U2REF_STOP = [
	"55434432010c040109000000050002010000800000de80b495",
	"55434432010c040209000000050002010000800000730f7538",
	"55434432010c040309000000050002010000800000e875ca5c",
	"55434432010c0407090000000500020100008000003382f6ca",
	"55434432010c045509000000050002010000800000b81eff13",
	"55434432010c0480090000000500020100008000003be10673",
	"55434432010c04aa09000000050002010000800000082e2330",
	"55434432010c04fe090000000500020100008000006eb068b6"
];
// The sequences the reference above answers for. ucd2Frame() stamps 1 itself and
// transmit() re-stamps with ucd2SeqNo, which runs 1..254 (transmit resets at
// 254), so 254 is the top of the range. The set walks the bit patterns of the
// sequence byte - one bit, two adjacent bits, three, an alternating byte, the
// top bit alone and the top bit plus all but one - which is what the 32 entries
// of ucd2SeqXor are for.
const U2SEQS = [1, 2, 3, 7, 0x55, 0x80, 0xaa, 254]b;

// A witness of this file's own, so the comparison below does not lean on the
// barrel's printer (the printer another vector pins). The helpers of the test
// module carry no type annotations, like StatusTest.mc's - the test module does
// not resolve Lang types.
function u2hex(b) {
	var dg = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"];
	var s = "";
	for (var i = 0; i < b.size(); i++) {
		var v = b[i] & 0xff;
		s += dg[(v >> 4) & 0x0f] + dg[v & 0x0f];
	}
	return s;
}

// A UCD2 frame as the envelope says it (all little endian): the magic, version
// 0x01, flags 0x0c, the frame type, the sequence, the four body-length octets,
// the body, and four trailer octets. declared is the BODY length - the whole
// frame is 16 + declared, which is the same arithmetic tools/insta360_ucd2.py
// states as frame_length() and the same the barrel computes as 16 + declared.
// The trailer octets are zeros except where a vector needs the real CRC; for the
// frames the barrel only reads the first 20 octets of, the trailer never arrives
// at all (that is the documented verdict B TRONCATURE-UNIQUE) and no code here
// checks it.
function u2f(declared, typeByte, seq, codeLo, codeHi, body) {
	var f = [0x55, 0x43, 0x44, 0x32, 0x01, 0x0c, typeByte, seq & 0xff,
		declared & 0xff, (declared >> 8) & 0xff, 0, 0]b;
	f.add(codeLo);
	f.add(codeHi);
	f.addAll(body);
	f.addAll([0, 0, 0, 0]b);
	return f;
}

// The rest of the nine octets a FILE body opens with, the code left to u2f():
// the 0x02 marker, the request id little-endian, and the 0x8000 flags. The
// request id is the one the barrel sends, ucd2ReqId = 1. With the code the body
// is the fixed nine the codec states: code:u16 | 0x02 | request_id:u16 |
// 0x8000:u32.
function u2fileBody() {
	return [0x02, BLEBarrel.ucd2ReqId & 0xff, (BLEBarrel.ucd2ReqId >> 8) & 0xff,
		0x00, 0x80, 0x00, 0x00]b;
}

function cleanUcd2Link() {
	var d = freshLink();
	BLEBarrel.ucd2Armed = false;
	BLEBarrel.ucd2SeqNo = 1;
	BLEBarrel.ucd2TxKind = 0;
	BLEBarrel.ucd2RxBuf = null;
	BLEBarrel.ucd2RxWant = 0;
	return d;
}

// The bytes this watch puts on air for an X6, against the bytes the reference
// codec puts on air for the same order. ucd2Frame() builds the frame by hand and
// the trailer does not come from a CRC - it comes from three constants:
// ucd2TrailStartBase / ucd2TrailStopBase (the trailer of the frame with the
// sequence at zero) xored, bit by bit of the sequence, through the 32 entries of
// ucd2SeqXor (that is how tools/gen_trailer_table.py derives them, and it is
// only legal because a CRC is linear over XOR). So this vector does not test a
// layout twice written from the same reading - it tests the table: a wrong entry
// is wrong at one sequence and right at the next, and the set of sequences above
// touches every entry.
(:test)
function ucd2TxFramesMatchTheReferenceCodec(logger) {
	var d = cleanUcd2Link();
	var bad = "";
	for (var i = 0; i < U2SEQS.size(); i++) {
		var seq = U2SEQS[i];
		var st = d.ucd2Frame(BLEBarrel.ucd2OpStart);
		if (seq != 1) {
			d.ucd2StampSeq(st, seq);
		}
		var sp = d.ucd2Frame(BLEBarrel.ucd2OpStop);
		if (seq != 1) {
			d.ucd2StampSeq(sp, seq);
		}
		var gotStart = u2hex(st);
		var gotStop = u2hex(sp);
		if (!gotStart.equals(U2REF_START[i])) {
			bad += " start seq=" + seq.toString() + " got=" + gotStart + " want=" + U2REF_START[i];
		}
		if (!gotStop.equals(U2REF_STOP[i])) {
			bad += " stop seq=" + seq.toString() + " got=" + gotStop + " want=" + U2REF_STOP[i];
		}
	}
	logger.debug("frames=" + U2SEQS.size().toString() + "x2 len=" + d.ucd2Frame(BLEBarrel.ucd2OpStart).size().toString() + (bad.length() == 0 ? " all match the codec" : bad));
	return bad.length() == 0;
}

// The shape the framing section names B TRONCATURE-UNIQUE: the answer to this
// watch's order declares 25 octets, and the link carries 20 at most. The rule
// the corpora force on the engine (PROTOCOL_APK L407-408, and consequence 1 of
// the same measurement at L566-569) is to answer at the frame boundary and not
// at want - a strict want gate would drop every answer the product handles. The
// answer of the UCD2 leg must therefore be the first 20 octets: the code at the
// head of the body, the marker, and the request id are all inside those 20, so
// the order is closed without waiting for a trailer that never arrives. The
// second chunk must then answer for nothing: the frame it completes belongs to a
// decision already taken.
(:test)
function ucd2AnswerReadAtTheFirstTwentyNotAtTheTrailer(logger) {
	var d = cleanUcd2Link();
	BLEBarrel.ucd2Armed = true;
	BLEBarrel.recState = BLEBarrel.stateStarting;
	BLEBarrel.mMessage = "Starting";
	var whole = u2f(9, BLEBarrel.ucd2TypeFile, 7, 0xc8, 0x00, u2fileBody());
	var head = whole.slice(0, 20);
	var tail = whole.slice(20, whole.size());
	d.onCharacteristicChanged(null, head);
	var after20 = BLEBarrel.recState == BLEBarrel.stateStartRec;
	var msg = BLEBarrel.mMessage;
	var cleared = BLEBarrel.ucd2RxBuf == null;
	d.onCharacteristicChanged(null, tail);
	var once = BLEBarrel.recState == BLEBarrel.stateStartRec;
	logger.debug("afterHead20 rec=" + BLEBarrel.recState.toString() + " msg=" + show(msg) + " bufCleared=" + cleared.toString() + " tailHead=" + tail.size().toString() + " afterTail rec=" + BLEBarrel.recState.toString());
	return after20 && cleared && once && !msg.equals("Starting");
}

// Two safety rules the same section states for the stream (L402-404 for the
// first, L417-420 for the second, both measured over the X6 corpora): 68 pushed
// frames declare 25 and receive 20 with a NEW head as the next notification and
// no continuation anywhere - so an open frame must yield its place to a new head
// instead of being stacked under it; and a frame whose declared length is beyond
// the bound is abandoned, its headless fragments dropped and not stacked. In
// both cases the engine must still answer the next thing that is addressed to
// it: an abandoned frame may not wedge the link.
(:test)
function ucd2OpenFrameYieldsAndOversizedDeclaredNeverWedges(logger) {
	var d = cleanUcd2Link();
	BLEBarrel.ucd2Armed = true;
	// A push with a body the link will never finish: declared 40, so want 56.
	var push = u2f(40, BLEBarrel.ucd2TypeFile, 0x11, 0x17, 0x20, u2fileBody());
	var pushHead = push.slice(0, 20);
	d.onCharacteristicChanged(null, pushHead);
	var opened = BLEBarrel.ucd2RxBuf != null && BLEBarrel.ucd2RxBuf.size() == 20;
	// The next notification is another head (the corpus: seq +1, no tail).
	var next = u2f(40, BLEBarrel.ucd2TypeFile, 0x12, 0x40, 0x20, u2fileBody());
	d.onCharacteristicChanged(null, next.slice(0, 20));
	var buf = BLEBarrel.ucd2RxBuf;
	var replaced = buf != null && buf.size() == 20 && (buf[7] & 0xff) == 0x12 && (buf[12] & 0xff) == 0x40;
	// A declared length above the bound of the reassembly: dropped, and the
	// headless fragment that follows is dropped too, never stacked.
	var huge = u2f(600, BLEBarrel.ucd2TypeFile, 0x13, 0x17, 0x20, u2fileBody());
	d.onCharacteristicChanged(null, huge.slice(0, 20));
	d.onCharacteristicChanged(null, [0x5f, 0x32, 0x2e, 0x30, 0x36]b);
	var dropped = BLEBarrel.ucd2RxBuf == null;
	// The link still answers what is addressed to it.
	BLEBarrel.recState = BLEBarrel.stateStarting;
	d.onCharacteristicChanged(null, u2f(9, BLEBarrel.ucd2TypeFile, 0x14, 0xc8, 0x00, u2fileBody()).slice(0, 20));
	var alive = BLEBarrel.recState == BLEBarrel.stateStartRec;
	logger.debug("opened=" + opened.toString() + " yieldedToNextHead=" + replaced.toString() + " oversizedDropped=" + dropped.toString() + " stillAnswers=" + alive.toString());
	return opened && replaced && dropped && alive;
}

// One stream, two envelopes - the requirement the X6 corpora state outright
// (L409-412: "a legacy ask is answered in UCD2 ... the RX engine must recognize
// both envelopes in one stream, not one per connection"). The direction the
// product can be in today is the arm of the envelope by the level in force
// (menuLevel 3 arms the UCD2 leg, the relink site), so both directions are
// named here: with the UCD2 leg armed, a frame of the legacy envelope - the mode
// echo the X5 answers with - is still read by the one legacy reader; and in a
// session that never armed the UCD2 leg, a UCD2 head is neither read as legacy
// nor stacked - the 16-octet envelope the legacy reader looks for is not in it,
// and the reassembly of the next legacy frame is untouched.
(:test)
function ucd2LegacyAnswerReadWhileUcd2Armed(logger) {
	var d = cleanUcd2Link();
	BLEBarrel.ucd2Armed = true;
	d.onCharacteristicChanged(null, frame(22, 0x53, 0x20, 0xff, [0x08, 0x64, 0x10, 0x02]b));
	var through = d.peekCamMode();
	// The other direction: this session never armed the UCD2 leg, and a UCD2
	// head of 20 octets crosses it. The legacy reader's envelope is not in that
	// frame (the legacy header reads 04 00 00 at 4..6, a UCD2 head carries
	// 01 0c 04 there), so nothing may be stacked for it.
	var e = cleanUcd2Link();
	e.onCharacteristicChanged(null, u2f(9, BLEBarrel.ucd2TypeFile, 0x23, 0x08, 0x00, u2fileBody()).slice(0, 20));
	var notStacked = BLEBarrel.x5RxBuf == null;
	e.onCharacteristicChanged(null, frame(22, 0x53, 0x20, 0xff, [0x08, 0x64, 0x10, 0x02]b));
	var after = e.peekCamMode();
	logger.debug("legacyThroughUcd2=" + show(through) + " ucd2NotStackedInLegacy=" + notStacked.toString() + " legacyAfterUcd2=" + show(after));
	return through != null && through.equals("v2") && notStacked && after != null && after.equals("v2");
}

// The same requirement, at the one moment it is not met today: an answer of the
// legacy envelope that arrives while a UCD2 frame is still open. The X6 corpus
// is what makes this reachable - a pushed UCD2 frame declares 25, receives 20,
// and stays open in the reassembly; if the camera then answers something this
// watch asked in the old envelope, that answer is what decides a recording, a
// mode, a card. Dropping it costs a decision, not a byte.
(:test)
function ucd2OpenFrameDoesNotSwallowALegacyAnswer(logger) {
	var d = cleanUcd2Link();
	BLEBarrel.ucd2Armed = true;
	var push = u2f(40, BLEBarrel.ucd2TypeFile, 0x31, 0x17, 0x20, u2fileBody());
	d.onCharacteristicChanged(null, push.slice(0, 20));
	var open = BLEBarrel.ucd2RxBuf != null;
	d.onCharacteristicChanged(null, frame(22, 0x53, 0x20, 0xff, [0x08, 0x64, 0x10, 0x02]b));
	var read = d.peekCamMode();
	// The UCD2 leg must survive the interlude too: the frame that was open was
	// closed by this frontier (cut, as the corpus names it), not destroyed by
	// the legacy reader.
	logger.debug("ucd2FrameOpen=" + open.toString() + " legacyAnswerRead=" + show(read));
	return open && read != null && read.equals("v2");
}

// Two questions this file deliberately does NOT answer, so that the suite does
// not freeze what no camera on this bench has ever said:
//   1. What code an X6 puts at the head of the body of an ANSWER. This barrel's
//   ucd2IsAck() asks for 0x00c8 (the legacy envelope's status code) with the
//   request id it sent. The one captured UCD2 frame in this repository - the
//   GET_OPTIONS frame carried by tools/test_golden.py, decoded by
//   insta360_ucd2.describe_frame() as code 8 = CMD_GET_OPTIONS with request id 1
//   - is request-shaped: an X6 answer may echo its request's code instead of
//   answering 0xc8, and no X6 has ever been asked here. The signal that would
//   decide it is the first X6 trace with a UCD2 answer in it, named in the plan.
//   2. Whether a TRUNCATED non-answer UCD2 frame must be delivered with a
//   truncation flag, as the legacy leg does through x5RxTruncated. Today the
//   open UCD2 frame yields to the next head and nothing is read out of it,
//   because the only reading the UCD2 leg makes is onUcd2Frame (a recording
//   state), and the answer path above already closes on the first 20 octets. If
//   a UCD2 feature is ever read - an option, a storage figure, a battery - the
//   rule of PROTOCOL_APK L407-408 (deliver at the boundary, flagged) applies to
//   this leg too, and the vector above will be the place it is written.
