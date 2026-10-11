# MacMouseGestures

<!-- macos-app:project:start -->
## เกี่ยวกับแอพ

แอพ menu bar map mouse gesture ไปเป็นการ navigate desktop: กดค้างปุ่มขวาแล้วลากซ้าย/ขวาเพื่อสลับ Space (มี animation), ลากขึ้น/ลงเพื่อเปิด Mission Control/Application Windows และกำหนด action ให้ปุ่ม 3/4 ได้

## สิทธิ์ macOS ที่ใช้

- Accessibility (event tap และ synthesized input)
- Launch at Login ผ่าน `SMAppService`

## ข้อควรระวังเฉพาะแอพ

- ใช้ private behavior: raw value ของ `CGEventField` สำหรับ gesture ของ Spaces (DockSwipe event อยู่ใน `Sources/MacMouseGesturesBridge`) และ `CoreDockSendNotification` สำหรับ Mission Control (อยู่ใน `Sources/MacMouseGestures/Services/PrivateApis.swift`) ไม่ปลอดภัยสำหรับ App Store
- event ที่แอพ post เองต้อง mark ไว้เพื่อไม่ให้ event tap ประมวลผลซ้ำ
- การคลิกขวาสั้น ๆ ต้อง replay เป็นคลิกขวาปกติ และปุ่มที่ตั้งเป็น No Action ต้องทำงานแบบเดิมของระบบ
- รายละเอียดการ investigate อยู่ที่ `Docs/spec-private-spaces-drag.md`
<!-- macos-app:project:end -->

<!-- macos-app:standard:start v1 -->
## Stack

- Swift 6 + SwiftPM เท่านั้น ห้ามสร้าง `.xcodeproj` หรือ `.xcworkspace`
- AppKit สำหรับ app lifecycle, menu bar, window และ event tap; SwiftUI สำหรับ view ข้างใน
- เป็นแอพ menu bar (`LSUIElement = true`) เว้นแต่ส่วน "เกี่ยวกับแอพ" ระบุไว้เป็นอย่างอื่น
- ห้ามเพิ่ม dependency ภายนอกก่อนถามผู้ใช้ ถ้าต้องใช้โค้ดจากที่อื่นให้ vendor ไว้ใน `Vendor/` พร้อม license

## โครงสร้าง repo

```
MacMouseGestures/
├── AGENTS.md              # ไฟล์นี้ (CLAUDE.md มีแค่ @AGENTS.md)
├── README.md
├── Package.swift
├── Sources/
│   ├── MacMouseGestures/      # executable target: AppKit/SwiftUI
│   │   ├── App/           # main.swift, AppDelegate, MenuBarController
│   │   ├── Views/         # SwiftUI view, NSWindow/NSPanel
│   │   └── Services/      # ส่วนที่แตะระบบ: permission, event tap, login item, private API
│   ├── MacMouseGesturesCore/  # library target: logic ล้วน ไม่ import AppKit/SwiftUI
│   └── MacMouseGesturesBridge/ # (ถ้าจำเป็น) C/ObjC bridge สำหรับ private API
├── Tests/
│   └── MacMouseGesturesCoreTests/
├── Scripts/
│   ├── dev-app.sh         # build + run แบบ debug
│   └── build-app.sh       # สร้าง dist/<Display Name>.app
├── Assets/AppIcon.png     # 1024x1024
├── Docs/                  # spec, idea, init prompt
├── Vendor/                # (ถ้ามี) โค้ดภายนอกที่ vendor มา
└── dist/                  # output (gitignored)
```

- ไฟล์ที่ห้ามอยู่ที่ root: `Info.plist`, `*.icns`, `build-app.sh` หรือสคริปต์อื่น (สคริปต์ทั้งหมดอยู่ใน `Scripts/`)
- ชื่อโฟลเดอร์ใช้ตามนี้ตรงตัว (`Docs` ไม่ใช่ `docs`, `Scripts` ไม่ใช่ `scripts`)
- ไม่ใช้ `resources:` ใน `Package.swift` รูปและไฟล์ที่ต้องอยู่ใน bundle ให้วางใน `Assets/` แล้วให้ `build-app.sh` copy เข้า `Contents/Resources`

## คำสั่ง

| งาน | คำสั่ง |
|---|---|
| รันระหว่างพัฒนา | `Scripts/dev-app.sh` |
| test | `swift test` |
| build `.app` | `Scripts/build-app.sh [debug\|release]` → `dist/Mac Mouse Gestures.app` |

- `Info.plist` สร้างใน `Scripts/build-app.sh` ที่เดียว ถ้าจะแก้ version, bundle id หรือ usage description ให้แก้ที่ตัวแปรด้านบนของสคริปต์
- Bundle id: `dev.sumetph.MacMouseGestures`
- Sign ด้วย `Apple Development` เพื่อให้สิทธิ์ Accessibility/Input Monitoring ไม่หายหลัง rebuild (override ด้วย `CODE_SIGN_IDENTITY=-`)

## แนวทางเขียนโค้ด

- logic ที่ test ได้ (parser, state machine, การคำนวณ layout, model) อยู่ใน `MacMouseGesturesCore` ส่วน target แอพทำหน้าที่ต่อสายกับระบบและ UI เท่านั้น
- โค้ดที่แตะ UI ใส่ `@MainActor`
- การเช็กและขอสิทธิ์รวมไว้ที่ `Services/PermissionManager.swift` ที่เดียว
- ค่า settings เก็บใน `UserDefaults` ผ่าน type เดียว (`AppSettings`) ห้ามเรียก `UserDefaults` กระจายหลายที่
- ใช้ `os.Logger` (subsystem = bundle id) ห้ามใช้ `print`
- ถ้าใช้ private API ให้รวมไว้ในไฟล์ `PrivateApis.swift` หรือ Bridge target พร้อม comment ว่ามาจากไหน และ fail แบบปลอดภัยถ้า symbol ไม่มี
- ห้าม hardcode path ของเครื่อง ให้ใช้ `FileManager` หา Application Support ของแอพ

## Tests

- ใช้ Swift Testing (`import Testing`, `@Test`, `#expect`) และทดสอบ target `MacMouseGesturesCore`
- โค้ดที่ต้องใช้สิทธิ์หรือ UI จริงไม่ต้องเขียน unit test แต่ให้แยก logic ออกมาเป็น Core เพื่อ test แทน

## ก่อนบอกว่างานเสร็จ

1. `swift build` และ `swift test` ผ่าน
2. ถ้าแก้ `Scripts/` หรือ `Package.swift` ต้องรัน `Scripts/build-app.sh` ผ่านด้วย
3. ปิดแอพที่รันไว้ทดสอบ (`pkill -x MacMouseGestures`)
4. ถ้ามีการเปลี่ยนสิทธิ์ ฟีเจอร์ หรือคำสั่ง ให้อัปเดต README และส่วน project ด้านบนของไฟล์นี้
<!-- macos-app:standard:end -->
