# Language Pack Format

Bu doküman, dil paketlerinin (pack) yapısını ve dağıtım yollarını tanımlar.
SDK ve backend bu spesifikasyona göre çalışır — değişiklikler `schemaVersion`
artırılarak yapılır.

| Sürüm | Durum | Eklenenler |
|---|---|---|
| **1.1.0** | Aktif (önerilen) | `aiCapabilities`, vocabulary `examples[]` + `ipa`, `previousPack`/`nextPack` (level path) |
| 1.0.0 | Hâlâ desteklenir (backwards-compatible) | İlk kararlı sürüm |

> v1.0.0 paketler değişiklik gerektirmez — schema'ya yeni alanlar **opsiyonel**
> olarak eklendi. Eski paketler hiçbir şey yapmadan çalışmaya devam eder.

## 1. Pack nedir?

Bir **pack** = bir dilin tüm derslerini içeren bir klasördür. Pack'ler:

- bir **manifest.json** (kart bilgisi)
- bir veya daha fazla **lesson JSON** dosyası
- isteğe bağlı **media** dosyaları (ses, görsel)

içerir. Pack'ler `.zip` olarak paketlenip dağıtılır.

## 2. Klasör yapısı

```
<pack-root>/
├── manifest.json           # ZORUNLU: pack tanım kartı
├── README.md               # önerilen
├── LICENSE                 # önerilen
├── lessons/                # ZORUNLU: en az 1 ders
│   ├── 001-intro.json
│   └── 002-...
└── media/                  # opsiyonel
    ├── audio/
    ├── images/
    └── video/
```

**Kurallar:**
- Klasör isimleri küçük harf + tire (`-`).
- Dosya yolları her zaman `pack-root`'a göredir; mutlak yol yasak.
- ZIP içindeki kök, ya doğrudan dosyalar olur ya da tek bir klasör — ikisi de kabul edilir; SDK normalleştirir.

## 3. Manifest

Tüm pack'in giriş noktasıdır. Şema: [`schema/manifest.schema.json`](../schema/manifest.schema.json).

Zorunlu alanlar: `schemaVersion`, `id`, `name`, `version`, `language`, `author`, `license`, `lessons`.

**`id` formatı:** Reverse-DNS (`com.github.<kullanici>.<paket>`). Bu sayede iki kişi aynı isimde pack yapsa bile çakışma olmaz.

**`version`:** [Semver](https://semver.org). `1.2.3` gibi.
- MAJOR: bozucu değişiklik (bir ders silindi, dersin id'si değişti)
- MINOR: yeni ders eklendi
- PATCH: yazım hatası düzeltildi, ses yeniden kaydedildi

**`schemaVersion`:** Bu manifestin uyduğu pack format sürümü. Geçerli değerler: `"1.0.0"` veya `"1.1.0"`. Yeni pack'ler `"1.1.0"` kullanmalı.

### 3.1 v1.1 opsiyonel alanlar

#### `aiCapabilities` (opsiyonel)

Pack'in destek ettiği AI özelliklerini deklare eder. Pack offline tam çalışır;
bu alan sadece **uygulamadaki AI butonlarını hangi pack'lerde göstereceğimizi**
belirler. Backend ek olarak kullanıcının abonelik durumunu kontrol eder.

```json
"aiCapabilities": {
  "questionGeneration": true,
  "explanation": true,
  "conversation": false,
  "hint": true
}
```

| Alan | Anlam |
|---|---|
| `questionGeneration` | AI bu pack'in içeriğinden yeni alıştırma soruları türetebilir |
| `explanation` | Kullanıcı "bunu daha detaylı anlat" derse AI gramer/etimoloji açıklaması üretir |
| `conversation` | AI bu pack'in vocabulary'siyle konuşma pratiği yaptırır |
| `hint` | Egzersiz sırasında bağlama duyarlı ipucu verir |

#### `previousPack` / `nextPack` (opsiyonel — level path)

Curated bir öğrenme yolunda pack'ler birbirine zincirlenir. Kullanıcı bir pack'i
bitirdiğinde SDK `nextPack`'i önerir.

```json
"previousPack": "com.paktly.ja.beginner-1",
"nextPack":     "com.paktly.ja.beginner-3"
```

## 4. Lesson

Şema: [`schema/lesson.schema.json`](../schema/lesson.schema.json).

Bir ders, sıralı **block**'lardan oluşur. Üç tip block var:

### 4.1 `explanation`
Düz metin açıklama (markdown ileride desteklenecek).

```json
{ "type": "explanation", "text": "Hiragana, Japoncada kullanılan üç yazı sisteminden biridir." }
```

### 4.2 `vocabulary`
Hedef dil → ana dil çevirisi listesi.

```json
{
  "type": "vocabulary",
  "items": [
    {
      "target": "こんにちは",
      "translation": "merhaba",
      "transliteration": "konnichiwa",
      "audio": "media/audio/konnichiwa.mp3",
      "ipa": "/koɲɲitɕiwa/",
      "examples": [
        {
          "text": "こんにちは、田中さん",
          "translation": "merhaba Tanaka-san",
          "audio": "media/audio/example-1.mp3"
        }
      ]
    }
  ]
}
```

**Alanlar:**
| Alan | Sürüm | Zorunlu | Açıklama |
|---|---|---|---|
| `target` | 1.0.0 | ✓ | Öğrenilecek dilde kelime/ifade |
| `translation` | 1.0.0 | ✓ | UI dilinde çevirisi |
| `transliteration` | 1.0.0 | — | romaji, pinyin, transliteration |
| `audio` | 1.0.0 | — | Ses dosyası yolu (1.1.0+'da opsiyonel; SDK iOS Siri/Android TTS ile fallback yapar) |
| `image` | 1.0.0 | — | Görsel ipucu |
| `notes` | 1.0.0 | — | Yazarın özel notu |
| `ipa` | **1.1.0** | — | Phonetic transcription (IPA) |
| `examples[]` | **1.1.0** | — | Örnek cümle listesi (text + translation + opsiyonel audio + notes) |

### 4.3 `exercise`
Etkileşimli alıştırma. `exerciseType` alanı türü belirler:

| Tür | Ne yapar |
|---|---|
| `flashcard` | Tek yüzde soru, çevirince cevap |
| `multipleChoice` | Çoktan seçmeli |
| `typing` | Kullanıcı yazarak cevaplar |
| `listening` | Ses çal, ne dendiğini sor |
| `matching` | Sol-sağ eşleştirme |
| `fillInBlank` | Boşluk doldurma |

Her türün `data` payload'ı farklıdır — SDK her tip için ayrı validation yapar.

## 5. Dağıtım

Pack'ler iki yoldan dağıtılır:

### 5.1 GitHub Release (önerilen)

1. Yazar pack'i kendi public reposunda hazırlar.
2. `git tag v1.0.0` + `git push --tags`.
3. GitHub > Releases > Draft a new release > tag seç > zip yükle (örn. `nihongo-1.0.0.zip`).
4. Yazar bize sadece repo URL'ini verir: `https://github.com/<user>/<repo>`.
5. Backend GitHub API'siyle:
   - En son release'i bulur
   - Release asset'lerinden zip'i indirir
   - SHA256 hash hesaplar, validate eder
   - S3'e koyar, registry DB'ye kayıt düşer

**Yazar için kolaylık:** Sürüm yönetimini Git tag'leriyle yapar, ekstra bir CLI öğrenmesi gerekmez.

### 5.2 Doğrudan ZIP yükleme

GitHub'ı olmayan veya kullanmak istemeyen yazarlar için:

1. Yazar `manifest.json`'da bir `version` belirler.
2. Backend'e zip yükler.
3. Backend aynı validation pipeline'ından geçirir.

Aynı `id` + `version` ikilisi tekrar yüklenemez (immutability).

## 6. Validation pipeline

Hangi yoldan gelirse gelsin her pack şu adımlardan geçer:

1. **Yapı kontrolü:** zip açılır, `manifest.json` var mı?
2. **Manifest schema:** JSON Schema validation.
3. **Ders dosyaları:** her `lessons[].file` mevcut mu, lesson schema'sına uyuyor mu?
4. **Media referansları:** her `audio`/`image`/`video` yolu pack içinde var mı?
5. **Boyut limiti:** toplam boyut limit altında mı (örn. 500 MB).
6. **Güvenlik:** zip-slip kontrolü (`../` ile pack dışına yazma).
7. **Hash:** SHA256 hesaplanır, registry'ye kaydedilir.

Herhangi bir adım fail olursa pack kabul edilmez ve yazara hata raporu döner.

## 7. Sürümleme ve immutability

- Yayınlanmış bir `id@version` **asla** değiştirilmez.
- Yazar düzeltme yapmak isterse yeni bir `version` çıkarır.
- SDK indirdiği pack'in hash'ini her açılışta doğrular — değişmişse atar.

## 8. SDK uyumluluğu

Manifest'teki `minSdkVersion` alanı, pack'i açabilecek minimum SDK sürümünü
belirtir. SDK bundan eski bir sürümdeyse pack'i indirmez/uyarır.
