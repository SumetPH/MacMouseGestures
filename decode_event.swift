import Foundation
import CoreGraphics

let fileURL = URL(fileURLWithPath: "native-record.log")
guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
    print("Could not read file")
    exit(1)
}

let lines = content.components(separatedBy: .newlines)
for line in lines {
    guard !line.isEmpty else { continue }
    guard let data = line.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
          let b64 = json["cg_data_base64"] as? String else {
        continue
    }
    
    if let eventData = Data(base64Encoded: b64),
       let event = CGEvent(withDataAllocator: kCFAllocatorDefault, data: eventData as CFData) {
        
        let type = event.type.rawValue
        if type == 30 {
            let phase = event.getIntegerValueField(CGEventField(rawValue: 0x84)!)
            let progress = event.getDoubleValueField(CGEventField(rawValue: 0x7c)!)
            print("Type 30: phase=\(phase), progress=\(progress)")
        }
    }
}
