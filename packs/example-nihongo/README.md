# Japonca Başlangıç (örnek pack)

Bu, language pack formatının nasıl göründüğünü gösteren minimal bir örnektir.

## Yapı

```
example-nihongo/
├── manifest.json       # Pack tanım kartı
├── lessons/            # Dersler
│   ├── 001-hiragana-aiueo.json
│   └── 002-greetings.json
└── media/
    └── audio/          # Ses dosyaları (bu örnekte boş)
```

## Validate etme

Tüm pack'ler şu schema'lara uymalı:
- `manifest.json` → `schema/manifest.schema.json`
- `lessons/*.json` → `schema/lesson.schema.json`

## Yayınlama

1. Reponu GitHub'a push et
2. Tag oluştur: `git tag v0.1.0 && git push --tags`
3. GitHub'da Releases > Draft a new release > zip yükle (`example-nihongo-0.1.0.zip`)
4. Repo URL'ini uygulamaya ver
