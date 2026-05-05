# Mac'te sıfırdan başlama rehberi

Bu doküman **kodlama tecrüben olmadan** Paktly üzerinde çalışmaya başlamana
yardım eder. Hiçbir şeyi ezbere bilmiyorsan da takip edebilirsin. Adımlar
yaklaşık **30-60 dakika** sürer (kurulumlar arka planda inerken kahve
içersin).

---

## Bilgi vermem gereken iki şey

1. **Kod yazmana gerek yok.** Claude (sandbox'ta veya Mac'inde) tüm kodu
   yazar. Sen Türkçe / İngilizce ne istediğini söylersin, gözden geçirirsin,
   commit'lersin.
2. **Mac'te Claude da en az sandbox'taki kadar yetenekli.** "Claude Code"
   denen CLI aracı Mac'te dosya okuyup yazabilir, terminal komutları
   çalıştırabilir, GitHub'a push'layabilir. Buradakiyle aynı işi yapar.

---

## Adım 1 — Mac'i hazırla (~20 dk, çoğu indirme bekleme)

### 1.1 Xcode'u yükle (15-20 GB indirme!)

iOS uygulaması yapacaksak Xcode şart. App Store'dan ücretsiz indir:

1. **App Store** aç → "Xcode" ara → **Get** / **Install**
2. ~10 GB indirir, ~30 GB diske oturur. İlk açılışta lisans + extra
   bileşenler için 5-10 dk daha bekleme

İndirme bitince **bir kere aç**, lisansı kabul et, kapat.

### 1.2 Command Line Tools

Xcode'la birlikte gelir ama emin olmak için terminal'de:

```bash
xcode-select --install
```

Açılan dialog "Install" → bekle. Zaten kuruluysa "already installed" der,
sorun yok.

Doğrula:
```bash
git --version
swift --version
```
İkisi de bir sürüm yazıyorsa hazırsın.

### 1.3 Homebrew (paket yöneticisi, opsiyonel ama faydalı)

Sonradan başka araç kurmak gerekirse hayat kurtarır:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Komut sonunda terminal'de şuna benzer satır göstereceğini söyleyecek:
```
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
```
Onu kopyala-yapıştır + terminal'i yeniden aç.

---

## Adım 2 — Claude Code CLI'ı kur (~5 dk)

[Claude Code](https://docs.claude.com/en/docs/claude-code) Anthropic'in resmi
CLI aracı. Terminal'den `claude` yazınca açılır, sandbox'takiyle aynı yetkilere
sahiptir (dosya okur/yazar, terminal komutu çalıştırır).

### 2.1 Yükleme

Resmi kurulum komutunu sitelerinden alacaksın (zamanla değişebiliyor).
Genelde:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```
veya `brew install claude`. Resmi sayfa: <https://docs.claude.com/en/docs/claude-code/setup>

### 2.2 Login

```bash
claude
```
İlk açılışta browser'da Anthropic hesabınla giriş yap. Plan: Pro veya Max
(Claude Code dahil) ya da API kredisi.

Test:
```bash
claude --version
```

---

## Adım 3 — Repo'yu Mac'e indir (~2 dk)

### 3.1 GitHub kimlik bilgileri

Mac terminal'inden GitHub'a push'layabilmek için bir kez SSH key kur:

```bash
ssh-keygen -t ed25519 -C "senin@email.com"
```
Üç soruya da Enter (varsayılan path + boş passphrase, isterson passphrase
ekle ama Mac Keychain hatırlar).

```bash
cat ~/.ssh/id_ed25519.pub
```
Çıkan public key'i kopyala. <https://github.com/settings/ssh/new> → yapıştır
→ Add SSH key.

Doğrula:
```bash
ssh -T git@github.com
```
"Hi rapoyrazoglu! ..." derse oldu.

### 3.2 Clone

İstediğin bir klasöre (örn. `~/Projects`):

```bash
mkdir -p ~/Projects
cd ~/Projects
git clone git@github.com:rapoyrazoglu/languageApp.git
cd languageApp
```

Repo indi. İçinde her şey hazır: backend, iOS SDK, dokümanlar, deploy
runbook.

### 3.3 Git config (bir kerelik)

Commit'lerde adın görünsün diye:

```bash
git config user.name "Ata"
git config user.email "senin@email.com"
```

---

## Adım 4 — Claude'u repo dizininde başlat (~1 dk)

```bash
cd ~/Projects/languageApp
claude
```

`claude` komutu mevcut klasörü "working directory" yapar. Açılan promptta:

> "Merhaba, Paktly projesinde devam edeceğim. CLAUDE.md'yi oku, ROADMAP'e
> bak, son durumu özetle."

Claude `CLAUDE.md`'yi otomatik okur (her oturumda). Kısa süre sonra:
- Projenin ne olduğunu
- Hangi fazda olduğumuzu (Phase 3 iOS SDK)
- Live URL'leri (api.paktly.dev)
- Sıradaki işin ne olduğunu (RegistryClient yazma)

bilir hale gelir. Yani **bu sandbox'taki bilgi kayıt dışı kalmaz** — hepsi
repo'da, Claude okur, devam eder.

---

## Adım 5 — Günlük iş akışı

Mac'inde her oturum böyle:

```bash
cd ~/Projects/languageApp
git pull origin main           # internet'ten son değişiklikleri çek
claude                         # Claude oturumu başlat
```

Claude'a Türkçe konuş. Örnekler:

- **Yeni özellik**: "RegistryClient'ta /v1/packs/upload destekli olsun, multipart form-data ile zip yüklesin"
- **Bug fix**: "Şu hatayı görüyorum: [hata mesajı]. Düzelt."
- **Test çalıştır**: "iOS testlerini koştur" → Claude `cd ios && swift test --parallel` yapar
- **Demo app aç**: "Xcode'da demo app'i aç, simulator'da çalıştır" → Claude `xed` ile açar
- **Commit + push**: "Bunu push'layalım" → Claude Conventional Commits formatında commit + push yapar

---

## Adım 6 — iOS demo app'i çalıştır (Phase 3g'ye geldiğimizde)

Xcode kurulu olduğu için Mac'inde simulator açabilirsin:

```bash
cd ~/Projects/languageApp/ios
xed Package.swift              # Xcode'da paketi aç
```

Xcode'da:
- Sol üstte scheme (PaktlyKit) ve destination (iPhone 15 simulator) seç
- ⌘R = Run. Simulator açılır, demo app çalışır
- ⌘U = Run tests

İlk seferinde simulator ~1 dk yüklenir, sonrası anlık.

---

## Sürekli kontrol etmen gereken yerler

| Yer | Ne için |
|---|---|
| <https://github.com/rapoyrazoglu/languageApp/actions> | CI yeşil mi (her commit sonrası bak) |
| <https://github.com/rapoyrazoglu/languageApp/pulls> | release-please bot'tan PR var mı (varsa merge et) |
| <https://github.com/rapoyrazoglu/languageApp/releases> | Yayınlanan sürümler |
| <https://api.paktly.dev/healthz> | Backend canlı mı (`{"status":"ok"}` dönmeli) |
| AWS Console → Billing → Budgets | $40 alarm aşıldı mı |
| AWS Console → CloudWatch → Alarms | RDS / EC2 alarm yeşil mi |

---

## Sık sorulan terimler

| Terim | Anlamı | Pratikte |
|---|---|---|
| **commit** | Bir değişiklik kaydı | Git history'de bir nokta. "Bu değişikliği kaydet ve isim ver." |
| **push** | Yerel commit'leri GitHub'a yolla | "Şimdi internet'e koy" |
| **pull** | GitHub'dan son commit'leri çek | "İnternet'ten yeni şey var mı, indir" |
| **branch** | Paralel geliştirme dalı | Bizde sadece `main`, başka branch açmıyoruz |
| **PR (pull request)** | Bir branch'i diğerine merge etme önerisi | release-please bot'unun açtığı PR'ı merge edersin |
| **CI** | Continuous Integration — her commit'te otomatik test | GitHub Actions; yeşil = OK, kırmızı = bozuk |
| **deploy** | Kodu canlıya çıkarma | Watchtower bunu otomatik yapıyor; sen sadece push'ladıkça |
| **simulator** | iPhone taklit eden Mac uygulaması | Xcode'la geliyor, gerçek telefon gerekmiyor |
| **TestFlight** | Apple'ın iç test platformu | Phase 3 sonunda lazım, $99/yıl Developer hesabı gerek |
| **SDK** | Software Development Kit — başka uygulamalardan kullanılacak kütüphane | Bizdeki PaktlyKit Swift SDK'sı |

---

## Bir şey ters giderse

1. **Önce dur, panik yapma.** Hiçbir şey kaybolmaz — git geri alır, AWS
   snapshot'tan döner, GitHub'da her commit kaydı vardır.
2. **Hata mesajını Claude'a yapıştır.** "Şu hatayı aldım, çöz" yeter.
3. **GitHub Actions kırmızıysa** ilgili run'a tıkla → fail step'in log'unu
   Claude'a ver → fix yapar, push'lar.
4. **AWS'de bir şey bozulursa** SSH'le bağlan, Claude'a `journalctl`
   çıktısını yapıştır → çözüm önerir.
5. **Git'te kafan karışırsa**: `git status` neyin ne durumda olduğunu
   söyler. Aklın hep oraya dönsün.

---

## Hatırla

Sen **tasarımcı + ürün sahibi** rolündesin. Kod yazmıyorsun, **ne istediğini
söylüyorsun**. Kod kalitesi, mimari, test, CI gibi şeyler Claude'un işi —
sen ürün vizyonunu, kullanıcı deneyimini, business kararlarını yönlendir.

Bu repo o vizyonun hafızası. ROADMAP, CHANGELOG ve CLAUDE.md sürekli güncel
tutulmalı; o sayede 6 ay sonra "biz neyi neden yaptık?" sorusuna yine doğru
cevap çıkar.

İyi çalışmalar.
