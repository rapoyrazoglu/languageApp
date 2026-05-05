# PaktlyKit (iOS / macOS Swift SDK)

Swift Package Manager kütüphanesi. Paktly registry'lerinden pack indirir,
disk'te saklar, derslerini SwiftUI view'larıyla çalıştırır.

> **Durum**: alpha — Phase 3 geliştirme aşamasında. API stabil değil.

## Hızlı kullanım

```swift
import PaktlyKit

// 1. Registry client — istersen api.paktly.dev, istersen kendi self-host URL'in
let registry = RegistryClient(baseURL: URL(string: "https://api.paktly.dev")!)

// 2. Pack ara, indir, lokal saklayıp doğrula (SHA256)
let store = PackStore.default
let pack = try await registry.getPack(id: "com.github.ata.example-nihongo")
let installed = try await store.download(pack: pack, version: "0.2.0", from: registry)

// 3. Bir dersi çalıştır
let lesson = try installed.lesson(id: "001-hiragana-aiueo")
// SwiftUI: LessonRunnerView(lesson: lesson) — Phase 3e'de gelecek
```

## Yapı

```
ios/
├── Package.swift
├── Sources/
│   └── PaktlyKit/
│       ├── Models/        Manifest, Lesson, Block (Codable, schema 1.0 + 1.1)
│       ├── Registry/      RegistryClient (REST), AuthClient (token issue)
│       └── Store/         PackStore (download, verify, cache)
└── Tests/
    └── PaktlyKitTests/
        ├── Fixtures/      Gerçek pack JSON örnekleri
        └── *Tests.swift
```

## Geliştirme

Mac üzerinde:

```bash
cd ios
swift test                 # birim testler (host'ta çalışır, simulator gerektirmez)
swift build                # release build
xed Package.swift          # Xcode'da aç
```

CI: `.github/workflows/ios.yml` her commit'te macOS runner'da `swift test`
çalıştırır.

## Platform desteği

- iOS 16+
- macOS 13+ (testler ve geliştirme için; UI bileşenleri iOS odaklı)

## Self-hosting

`RegistryClient`'a hangi URL'i verirsen oraya bağlanır. Paktly hosted'a hiç
bağlı değildir — kendi backend'ini docker-compose ile ayağa kaldırıp SDK'yı
oraya yönlendirebilirsin. Bkz. `../docs/SELF_HOSTING.md` (Phase 5'te eklenecek).
