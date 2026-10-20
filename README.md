# Hermes Agent — Windows Auto Installer

Satu script, sekali jalan: **install Hermes → set provider + model + API key → pasang Telegram bot → autostart gateway (Scheduled Task)**.

## Isi folder

| File | Fungsi |
|---|---|
| `install-hermes.ps1` | Otak installer. Semua config ada di blok `$CFG` di bagian atas file. |
| `install-hermes.cmd` | Launcher. **Double-click ini** (bypass ExecutionPolicy otomatis). |
| `README.md` | File ini. |

## Cara pakai — zero prompt (rekomendasi)

1. Extract folder ini ke mana saja, mis. `C:\Users\<kamu>\Downloads\hermes-win-installer`.
2. Buka `install-hermes.ps1` pakai Notepad / VS Code, edit blok ini saja:

```powershell
$CFG = @{
    Provider             = "deepseek"                 # provider default
    Model                = "deepseek-v4-flash"        # model default
    ApiKey               = "sk-xxxxxxxxxxxxxxxx"      # API key provider
    TelegramToken        = "123456789:AAxxxxxxxxxxxx" # token dari @BotFather
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
  -TelegramToken "123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxx" `
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
