using Toybox.System;
using Toybox.BluetoothLowEnergy;
using Toybox.Time;
using Toybox.WatchUi;
using Toybox.Application as App;
using Toybox.Position;
using Toybox.Graphics;
using Toybox.Application.Storage;

module BLEBarrel {

const DEVICE_NAME = "ONE "; // Full name is "ONE R DV6W5S";
const DEVICE_NAME2 = "GO2 "; 
const DEVICE_NAME3 = "X3 "; // Full name is "X3 7MN5JB";
const DEVICE_NAME4 = "GO3 "; 
const DEVICE_NAME5 = "ACE ";
const DEVICE_NAME6 = "X4 ";

const LBS_SERVICE = BluetoothLowEnergy.stringToUuid("0000BE80-0000-1000-8000-00805F9B34FB");    // Camera Service entry point
const LBS_RW_CHAR = BluetoothLowEnergy.stringToUuid("0000BE81-0000-1000-8000-00805F9B34FB");    // Camera command channel
const LBS_NOTIF_CHAR = BluetoothLowEnergy.stringToUuid("0000BE82-0000-1000-8000-00805F9B34FB"); // Camera notification channel
const LBS_NOTIF_DESC = BluetoothLowEnergy.cccdUuid();
// b after the array is for ByteArray
const stateBusy =  0xf4; // Byte Array starts with  a "33" Error message when camera is busy
const stateCmdErr = 34; // Byte Array starts with a "34" Error message when an invalid command is sent.
const stateStandby = [0x7, 0, 0, 0, 0x5, 0, 0]b;
const responseSig =[0x00, 0x00, 0x04, 0x00, 0x00]b;
const stateStopRec = 0;
const stateStartRec = 1;
const stateStarting = 2;
const stateStopping = 3;
const SeqPos = 10;

var recState = stateStopRec;
var startRecTime = Time.now(); 
var elapsedRecTime;
var clockTime;
var lastTime = Time.now();
var GPSon = false;
var GPSaccuracy = Position.QUALITY_NOT_AVAILABLE;
var connecting = false;

 
var SeqNo = 1;
var queue = [];
var cmdStartRec = [0x12, 0, 0, 0, 0x4, 0, 0, 0x4, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x1]b;  // Start video Recording commmand
var cmdStopRec =  [0x12, 0, 0, 0, 0x4, 0, 0, 0x5, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x10, 0x1]b; // Stop recording command
var cmdApply =    [0x10, 0, 0, 0, 0x4, 0, 0, 0xf, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0]b; // Apply settings
var cmdSet5k24 =  [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x14, 0x18, 0x7]b; // Set video mode to 5.7k 24fps
var cmdSet5k25 =  [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x13, 0x18, 0x7]b; // Set video mode to 5.7k 25fps
var cmdSet5k30 =  [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0a, 0x18, 0x7]b; // Set video mode to 5.7k 30fps
var cmdSet4k30 =  [0x17, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x0, 0x18, 0x7]b; // Set video mode to 4k 30fps
var cmdSet4k50 =  [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0c, 0x18, 0x7]b; // Set video mode to 4k 50fps
var cmdSet3k100 = [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0d, 0x18, 0x7]b; // Set video mode to 3k 100fps
var cmdSetHDR =   [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x15, 0x18, 0x7]b; // Set video mode to HDR
var cmdSetTL =    [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0a, 0x18, 0x2]b; // Set video mode to Timelapse
var cmdSetBullet= [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0d, 0x18, 0x4]b; // Set video mode to Bullet time
var cmdSetPhoto =      [0x3f, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0xe3, 0x00, 0x00, 0x80, 0x00, 0x00, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdSetPhotoHDR =   [0x46, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0x01, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00, 0x1a, 0x03, 0x27, 0x00, 0x4e]b;
var cmdSetPhotoBurst = [0x41, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0x0a, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0x03, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdSetInterval =   [0x3f, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0xe3, 0x00, 0x00, 0x80, 0x00, 0x00, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdSetNightShot = [0x41, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0x2b, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0x04, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdHighlight = [0x36, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x3c, 0x00, 0x02, 0x8b, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0xde, 0xfc, 0xd3, 0xfa, 0x05, 0x1a, 0x1e, 0x63, 0x6f, 0x6d, 0x2e, 0x69, 0x6e, 0x73, 0x74, 0x61, 0x33, 0x36, 0x30, 0x2e, 0x6b, 0x65, 0x79, 0x54, 0x69, 0x6d, 0x65, 0x2e, 0x68, 0x69, 0x67, 0x68, 0x6c, 0x69, 0x67, 0x68, 0x74]b;
var cmdTrackThat = [0x36, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x3c, 0x00, 0x02, 0xa8, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0xf8, 0xfc, 0xd3, 0xfa, 0x05, 0x1a, 0x1e, 0x63, 0x6f, 0x6d, 0x2e, 0x69, 0x6e, 0x73, 0x74, 0x61, 0x33, 0x36, 0x30, 0x2e, 0x6b, 0x65, 0x79, 0x54, 0x69, 0x6d, 0x65, 0x2e, 0x74, 0x72, 0x61, 0x63, 0x6b, 0x54, 0x68, 0x61, 0x74]b;
var currentMode = cmdSet5k30;
var videoMode = true;
var currentLabel = "5.7K / 30";
var startMessage = "";
	
(:glance)
class BleDevice extends BluetoothLowEnergy.BleDelegate {
	var scanning = false;
	var scanTimeout = 64;
	var device = null;
	var button = 0;

	hidden function debug(str) {
		System.println("[ble] " + str);
	}

	function initialize() {
		BleDelegate.initialize();
		debug("initialize");
	}

	// Send command to BLE device
	function sendCMD(value) {
		var service;
		var ch;
		var i;
		var j;

		// check that the camera is actually connected, otherwise start a scan
		// debug("sendCMD: new scan ? " + scanning + " " + (device == null));
		if (!scanning) {
			if (device == null) {
		    	recState = stateStopRec;
				BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
				return;
//			} else if (!device.isConnected()) {
//		    	recState = stateStopRec;
//		    	BluetoothLowEnergy.unpairDevice(device);
//				BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
//				return;
			} else {
				service = device.getService(LBS_SERVICE);
				// debug("sendCMD: service null "  + (service == null));
				if (service == null) {
			    	recState = stateStopRec;
			    	BluetoothLowEnergy.unpairDevice(device);
			    	device = null;
					BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
					return;
				} 
			}
		} else {
			return ;
		}
		
		// the ble messages are numbered in sequence (byte 10)
		SeqNo = SeqNo + 1;
		if (SeqNo > 254) {
			SeqNo = 1;
		}
		value[SeqPos] = SeqNo; 

		// max message length = 20. the message has to be split into 20 bytes parts which are put in a queue.
		// each write operation has to be finished before the next one can occur.
		// the dequeuing is done in the onCharacteristicWrite function
		if (value.size() > 20) {
			j = (value.size()-1)/20;
			for (i = 0; i <= j.toNumber(); i++) { 
				queue.add(value.slice(i*20,(i+1)*20));
			} 	
		} else {
			queue.add(value);
		}
		
		// kind of a hack: send a unneeded write command for the onCharacteristicWrite function to trigger
		// need to think of a better way. 
		try {
			// debug("sendCMD: service.getChar");
			ch = service.getCharacteristic(LBS_RW_CHAR);
		} catch (ex) {
			    debug("[sendCMD] exception: " + ex.getErrorMessage());
		}
		try {
			// debug("sendCMD: send stateStandby");
		    ch.requestWrite(stateStandby, {:writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT});
		} catch (ex) {
			    debug("[sendCMD] exception: " + ex.getErrorMessage());
		}
	}

	function onCharacteristicChanged(ch, value) {
		// except for keep alive mesages that are 7 bytes long all others are at least 16 bytes long
		if (value.size() >=  18) {
		// messages are cut into 20 bytes max length (but can be shorter)
		// The necessary info are in the first 20 bytes, the rest is ignored
		// 2 first bytes is the length of the message (little endian). 
		// followed by 00 00 04 00 00. Check for this value
		  if (responseSig.equals(value.slice(2,7))) {
			// debug("char read " + ch.getUuid() + " " + value + " Size: " + value.size()); 
			// the 8th byte is the "command" code
			// Check to see if we got a Stop or Start recording event. 
			// Command byte == 0x10 position 17 is >0 = start. 0=end.
			if ((value[7] == 0x10) and (value[17] > 0x00)) {
				// debug("Start Shooting");
				mMessage = "Shooting";
				recState = stateStartRec;
				startRecTime = Time.now();
//				WatchUi.pushView(new ViewData(BleDevice2), new InputDelegate(BleDevice2), WatchUi.SLIDE_IMMEDIATE);
				
			} else 	if ((value[7] == 0x10) and (value[17] == 0x00)) {
				// debug("Stop Shoot");
				mMessage = currentLabel + "\n" + startMessage;
				recState = stateStopRec;
			} else if (stateBusy.equals(value[7])) {
				// sendCMD(cmdStopRec);
				mMessage = "Busy...";
   			} else if (stateCmdErr.equals(value[0])) {
				mMessage = currentLabel + "\n" + startMessage;
				recState = stateStopRec;
			} else {
				 debug("Unknown Response " + value);
				// mMessage = "-";
			}
		  }
		} 	
		
		//second guess elapsed recording time
		if (recState == stateStartRec) {
			clockTime = Time.now();
			elapsedRecTime = clockTime.subtract(startRecTime);
			mMessage = currentLabel + "\n" + toTimeString(elapsedRecTime.value()); 
		} else {
			// mMessage = "Stopped\n" + currentLabel + "\n" + startMessage;
		}
		WatchUi.requestUpdate();
	}
	
	function onCharacteristicWrite(ch, st) {
	// we need to wait before sending the next ble message. 
	// this function is called only when the previous message has been writen to the camera (successfuly or not) 	
		if (queue.size() > 0) {
			try {
			    ch.requestWrite(queue[0], {:writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT});
		    } catch (ex) {
			    debug("[onCharWrite] exception: " + ex.getErrorMessage());
		    }
			// debug("[onCharWrite] deq : " + queue[0] + " qsize: " + queue.size() + " Status " + st );
			queue = queue.slice(1,queue.size());
		} else {
			debug ("[onCharWrite] queue empty Status " + st );
		}
	}
	
	function toTimeString(seconds) {
		var hours = seconds/3600;
    	var min = (seconds - hours*3600)/60;
    	var sec = (seconds - hours*3600 - min*60);
    	
    	return ("" + hours + ":" + min.format("%02d") + ":" + sec.format("%02d"));
	}
	

	function onProfileRegister(uuid, status) {
		debug("registered: " + uuid + " " + status);
	}

	// Called by open() function, part of initialization process.
	function registerProfiles() {
		var profile = {
			:uuid => LBS_SERVICE,
			:characteristics => [{
				:uuid => LBS_RW_CHAR,
                        }, {
				:uuid => LBS_NOTIF_CHAR,
				:descriptors => [LBS_NOTIF_DESC],
			}]
		};
		try {
			BluetoothLowEnergy.registerProfile(profile);
		} catch (ex) {
			    debug("[sendCMD] exception: " + ex.getErrorMessage());
		}

	}

	function onScanStateChange(scanState, status) {
		debug("scanstate: " + scanState + " " + status);

		if (scanState == BluetoothLowEnergy.SCAN_STATE_SCANNING) {
			scanning = true;
			mMessage = "Scanning...\n" + scanTimeout;
			WatchUi.requestUpdate() ;
			
		} else {
			scanning = false;
			scanTimeout = 64;
			if (device == null) {
				mMessage = startMessage + "\nto scan";
			} else {
				mMessage = currentLabel + "\n" + startMessage;
			}
			WatchUi.requestUpdate() ;
		}
	}

	function onConnectedStateChanged(dev, state) {
		// debug("connected: " + dev.getName() + " " + state);
		mMessage = currentLabel + "\n" + startMessage;
		WatchUi.requestUpdate();
		if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
			connecting = false;
			if (scanning) {
			try {
				BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
			} catch (ex) {
			    debug("[onConStateChg] OFF exception: " + ex.getErrorMessage());
		    }
			
				scanning = false;
			}
			device = dev;
		} else {
			if (!scanning) {
				scanning = true;
				device = null;
			open();
//			try {
//				BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
//			} catch (ex) {
//			    debug("[onConStateChg] On exception: " + ex.getErrorMessage());
//		    }
			
			}
		}
	}

	private function connect(result) {
		debug("[connect] " + result.getDeviceName());
		if (!connecting) {
			connecting = true;
			try {
				device = BluetoothLowEnergy.pairDevice(result);
			} catch (ex) {
			    debug("[Connect] Pair exception: " + ex.getErrorMessage());
		    }
			
		}
	}

//	private function dumpUuids(iter) {
//		for (var x = iter.next(); x != null; x = iter.next()) {
//			debug("uuid: " + x);
//		}
//		return false;
//	}

	function onScanResults(scanResults) {
//		debug("scan results");
//		var uuids;
		var name;
		var rssi;
		for (var result = scanResults.next(); result != null; result = scanResults.next()) {
//			uuids = result.getServiceUuids();
			name = result.getDeviceName();
			rssi = result.getRssi();

			debug("[onScanResults] device: " + name + " rssi: " + rssi);
//			dumpUuids(uuids);

			if (name != null) {
				// debug ("device name: [" + name.substring(0,4) +"]");
				if (DEVICE_NAME.equals(name.substring(0,4)) or 
					DEVICE_NAME2.equals(name.substring(0,4)) or
					DEVICE_NAME3.equals(name.substring(0,3)) or
					DEVICE_NAME4.equals(name.substring(0,4)) or
					DEVICE_NAME5.equals(name.substring(0,4)) or
					DEVICE_NAME6.equals(name.substring(0,3))) {
//					try {
//						Storage.setValue("device", result);
//					} catch (ex) {
//			    		debug("[onScanResult] storage write exception " + ex.getErrorMessage());
//					}
					connect(result);
					return;
				}
			}
			scanTimeout--;
			mMessage = "Scanning...\n" + scanTimeout;
			WatchUi.requestUpdate() ;
			
			if (scanTimeout == 0) {
				try {
					BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
				} catch (ex) {
			    	debug("[onConStateChg] OFF exception: " + ex.getErrorMessage());
		    	}
			}
		}
	}

	function toDouble(single) {
		// convert a 32bit float to 64-bit, signed, in a bitArray. 
		var double = new [0]b;
		var d1 = new [4]b;
		var d2 = new [4]b;
		var t32 = new [4]b;
		var ts = 0l;
		var tb = 0l;
		var tb1 = 0l;
		var tb2 = 0l;
		var te = 0l;
		var tm = 0l;
		var bias = 0l;
		// Need to convert to float 64bit, but not directly supported by Connect IQ.
		// convert back and forth from 32bit float to 32bit INT to have a "bitwise" representation
		t32.encodeNumber(single,Lang.NUMBER_FORMAT_FLOAT,null);
		tb = t32.decodeNumber(NUMBER_FORMAT_UINT32, null);
		// get the sign
		ts = tb & 0x80000000;
		// get the exponent part 
		te = tb & 0x7f800000;
		te >>= 23;
		// new 64bit based bias
		bias = te - 127 + 1023;
		bias <<= 52;
		// get the mantisse part and shift it 
		tm = tb & 0x007fffff;
		tm <<= 29;
		// add the new bias to the mantis and the sign
		ts <<= 32;
		tb = ts + bias + tm;
		// cut the new value in 2 32bit chunks
		tb1 = tb;
		tb1 >>= 32;
		d1.encodeNumber(tb1, NUMBER_FORMAT_UINT32, null);
		tb1 <<=32;
		tb2 = tb - tb1;
		d2.encodeNumber(tb2, NUMBER_FORMAT_UINT32, null);
		// debug ("[toDouble] " + tb.format("%x"));
		// build the final bitArray, little endian
		double.addAll(d2);
		double.addAll(d1);
		return double;
	}

	function sendPosition(info) {
		// Build a byte array with the following info in HEX format, all Little endian
		// byte position - value
		// 00-13 47 00 00 00 04 00 00 35 00 02 ff 00 00 80 
		// 14-17 00 00 0a 35 ?
		// 18-21 UX Epoch (int 32)
		// 22-25 00 00 00 00 
		// 26-28 00 00 41 ?
		// 29-36 Latitude (double float)
		// 37    N / S (ASCII)
		// 38-45 Longitude (double float)
		// 46    E / W (ASCII) 
		// 47-54 Speed meters per seconds (double float) 
		// 55-62 Heading, degrees  (double float) 
		// 63-70 Altitude Meters (double float)


		var header = [0x47, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x35, 0x00, 0x02, 0xff, 0x00, 0x00, 0x80, 0x00, 0x00, 0x0a, 0x35]b;
		var uxEpoch = info.when;
		var filler = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x41];
		var location = [0,0];
		var latitude = 0;
		var longitude = 0;
		var speed = info.speed;
		var heading = 0; 
		var altitude = info.altitude;
		var temp32 = new[4]b;
		var temp64 = new[8]b;
		var sector = 0x4e;
		
		GPSaccuracy = info.accuracy;
		WatchUi.requestUpdate();
		debug("[sendPosition] Accuracy: " + GPSaccuracy); 
		

		if ((device == null) or (recState != stateStartRec)) { return; }
		
		if (info.position != null) {
			location = info.position.toDegrees();
			latitude = location[0];
			longitude = location[1];
			
		} else { return; }
		//heading is provided in radians, convert to degrees
		if (info.heading != null) {
			heading = info.heading*180/Math.PI;
			if (heading < 0) {
				heading = 360 + heading;
			}
		} else { return; }
		
		if (speed == null) {
			speed = 0;
		}
		
		// debug ("[onPosition] " + uxEpoch.value() + " " + latitude + " " + longitude + " " + speed + " " + heading + " " + altitude);

		// Video & Photo telemetry are encoded differently.
		if (videoMode) {
			// encode timestamp
			temp32.encodeNumber(uxEpoch.value(),Lang.NUMBER_FORMAT_UINT32,null);
			header.addAll(temp32);
			header.addAll(filler);
			// North or South
			if (latitude >= 0) {
				sector = 0x4e; // ASCII 'N'
			} else {
				sector = 0x53; // ASCII 'S'
			}
			// encode latitude
			temp64 = toDouble(latitude.abs());
			header.addAll(temp64);
			header.add(sector);
			// East or West
			if (longitude >= 0) {
				sector = 0x45; // ASCII 'E'
			} else {
				sector = 0x57; // ASCII 'W'
			}
			// encode longitude
			temp64 = toDouble(longitude.abs());
			header.addAll(temp64);
			header.add(sector);
			// encode speed
			temp64 = toDouble(speed.abs());
			header.addAll(temp64);
			
			// encode heading
			temp64 = toDouble(heading);
			header.addAll(temp64);
			
			// encode altitude		
			temp64 = toDouble(altitude.abs());
			header.addAll(temp64);
	
			// debug ("hex " +header.size() +" "+ header); 
			sendCMD(header);
		} 
	}
	
	
	function open() {
		var temp;
		// var result;		
		
		if (System.getDeviceSettings().isTouchScreen) {
			startMessage = "Tap Here";
		} else {
			startMessage = "Press Start";
		}
		// debug("open");
		// Load last state of app
		recState = App.getApp().getProperty("recState");
		if (recState == null) {
			recState = stateStopRec;
		}
		currentMode = App.getApp().getProperty("currentMode");
		currentLabel = App.getApp().getProperty("currentLabel");
		if (currentMode == null) {
			currentMode = cmdSet5k30;
			currentLabel = "5.7K / 30";
		}
		lastTime = Time.now();
		startRecTime = new Time.Moment(App.getApp().getProperty("startRecTime")); 
		if (startRecTime == null) {
			startRecTime = Time.now();
		}
		temp = App.getApp().getProperty("cmdStartRec");
		if (temp != null) {
			cmdStartRec = temp;
		}
		
		temp = App.getApp().getProperty("cmdStopRec");
		if (temp != null) {
			cmdStopRec = temp;
		}
		GPSon = App.getApp().getProperty("GPSon");
		if (GPSon == null) {
			GPSon = false;
		}
		// Bluetooth initialisation
		debug("[open] CIQ V " + System.getDeviceSettings().monkeyVersion);
		registerProfiles();
		BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
		// try to connect directly to the last known device.
//		result = Storage.getValue("device");
//		if (result != null) {
//			debug ("[open] direct connect");
//			connect(result);
//		} 
				
	}

	function close() {
		debug("close");
		// Save current state of app 
		App.getApp().setProperty("recState", recState);
		App.getApp().setProperty("startRecTime", startRecTime.value());
		App.getApp().setProperty("currentMode", currentMode);
		App.getApp().setProperty("currentLabel", currentLabel);
		App.getApp().setProperty("cmdStartRec", cmdStartRec);
		App.getApp().setProperty("cmdStopRec", cmdStopRec);
		App.getApp().setProperty("GPSon", GPSon);
		if (scanning) {
			BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
		}
		if (device) {
			BluetoothLowEnergy.unpairDevice(device);
		}
		Position.enableLocationEvents(Position.LOCATION_DISABLE,null);
	}
}


}
