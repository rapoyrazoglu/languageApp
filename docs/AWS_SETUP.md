# AWS Setup Runbook

Bu doküman backend'i AWS'de **tek EC2 + RDS + S3** mimarisiyle ayağa kaldırmak
için adım adım rehberdir. Free tier YOK varsayımı ile yazıldı; aylık maliyet
~$32 (eu-central-1, Frankfurt).

> **Mimari özet**: bir EC2 (t4g.small) Caddy + Docker container çalıştırır,
> Postgres RDS'te (private subnet), pack zip'leri S3'te. ALB yok — Caddy
> Let's Encrypt ile TLS yapar. Secrets Manager parolaları taşır, EC2'ye
> attach edilen IAM role ile kod sızdırılmadan erişilir.
>
> **ALB neden yok**: ALB sadece var olduğu için ~$16.20/ay yer. Tek instance'da
> Caddy aynı işi (TLS termination + health check) bedavaya yapar. SAA için
> ALB'yi sınava bir hafta kala bir hafta için ayağa kaldırıp test edersin
> (~$0.50), sonra silersin.

## Maliyet beklentisi

| Bileşen | Aylık |
|---|---:|
| EC2 t4g.small (on-demand) | $12.27 |
| RDS Postgres db.t4g.micro single-AZ | $13.14 |
| RDS 20GB gp3 + 7d backup | $2.30 |
| KMS CMK | $1.00 |
| Secrets Manager × 3 | $1.20 |
| Route53 hosted zone | $0.50 |
| CloudWatch Logs (~1 GB) | $0.50 |
| S3 + transfer (düşük trafik) | $1.00 |
| **Toplam** | **~$31.91** |

Domain'in maliyeti ayrı (.com Route53'te ~$13/yıl).

---

## 0. Ön hazırlık (10 dk)

1. AWS hesabı aç (root e-mail + güçlü parola).
2. Root user'da **MFA aktif et**: AWS Console → sağ üstte hesap adı → Security
   credentials → MFA → virtual MFA app (Authy/1Password).
3. **IAM user yarat**: IAM → Users → Create user
   - Name: `ata` (kendi adın)
   - Provide access to AWS Management Console: **on**
   - Attach policies directly → `AdministratorAccess`
   - User'a giriş yap, **MFA aç**.
4. Bu noktadan sonra **root'u asla kullanma** — günlük IAM user'la.
5. **Billing alarm kur**:
   - Billing and Cost Management → Budgets → Create budget
   - Use a template → Monthly cost budget
   - Amount: **$40**
   - Email: kendi mailini gir
   - Save. Limit yaklaşınca uyarı alırsın.

> **Kritik**: AWS faturası **fiyatlandırma değişikliği yapmadan** birden bine
> çıkabilir (örn. yanlışlıkla NAT Gateway aç, multi-AZ RDS aç, vb). Budget
> alarm'ı setup'ın **ilk işi**.

## 1. Region seçimi

Console üst sağdan **Europe (Frankfurt) eu-central-1** seç. Sebep:
- KVKK için EU region
- TR'den latency düşük (~30 ms)
- Sonraki tüm adımlarda **aynı region'da kal**.

## 2. VPC kur

VPC = senin AWS'teki sanal ağın. Public subnet (internet'e açık) + private
subnet (sadece içeriden) ayrımı bizim güvenlik temelimiz.

**VPC Console** → Your VPCs → **Create VPC**:
- Resources to create: **VPC and more** seç
- Name auto-generation: `langapp`
- IPv4 CIDR: `10.0.0.0/16`
- IPv6: No
- Tenancy: Default
- **Number of AZs: 2**
- **Public subnets: 2**
- **Private subnets: 2**
- **NAT gateways: None** (NAT Gateway $32/ay yer; MVP'de gereksiz)
- VPC endpoints: **None**
- DNS options: ikisi de açık

**Create VPC** — ~1 dk sürer.

Sonuç:
- 1 VPC: `10.0.0.0/16`
- 2 public subnet: `10.0.0.0/20`, `10.0.16.0/20` (internet gateway'e bağlı)
- 2 private subnet: `10.0.128.0/20`, `10.0.144.0/20` (DB için)

> **Pitfall**: NAT Gateway varsayılan olarak "1 per AZ" gelir, $64/ay yer.
> "None" seçtiğinden emin ol.

## 3. SSH key pair

EC2 Console → **Key Pairs** (sol menü Network & Security altında) → **Create
key pair**:
- Name: `langapp-key`
- Type: **ED25519**
- Format: `.pem`
- Create — `.pem` dosyası otomatik iner.

Yerel makinede:
```bash
mv ~/Downloads/langapp-key.pem ~/.ssh/
chmod 600 ~/.ssh/langapp-key.pem
```

## 4. Security Groups

İki SG yaratacağız: web (EC2) ve db (RDS). RDS sadece web SG'sinden trafik
kabul edecek.

### 4.1 `langapp-web-sg`

VPC Console → Security Groups → **Create security group**:
- Name: `langapp-web-sg`
- Description: "EC2 inbound"
- VPC: `langapp-vpc`
- **Inbound rules**:
  - SSH (22) | Source: **My IP** (kendi IP'in otomatik gelir)
  - HTTP (80) | Source: `0.0.0.0/0` (Caddy'nin Let's Encrypt challenge'ı için)
  - HTTPS (443) | Source: `0.0.0.0/0`
- Outbound: default (all)
- Create.

### 4.2 `langapp-db-sg`

- Name: `langapp-db-sg`
- Description: "RDS inbound from web only"
- VPC: `langapp-vpc`
- **Inbound rules**:
  - PostgreSQL (5432) | Source: **`langapp-web-sg`** (custom → yazmaya başla, dropdown'dan SG'yi seç)
- Outbound: default
- Create.

> **Pitfall**: SSH'i `0.0.0.0/0`'a açma. "My IP" seç. Mobil bağlantın değişirse
> SG'yi güncelle.

## 5. KMS key (RDS encryption için)

KMS Console → Customer managed keys → **Create key**:
- Type: Symmetric
- Usage: Encrypt and decrypt
- Advanced: tüm default
- **Alias**: `langapp-rds`
- Description: "RDS encryption-at-rest"
- Key administrators: kendi IAM user'ın
- Key users: kendi IAM user'ın (RDS otomatik kullanım izni alacak)
- Finish.

ARN'i not et: `arn:aws:kms:eu-central-1:<account>:key/<key-id>`. Sonra
IAM policy'sinde lazım.

## 6. RDS subnet group

RDS Console → **Subnet groups** → Create:
- Name: `langapp-db-subnets`
- Description: "Private subnets for RDS"
- VPC: `langapp-vpc`
- Availability Zones: `eu-central-1a`, `eu-central-1b` (ya da hangi 2 AZ varsa)
- Subnets: **2 private subnet** seç (`10.0.128.0/20`, `10.0.144.0/20`)
- Create.

## 7. RDS Postgres

RDS Console → Databases → **Create database**:

**Engine**:
- Standard create
- PostgreSQL
- Version: 16.x (en son)

**Templates**: **Production** (Free tier seçme — etkin değil zaten)

**Settings**:
- DB instance identifier: `langapp-db`
- Master username: `langapp`
- Credentials management: **Self managed**
- Master password: `openssl rand -base64 24` çıktısını kullan, **bir yere kaydet**
  (sonra Secrets Manager'a koyacağız, sonra unutabilirsin)

**Instance**:
- DB instance class: **Burstable classes** → `db.t4g.micro`

**Storage**:
- Storage type: **gp3**
- Allocated storage: **20** GiB
- **Storage autoscaling: KAPAT** (sürpriz fatura olmasın; ileride elle açarsın)

**Availability & durability**:
- Multi-AZ deployment: **Single DB instance** (Multi-AZ +$13/ay daha)

**Connectivity**:
- VPC: `langapp-vpc`
- DB subnet group: `langapp-db-subnets`
- **Public access: No**
- VPC security group: existing, sadece `langapp-db-sg` seç (default'u kaldır)
- Availability Zone: no preference
- Database port: 5432

**Authentication**: Password authentication

**Encryption**:
- Enable encryption: **on**
- KMS key: `langapp-rds`

**Additional configuration** (genişlet):
- Initial database name: `langapp`
- DB parameter group: default
- Backup: enabled, retention **7 days**, window 03:00 UTC
- **Performance Insights: KAPAT** (saatlik ücret var)
- Monitoring: Enhanced monitoring **kapat** (saatlik ücret)
- Log exports: Postgres log → CloudWatch (boyut küçük, faydalı)
- Maintenance: minor version auto-upgrade ON, window 04:00 UTC Sun
- Deletion protection: **on** (kazara silmeyi önler)

**Create database** — ~5 dk sürer (yeşil "Available" görene kadar bekle).

Hazır olunca **Endpoint** URL'ini kopyala:
`langapp-db.xxxxxxxxxxxx.eu-central-1.rds.amazonaws.com`

## 8. Secrets Manager

Üç secret yaratacağız.

### 8.1 `langapp/db`

Secrets Manager Console → **Store a new secret**:
- Type: **Other type of secret**
- Key/value (json olarak):
  ```json
  {
    "username": "langapp",
    "password": "<az önceki RDS master password>",
    "host": "<RDS endpoint>",
    "port": 5432,
    "dbname": "langapp"
  }
  ```
- Encryption key: `aws/secretsmanager` (default)
- Secret name: `langapp/db`
- Description: "Postgres master credentials"
- Auto-rotation: **Disable** (MVP'de manuel)
- Store.

### 8.2 `langapp/jwt`

Aynı akış:
- Secret değeri (yerelde üret):
  ```bash
  echo "{\"secret\": \"$(openssl rand -base64 48)\"}"
  ```
- Bu JSON'u key/value olarak yapıştır.
- Name: `langapp/jwt`

### 8.3 `langapp/gemini`

- Google AI Studio'dan Gemini API key al
- JSON: `{"apiKey": "<gemini key>"}`
- Name: `langapp/gemini`

## 9. S3 bucket

S3 Console → **Create bucket**:
- AWS Region: eu-central-1
- Bucket name: `langapp-packs-<rastgele 6 karakter>` (global unique olmalı)
- ACLs: disabled
- **Block all public access: ON** (bizde presigned URL var; bucket asla public olmayacak)
- Versioning: **Disable** (MVP'de versiyon DB tarafında)
- Default encryption: **SSE-S3** (default, bedava)
- Bucket key: enabled
- Create.

Bucket ARN'ini not et: `arn:aws:s3:::langapp-packs-xxxxxx`

## 10. EC2 IAM role (instance profile)

Bu role EC2'ye attach edildiğinde **instance üzerindeki kod statik AWS
credential olmadan** Secrets Manager + S3 + KMS'e erişebilir. SAA'da
"least-privilege IAM role" konusunun pratiği.

IAM Console → Roles → **Create role**:
- Trusted entity type: **AWS service**
- Use case: **EC2**
- Next.

**Permissions**: hiçbir managed policy seçme. **Create role** dedikten sonra
policy'i inline ekleyeceğiz.

- Role name: `langapp-ec2-role`
- Create role.

Şimdi role'a tıkla → **Add permissions → Create inline policy**:
- JSON sekmesine geç, aşağıyı yapıştır (ARN'leri seninkiyle değiştir):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadOwnSecrets",
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": [
        "arn:aws:secretsmanager:eu-central-1:<ACCOUNT>:secret:langapp/db-*",
        "arn:aws:secretsmanager:eu-central-1:<ACCOUNT>:secret:langapp/jwt-*",
        "arn:aws:secretsmanager:eu-central-1:<ACCOUNT>:secret:langapp/gemini-*"
      ]
    },
    {
      "Sid": "PackBucketRW",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::langapp-packs-xxxxxx",
        "arn:aws:s3:::langapp-packs-xxxxxx/*"
      ]
    },
    {
      "Sid": "DecryptRDSKey",
      "Effect": "Allow",
      "Action": ["kms:Decrypt"],
      "Resource": "arn:aws:kms:eu-central-1:<ACCOUNT>:key/<langapp-rds-key-id>"
    },
    {
      "Sid": "WriteCloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:CreateLogGroup",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:eu-central-1:<ACCOUNT>:*"
    }
  ]
}
```

Policy name: `langapp-ec2-policy` → Create.

> `<ACCOUNT>` = 12-haneli AWS account ID (Console sağ üstten kopyalanır).
> `langapp-packs-xxxxxx` = senin bucket name'in.

## 11. EC2 instance launch

EC2 Console → Instances → **Launch instances**:
- Name: `langapp-api`
- AMI: **Amazon Linux 2023 (64-bit Arm)** — ARM, t4g serisiyle uyumlu
- Instance type: **t4g.small** (2 vCPU burst, 2 GB RAM)
- Key pair: `langapp-key`
- Network settings → **Edit**:
  - VPC: `langapp-vpc`
  - Subnet: bir **public** subnet seç (`langapp-subnet-public1`)
  - Auto-assign public IP: **Enable**
  - Firewall: select existing, `langapp-web-sg`
- Storage: 20 GB **gp3** (default 8 GB Docker image için yetmez)
- Advanced details:
  - **IAM instance profile**: `langapp-ec2-role`
  - User data (boot script):
    ```bash
    #!/bin/bash
    set -euo pipefail
    dnf update -y
    dnf install -y docker jq
    systemctl enable --now docker
    usermod -a -G docker ec2-user

    # Caddy (CoreOS reposu)
    cat > /etc/yum.repos.d/caddy.repo <<'EOF'
    [caddy]
    name=Caddy
    baseurl=https://download.copr.fedorainfracloud.org/results/@caddy/caddy/fedora-39-aarch64/
    enabled=1
    gpgcheck=1
    gpgkey=https://download.copr.fedorainfracloud.org/results/@caddy/caddy/pubkey.gpg
    EOF
    dnf install -y caddy || {
      # Fallback: binary indir
      curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=arm64" -o /usr/local/bin/caddy
      chmod +x /usr/local/bin/caddy
      useradd -r -s /bin/false caddy || true
    }
    ```
- Launch instance.

## 12. Elastic IP

EC2 Console → Elastic IPs → **Allocate Elastic IP address** → Allocate.

Sonra: Actions → **Associate Elastic IP address** → Resource type: Instance →
`langapp-api` seç → Associate.

> **Önemli**: Elastic IP **instance'a attach edildiği sürece bedava**. Detach
> ya da unattached durumda saatte $0.005 (~$3.65/ay) yer. Eğer instance'ı
> sileceksen Elastic IP'yi de Release et.

IP'yi not et: örn. `3.120.45.67`.

## 13. Domain (opsiyonel ama önerilir)

İki yol:

**A. Route53'te domain kayıt** (en kolay): Route53 → Registered domains →
Register → `<adın>.com` ~$13/yıl. Otomatik hosted zone yaratılır.

**B. Mevcut domainin var**: Route53 → Hosted zones → Create hosted zone:
- Domain: `langapp.example.com`
- Type: Public
- Create.
- Verilen 4 NS kaydını domain registrar'ında (GoDaddy, Cloudflare vs.)
  domain'in name server'ı olarak yapıştır.

**A kayıt ekle**:
- Route53 → Hosted zones → senin zone → Create record
- Record name: `api`
- Type: A
- Value: `<Elastic IP>`
- TTL: 300
- Create.

Bekleme süresi: 5–10 dk DNS yayılımı.

> Domain yoksa şimdilik Caddy'i sadece IP üzerinden plain HTTP'de bırakırsın,
> TLS olmaz. Production için domain şart.

## 14. SSH bağlan ve uygulamayı kur

```bash
ssh -i ~/.ssh/langapp-key.pem ec2-user@<elastic-ip>
```

İlk doğrulama:
```bash
# IAM role çalışıyor mu?
aws sts get-caller-identity --region eu-central-1
# çıktıda "arn:aws:sts::<account>:assumed-role/langapp-ec2-role/i-xxxx" görmelisin

# Secret okuyabiliyor muyuz?
aws secretsmanager get-secret-value --secret-id langapp/db --region eu-central-1 --query SecretString --output text
# JSON çıkmalı

# RDS'e bağlantı testi (psql container ile)
sudo docker run --rm -it postgres:16-alpine psql \
  "postgres://langapp:<password>@<RDS-endpoint>:5432/langapp?sslmode=require" \
  -c "SELECT version();"
# Postgres versiyonu yazmalı
```

### 14.1 Migration çalıştır

```bash
DB_JSON=$(aws secretsmanager get-secret-value --secret-id langapp/db --region eu-central-1 --query SecretString --output text)
DB_URL="postgres://$(echo $DB_JSON|jq -r .username):$(echo $DB_JSON|jq -r .password)@$(echo $DB_JSON|jq -r .host):$(echo $DB_JSON|jq -r .port)/$(echo $DB_JSON|jq -r .dbname)?sslmode=require"

sudo docker run --rm \
  -e DATABASE_URL="$DB_URL" \
  ghcr.io/<owner>/languageapp-migrate:latest
# "OK   00001_init.sql ..." çıktıları
```

### 14.2 Secret-fetch script

```bash
sudo tee /usr/local/bin/langapp-fetch-secrets > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
mkdir -p /run/langapp
chmod 700 /run/langapp

REGION=eu-central-1
DB=$(aws secretsmanager get-secret-value --secret-id langapp/db --region $REGION --query SecretString --output text)
JWT=$(aws secretsmanager get-secret-value --secret-id langapp/jwt --region $REGION --query SecretString --output text)
GEM=$(aws secretsmanager get-secret-value --secret-id langapp/gemini --region $REGION --query SecretString --output text)

cat > /run/langapp/env <<INNER
DATABASE_URL=postgres://$(echo $DB|jq -r .username):$(echo $DB|jq -r .password)@$(echo $DB|jq -r .host):$(echo $DB|jq -r .port)/$(echo $DB|jq -r .dbname)?sslmode=require
JWT_SECRET=$(echo $JWT|jq -r .secret)
GEMINI_API_KEY=$(echo $GEM|jq -r .apiKey)
HTTP_ADDR=:8080
S3_REGION=$REGION
S3_BUCKET=langapp-packs-xxxxxx
S3_USE_PATH_STYLE=false
RATE_LIMIT_ANON_PER_MIN=60
RATE_LIMIT_USER_PER_MIN=600
INNER
chmod 600 /run/langapp/env
EOF
sudo chmod +x /usr/local/bin/langapp-fetch-secrets
sudo /usr/local/bin/langapp-fetch-secrets
sudo cat /run/langapp/env  # gözden geçir, değerler dolu mu
```

> Bucket name'i kendine göre düzelt. `S3_ENDPOINT`, `S3_ACCESS_KEY`,
> `S3_SECRET_KEY` AWS'de **set edilmez** — boş bırakılınca SDK IAM role'den
> otomatik credential alır, default S3 endpoint'ine konuşur.

### 14.3 systemd unit

```bash
sudo tee /etc/systemd/system/langapp.service > /dev/null <<'EOF'
[Unit]
Description=Language app backend
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/usr/local/bin/langapp-fetch-secrets
ExecStartPre=-/usr/bin/docker stop langapp-api
ExecStartPre=-/usr/bin/docker rm langapp-api
ExecStart=/usr/bin/docker run --rm --name langapp-api \
  --env-file /run/langapp/env \
  -p 127.0.0.1:8080:8080 \
  ghcr.io/<owner>/languageapp-backend:latest
ExecStop=/usr/bin/docker stop langapp-api
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now langapp
sudo systemctl status langapp
sudo journalctl -u langapp -f   # logları izle
```

### 14.4 Caddy reverse proxy

```bash
sudo tee /etc/caddy/Caddyfile > /dev/null <<'EOF'
api.langapp.example.com {
  reverse_proxy 127.0.0.1:8080
  encode gzip
  log {
    output file /var/log/caddy/access.log {
      roll_size 10MiB
      roll_keep 5
    }
    format json
  }
}
EOF

sudo mkdir -p /var/log/caddy
sudo systemctl enable --now caddy
sudo systemctl status caddy
```

Caddy ilk istekte Let's Encrypt'ten sertifika alır. Domain'in DNS'i Elastic
IP'ye işaret etmiyorsa burada takılır. Önce DNS'i `dig api.langapp.example.com`
ile doğrula.

## 15. Smoke test

```bash
curl https://api.langapp.example.com/healthz
# {"status":"ok"}

# Register
curl -X POST https://api.langapp.example.com/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"correct horse battery staple"}'
# token + user JSON
```

## 16. CloudWatch alarms

CloudWatch Console → Alarms → Create alarm:

**Alarm 1: RDS CPU yüksek**
- Metric: RDS / Per-Database / CPUUtilization → langapp-db
- Threshold: > 80% for 10 dakika
- Notification: SNS topic yarat → kendi mailini ekle (confirmation maili gelir, onayla)

**Alarm 2: EC2 status check fail**
- Metric: EC2 / Per-Instance / StatusCheckFailed → langapp-api
- Threshold: > 0 for 5 dakika
- Aynı SNS topic.

**Alarm 3: RDS storage düşük**
- Metric: RDS / FreeStorageSpace
- Threshold: < 5 GB

## 17. Backup test (RDS snapshot)

RDS Console → Snapshots → Take snapshot → langapp-db → Name: `langapp-test-1`
→ Take snapshot.

Tamamlanınca: Actions → Restore snapshot → instance class: db.t4g.micro,
identifier: `langapp-db-test-restore` → Restore.

5 dk içinde yeni RDS instance gelir, içinde aynı veri olduğunu doğrula, sonra
**sil** (saatlik ücretten kaçınmak için).

---

## Sorun giderme

| Belirti | Neden / Çözüm |
|---|---|
| `aws sts get-caller-identity` hata veriyor | IAM role attach edilmemiş — EC2 → Actions → Security → Modify IAM role |
| RDS'e bağlanamıyor | Web SG db SG'ye eklenmemiş; ya da RDS public access açık değil ve sen public subnet'te değilsin |
| Caddy "challenge failed" | DNS henüz yayılmadı; `dig` ile doğrula. Ya da port 80 SG'de kapalı |
| `langapp.service` start olmuyor | `journalctl -u langapp` — secret JSON'u eksik / yanlış parse edilmiş olabilir |
| Pack upload "no such bucket" | bucket name `.env`'de yanlış, ya da IAM policy bucket ARN'i farklı |
| Pack upload TLS hatası RDS'e | `sslmode=require` URL'de var mı? |

## Sonraki adımlar

1. **Audit + AI**: Phase 3 başlayınca Gemini proxy'yi `internal/ai/` altına ekleyeceğiz, secret zaten hazır.
2. **Backup automation**: 7 günlük RDS auto-backup yetiyor; aylık manuel snapshot eklemek istersen Lambda + EventBridge.
3. **Monitoring**: CloudWatch dashboards (RDS CPU, EC2 RAM, request count).
4. **WAF / CloudFront**: trafik artınca Caddy önüne CloudFront koy, edge cache + DDoS koruması.
5. **ALB**: SAA pratiği için bir hafta ALB ayağa kaldır + ACM sertifika + target group test, sonra teardown.
