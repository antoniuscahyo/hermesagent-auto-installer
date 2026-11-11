# Hermes Agent — One-Shot Auto Installer (Windows, Linux & macOS)

Satu script, sekali jalan: **install Hermes → set provider + model + API key → pasang Telegram bot → autostart gateway**.

## File Installer

| OS | File | Cara Jalankan |
|---|---|---|
| **Windows** | `install-hermes.cmd` / `install-hermes.ps1` | Double-click `install-hermes.cmd` atau via PowerShell |
| **Linux** | `install-hermes.sh` | `./install-hermes.sh` |
| **macOS** | `install-hermes-macos.sh` / `install-hermes-macos.command` | `./install-hermes-macos.sh` atau double-click `.command` |

---

## 0. Persiapan: Bikin Bot Token & Ambil User ID di Telegram

Sebelum menjalankan installer, siapkan 2 hal dari Telegram: **Bot Token** dan **User ID** (supaya cuma kamu yang bisa chat ke bot).

### A. Bikin Bot & Ambil Bot Token (`@BotFather`)
1. Buka aplikasi Telegram, cari **`@BotFather`** (yang ada centang biru resmi Telegram).
2. Klik **Start** atau kirim pesan:
   ```text
   /newbot
   ```
3. **Nama tampilan bot** (bebas, contoh: `Hermes Assistant`).
4. **Username bot** (harus unik dan **wajib diakhiri `bot`**, contoh: `cahyo_hermes_bot`).
5. Jika berhasil, `@BotFather` akan membalas pesan berisi **HTTP API token** dengan format angka + huruf, contoh:
   ```text
   123456789:AA_<token_dari_botfather>
   ```
6. **Copy token tersebut** → masukkan ke `TelegramToken` / `--telegram-token`.

> **Catatan keamanan:** Jangan share Bot Token ke orang lain atau commit ke repo publik. Kalau terlanjur bocor, kirim `/revoke` ke `@BotFather` untuk generate token baru.

### B. Ambil User ID Telegram (`@userinfobot`) — Sangat Disarankan
Tanpa `TELEGRAM_ALLOWED_USERS`, **siapa pun** yang menemukan username bot kamu di Telegram bisa memakai Hermes (dan menghabiskan kuota API kamu).
1. Cari **`@userinfobot`** di Telegram, lalu klik **Start** (atau kirim `/start`).
2. Bot akan membalas info akun kamu, lihat bagian **`Id`**, contoh:
   ```text
   Id: 123456789
   ```
3. Copy angka tersebut → masukkan ke `TelegramAllowedUsers` / `--allowed-users`.
   - Kalau lebih dari 1 orang, pisahkan pakai koma tanpa spasi: `123456789,987654321`.

### C. Opsional: Ambil Home Channel / Group ID (`TELEGRAM_HOME_CHANNEL`)
Cuma perlu kalau kamu mau cron job / notifikasi otomatis masuk ke grup atau chat tertentu:
- Untuk **DM pribadi** ke kamu sendiri: langsung pakai angka **User ID** dari langkah B (`123456789`).
- Untuk **Grup Telegram**: masukkan bot ke grup, jadikan admin (atau matikan Group Privacy di `@BotFather` → `/setprivacy` → Disable), kirim `/set-home` di grup setelah Hermes jalan — atau cek ID grup (biasanya diawali `-100...`).

---

## 1. Versi macOS (Apple Silicon & Intel)

### Cara Cepat (Zero-Prompt)
1. Clone repo ini:
   ```bash
   git clone https://github.com/antoniuscahyo/hermesagent-auto-installer.git
   cd hermesagent-auto-installer
   ```
2. Edit blok `CFG_` di bagian atas `install-hermes-macos.sh`:
   ```bash
   CFG_PROVIDER="deepseek"
   CFG_MODEL="deepseek-v4-flash"
   CFG_API_KEY="sk-xxxx"
   CFG_TELEGRAM_TOKEN="123456789:AAxxxx"
   CFG_TELEGRAM_ALLOWED_USERS="111111111"
   ```
3. Jalankan:
   ```bash
   chmod +x install-hermes-macos.sh install-hermes-macos.command
   ./install-hermes-macos.sh
   ```
   (Atau double-click `install-hermes-macos.command` dari Finder.)

### Atau via Satu Baris Command
```bash
./install-hermes-macos.sh --provider deepseek --model deepseek-v4-flash \
  --api-key "sk-xxxx" \
  --telegram-token "123456789:AAxxxx" \
  --allowed-users "111111111"
```

> **PENTING DI macOS:**
> - **JANGAN pakai `sudo`!** Hermes & service `launchd` berjalan di user space (`~/.hermes`).
> - Autostart dipasang ke `~/Library/LaunchAgents/ai.hermes.gateway.plist` (`RunAtLoad` + `KeepAlive`) dan langsung aktif.
> - Kompatibel dengan `/bin/bash` bawaan macOS (Bash 3.2) serta PATH Homebrew (`/opt/homebrew/bin` & `/usr/local/bin`).

---

## 2. Versi Linux (Ubuntu / Debian / RHEL / Arch / dll)

### Cara Cepat (Zero-Prompt)
1. Download / clone repo ini:
   ```bash
   git clone https://github.com/antoniuscahyo/hermesagent-auto-installer.git
   cd hermesagent-auto-installer
   ```
2. Buka `install-hermes.sh` dengan nano / text editor, isi konfigurasi di bagian atas:
   ```bash
   CFG_PROVIDER="deepseek"
   CFG_MODEL="deepseek-v4-flash"
   CFG_API_KEY="sk-xxxx"
   CFG_TELEGRAM_TOKEN="123456789:AAxxxx"
   CFG_TELEGRAM_ALLOWED_USERS="111111111"
   ```
3. Beri izin eksekusi lalu jalankan:
   ```bash
   chmod +x install-hermes.sh
   ./install-hermes.sh
   ```

### Atau via Satu Baris Command
```bash
./install-hermes.sh --provider deepseek --model deepseek-v4-flash \
  --api-key "sk-xxxx" \
  --telegram-token "123456789:AAxxxx" \
  --allowed-users "111111111"
```

> **PENTING DI LINUX:**
> - **JANGAN jalankan pakai `sudo`!** Hermes berjalan di user space (`~/.hermes`).
> - Script otomatis memasang autostart via **systemd user service** (`systemctl --user`).
> - Script juga otomatis menjalankan `loginctl enable-linger $USER` agar bot Telegram tetap menyala di background meskipun Anda disconnect / logout dari SSH.

---

## 3. Versi Windows

1. Extract folder ini ke mana saja, mis. `C:\Users\<kamu>\Downloads\hermes-win-installer`.
2. Buka `install-hermes.ps1` pakai Notepad / VS Code, edit blok ini saja:

```powershell
$CFG = @{
    Provider             = "deepseek"                 # provider default
    Model                = "deepseek-v4-flash"        # model default
    ApiKey               = "sk-xxxxxxxxxxxxxxxx"      # API key provider
    TelegramToken        = "123456789:AA_<token_dari_botfather>" # token dari @BotFather
    TelegramAllowedUsers = "111111111"                # ID Telegram kamu (pisah koma kalau >1)
    TelegramHomeChannel  = ""                         # opsional
}
```

3. Simpan, lalu **double-click `install-hermes.cmd`**. Selesai — sisanya otomatis.

> Simpan file dalam keadaan UTF-8 **tanpa BOM** (Notepad Windows 11 default sudah benar; kalau pakai Notepad lama pilih "UTF-8" bukan "UTF-8 with BOM"). BOM bikin config.yaml rusak.

## Cara pakai — satu baris PowerShell (tanpa edit file)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-hermes.ps1 `
  -Provider deepseek -Model deepseek-v4-flash `
  -ApiKey "sk-xxxxxxxx" `
  -TelegramToken "123456789:AA_<token_dari_botfather>" `
  -TelegramAllowedUsers "111111111,222222222"
```

Kalau `-ApiKey` / `-TelegramToken` dikosongkan, script akan **bertanya** (input token disensor).

## Yang dilakukan script

1. Cek `HERMES_HOME` (`%LOCALAPPDATA%\hermes` default) dan apakah `hermes.exe` sudah ada.
2. Kalau belum ada → download `https://hermes-agent.nousresearch.com/install.ps1` lalu jalankan mode `-NonInteractive` (uv + Python + Git + Node + clone repo + venv + deps, 5–15 menit).
3. `hermes config set model.provider <provider>` dan `hermes config set model.default <model>`.
4. Tulis API key ke `%HERMES_HOME%\.env` (nama env var otomatis per provider, mis. `DEEPSEEK_API_KEY`, `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, …).
5. Tulis `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, `TELEGRAM_HOME_CHANNEL` ke `.env`.
6. `hermes gateway install --force --start-now --start-on-login` → Windows **Scheduled Task** per-user (fallback: shortcut di folder Startup kalau task diblokir kebijakan kantor).
7. Smoke test 1x call ke provider (`hermes chat -q ...`), lalu tampilkan `hermes gateway status`.

## Sesudah selesai

```powershell
# buka PowerShell BARU (PATH perlu refresh)
hermes                      # chat di terminal
hermes doctor               # diagnosa
hermes gateway status       # cek service autostart
Get-Content "$env:LOCALAPPDATA\hermes\logs\gateway.log" -Tail 50 -Wait
```

Di Telegram: cari bot kamu → `/start`.

Cek autostart benar-benar terdaftar:

```powershell
Get-ScheduledTask | Where-Object TaskName -like "*ermes*" | Format-Table TaskName, State
```

## Flag

| Flag | Efek |
|---|---|
| `-Force` | Reinstall Hermes walau sudah terpasang |
| `-SkipGateway` | Jangan pasang autostart gateway |
| `-SkipSmokeTest` | Jangan tes call provider di akhir |
| `-NoInstall` | Jangan install; hanya konfigurasi (untuk Hermes yang sudah ada) |
| `-Unattended` | Nol prompt; kalau ada nilai kosong → langkah itu dilewati, bukan ditanya |
| `-HermesHome <path>` | Override `HERMES_HOME` |
| `-ApiKeyEnv <NAME>` | Paksa nama env var untuk API key (provider yang tidak ada di tabel) |

## Pitfalls

- **Jangan run as Administrator.** Scheduled Task dan `HERMES_HOME` dibuat per-user; kalau elevated, task bisa nempel ke profil admin.
- **Token Telegram harus format `123456789:AA...`** — script menolak format lain sebelum menulis apa pun.
- **`TELEGRAM_ALLOWED_USERS` kosong = bot terbuka untuk siapa pun.** Isi ID numerik kamu (ambil dari `@userinfobot`).
- **`hermes config set TELEGRAM_ALLOWED_USERS ...` lewat CLI akan salah tempat** (masuk `config.yaml` sebagai key tak dikenal). Script ini menulis langsung ke `.env`, jadi aman.
- Script **idempotent** — boleh dijalankan ulang, `.env` di-upsert (tidak dobel).
- Log: `%LOCALAPPDATA%\hermes\logs\install-win-<timestamp>.log`. Secret yang ikut ke-capture otomatis di-redact.
- Antivirus/Defender kadang memblokir `powershell -File` dari file hasil download: klik kanan file → **Properties → Unblock**, atau `Unblock-File .\install-hermes.ps1`.

## Ganti provider/model belakangan

```powershell
hermes config set model.provider openrouter
hermes config set model.default anthropic/claude-sonnet-4.5
hermes config set OPENROUTER_API_KEY sk-or-xxxx     # otomatis masuk .env
hermes gateway restart
```

## Uninstall autostart / Hermes

```powershell
hermes gateway uninstall      # hapus Scheduled Task
hermes uninstall              # hapus Hermes (opsional)
```

---

## 3b. Pakai 9Router / Custom Model / Endpoint Lainnya

Semua installer (Windows, Linux, macOS) mendukung endpoint OpenAI-compatible seperti **9Router**, **Ollama**, **vLLM**, **llama.cpp**, **LiteLLM**, atau proxy custom lain.

| Nilai `Provider` | Efek otomatis | Default `BaseUrl` (jika dikosongkan) |
|---|---|---|
| `9router` | Set `model.provider = custom` | `http://localhost:20128/v1` |
| `ollama` | Set `model.provider = custom` | `http://localhost:11434/v1` |
| `vllm` | Set `model.provider = custom` | `http://localhost:8000/v1` |
| `llamacpp` | Set `model.provider = custom` | `http://localhost:8080/v1` |
| `custom` | Set `model.provider = custom` | Wajib isi `--base-url` / `-BaseUrl` |

API key (jika endpoint pakai auth) otomatis disimpan sebagai `OPENAI_API_KEY` di `.env`. Jika endpoint lokal tanpa auth, kosongkan saja API key-nya.

### Contoh 9Router (macOS / Linux)
```bash
./install-hermes-macos.sh \
  --provider 9router \
  --base-url "http://localhost:20128/v1" \
  --model "cc/claude-sonnet-4-5" \
  --api-key "sk-9router-xxxx" \
  --telegram-token "123456789:AAxxxx" \
  --allowed-users "111111111"
```
*(Untuk Linux ganti script menjadi `./install-hermes.sh`.)*

### Contoh 9Router / Custom Proxy (Windows PowerShell)
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-hermes.ps1 `
  -Provider 9router `
  -BaseUrl "http://localhost:20128/v1" `
  -Model "cx/gpt-5.3-codex" `
  -ApiKey "sk-9router-xxxx" `
  -TelegramToken "123456789:AAxxxx" `
  -TelegramAllowedUsers "111111111"
```

### Contoh Endpoint Custom Remote (mis. LiteLLM / CLIProxy / API kompatibel OpenAI)
- **macOS / Linux:** `--provider custom --base-url "https://proxy-anda.example.com/v1" --model "nama-model-anda" --api-key "sk-xxxx"`
- **Windows:** `-Provider custom -BaseUrl "https://proxy-anda.example.com/v1" -Model "nama-model-anda" -ApiKey "sk-xxxx"`
- Opsional tambah `--api-mode` / `-ApiMode` (`chat_completions`, `anthropic_messages`, `codex_responses`) jika proxy tidak auto-detect.

---

## 4. Panduan Saat Proses Install Berjalan Sampai Selesai

Berikut apa yang akan tampil di layar dari awal sampai bot Telegram siap dipakai. Total durasi install awal sekitar **5–15 menit** tergantung kecepatan internet.

### Tahap 1 — Target Konfigurasi (0–5 detik)
- Script mencetak ringkasan: `HERMES_HOME`, `Provider`, `Model`, dan versi tersensor (`sk-x...xxxx`) untuk `API Key` dan `Telegram Token`.
- **Jika API key / Telegram token masih kosong** dan tidak memakai flag unattended: script akan meminta input sekali (ketik/paste lalu Enter; input disensor).
- **Kalau salah ketik token Telegram** (tidak sesuai format `123456789:AA...`), script langsung berhenti sebelum menulis file apa pun.

### Tahap 2 — Download & Pasang Hermes Agent (5–15 menit)
- Script mengecek apakah `hermes` sudah terpasang. Jika sudah ada, tahap ini langsung di-skip (kecuali pakai flag `--force` / `-Force`).
- Jika belum ada, installer resmi berjalan otomatis tanpa wizard:
  1. Menyiapkan `uv`, Python 3.11, Git, Node.js, `ripgrep`, dan `ffmpeg`.
  2. Clone repository `hermes-agent` dan membuat virtual environment (`venv`).
  3. Install paket Python + dependensi Node/TUI + Chromium/Playwright untuk browser tool.
- **Kelihatan diam agak lama?** Bagian `Installing Python dependencies` dan download Chromium memang paling lama (bisa 3–8 menit) tanpa banyak baris output — tunggu sampai lanjut, **jangan di-close**.
- **Khusus Linux jika macet di error `zygote` / `Broken pipe (32)`:**
  Tekan `Ctrl + C`, lalu jalankan:
  ```bash
  mkdir -p ~/.hermes
  echo 'AGENT_BROWSER_ARGS="--no-sandbox,--disable-dev-shm-usage,--disable-gpu"' >> ~/.hermes/.env
  ./install-hermes.sh
  ```
  (atau jalankan ulang dengan `--skip-browser`).

### Tahap 3 — Konfigurasi Provider, Model, API Key, & Telegram (5–10 detik)
- Output normal:
  - `[OK]  model.provider = deepseek`
  - `[OK]  model.default  = deepseek-v4-flash`
  - `[OK]  DEEPSEEK_API_KEY tersimpan`
  - `[OK]  TELEGRAM_BOT_TOKEN tersimpan`
  - `[OK]  TELEGRAM_ALLOWED_USERS = ...`
- **Peringatan kuning `[!] TELEGRAM_ALLOWED_USERS kosong`:** artinya siapa pun yang menemukan bot Telegram Anda bisa memakainya. Sangat disarankan isi ID numerik dari `@userinfobot`.

### Tahap 4 — Pasang Autostart Gateway & Status (5–15 detik)
- Script otomatis mendaftarkan service background supaya gateway menyala otomatis setiap login/boot dan langsung di-start:
  - **macOS:** `launchd` LaunchAgent di `~/Library/LaunchAgents/ai.hermes.gateway.plist`.
  - **Linux:** `systemd --user` service + `loginctl enable-linger $USER` (tetap hidup walau SSH ditutup).
  - **Windows:** Task Scheduler per-user (fallback ke folder Startup jika diblokir kebijakan kantor).
- Di layar muncul blok `Status Gateway` (`hermes gateway status`). Pastikan statusnya aktif/running.

### Tahap 5 — Smoke Test & Ringkasan Selesai (5–20 detik)
- Script mengirim 1 pesan tes (`Reply with exactly: OK`) ke provider untuk membuktikan API key dan model benar-benar valid:
  - `[OK]  Provider merespons - API key & model valid` → konfigurasi inference beres.
  - Jika muncul `[!]` (mis. saldo provider habis / koneksi lambat), instalasi tetap lanjut; cek ulang nanti dengan `hermes chat -q "halo"`.
- Setelah muncul banner **SELESAI** / **PEMASANGAN SELESAI**:

### Langkah Verifikasi Setelah Selesai
1. **Buka terminal / PowerShell BARU** (supaya `PATH` baru terbaca).
2. Cek perintah dasar:
   ```bash
   hermes --version
   hermes doctor
   hermes gateway status
   ```
3. **Tes di Telegram:** buka bot Anda di aplikasi Telegram → klik **Start** / kirim `/start` → kirim pesan biasa (`halo`).
   - Jika bot tidak membalas:
     - Pastikan ID Telegram Anda sudah masuk di `TELEGRAM_ALLOWED_USERS` (atau cek log):
       - **macOS / Linux:** `tail -f ~/.hermes/logs/gateway.log`
       - **Windows:** `Get-Content "$env:LOCALAPPDATA\hermes\logs\gateway.log" -Tail 50 -Wait`
4. **Cek autostart per OS:**
   - **macOS:** `launchctl list | grep hermes`
   - **Linux:** `systemctl --user status hermes-gateway`
   - **Windows:** `Get-ScheduledTask | Where-Object TaskName -like "*ermes*"`

