// Advertise the Insta360 wake iBeacon for N seconds: wake <6-char serial suffix> [seconds]
import Foundation
import CoreBluetooth
let args = CommandLine.arguments
let suffix = Array(args[1].utf8)
let secs = args.count > 2 ? Double(args[2])! : 30
var uuid: [UInt8] = [0x09] + Array("ORBIT".utf8) + [0x09, 0xFF, 0x0F, 0x00] + suffix
var payload = uuid + [0, 0, 0, 0, 0xE4]      // 16 UUID + major + minor + tx power = 21
class D: NSObject, CBPeripheralManagerDelegate {
  var pm: CBPeripheralManager!
  override init() { super.init(); pm = CBPeripheralManager(delegate: self, queue: nil) }
  func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
    print("state", p.state.rawValue)
    if p.state == .poweredOn {
      p.startAdvertising(["kCBAdvDataAppleBeaconKey": Data(payload)])
    }
  }
  func peripheralManagerDidStartAdvertising(_ p: CBPeripheralManager, error: Error?) {
    print("advertising", error.map { "\($0)" } ?? "ok", "len", payload.count, uuid.count == 16)
  }
}
let d = D()
RunLoop.main.run(until: Date().addingTimeInterval(secs))
d.pm.stopAdvertising(); print("stopped")
