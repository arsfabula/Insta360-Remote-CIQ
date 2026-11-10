import CoreGraphics
let opts = CGWindowListOption(arrayLiteral: .optionAll)
if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
  for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let name = w[kCGWindowName as String] as? String ?? ""
    let layer = w[kCGWindowLayer as String] as? Int ?? 1
    if owner.lowercased().contains("simulator") && layer == 0 && name.contains("Simulator") {
      print(w[kCGWindowNumber as String] as! Int); break
    }
  }
}
