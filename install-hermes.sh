#!/usr/bin/env bash
# =============================================================================
#  Hermes Agent - Linux One-Shot Installer
# =============================================================================
#  Satu script, sekali jalan:
#    1. Install Hermes Agent (curl resmi install.sh) secara non-interactive
#    2. Set default provider + model
#    3. Simpan API key provider ke ~/.hermes/.env
#    4. Simpan Telegram bot token + allowlist ke ~/.hermes/.env
#    5. Install autostart gateway (systemd --user service + loginctl linger)
#    6. Smoke test 1x call ke provider + cek status service
#
#  Cara pakai (pilih salah satu):
#
#    A. Zero-prompt (edit blok CFG di bawah lalu jalankan):
#       chmod +x install-hermes.sh
#       ./install-hermes.sh
#
#    B. Pakai Argumen / Environment variables:
#       ./install-hermes.sh --provider deepseek --model deepseek-v4-flash \
#                           --api-key "sk-xxxx" \
#                           --telegram-token "123456789:AAxxxx" \
#                           --allowed-users "111111111,222222222"
#
#  Catatan:
#    - JANGAN jalankan sebagai root / sudo!
#    - Autostart dipasang via systemd --user service.
#    - Script ini idempotent (aman dijalankan berulang kali).
# =============================================================================

set -eo pipefail

# =============================================================================
#  EDIT DI SINI (Blok CFG) jika ingin mode Zero-Prompt
# =============================================================================
CFG_PROVIDER="deepseek"
CFG_MODEL="deepseek-v4-flash"
CFG_API_KEY=""
CFG_API_KEY_ENV=""
CFG_TELEGRAM_TOKEN=""
CFG_TELEGRAM_ALLOWED_USERS=""
CFG_TELEGRAM_HOME_CHANNEL=""
# =============================================================================

# Variabel runtime
PROVIDER="${CFG_PROVIDER}"
MODEL="${CFG_MODEL}"
API_KEY="${CFG_API_KEY}"
API_KEY_ENV="${CFG_API_KEY_ENV}"
TELEGRAM_TOKEN="${CFG_TELEGRAM_TOKEN}"
TELEGRAM_ALLOWED_USERS="${CFG_TELEGRAM_ALLOWED_USERS}"
TELEGRAM_HOME_CHANNEL="${CFG_TELEGRAM_HOME_CHANNEL}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
FORCE=0
SKIP_GATEWAY=0
SKIP_SMOKE_TEST=0
UNATTENDED=0

# Parsing argumen CLI
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider) PROVIDER="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --api-key-env) API_KEY_ENV="$2"; shift 2 ;;
    --telegram-token) TELEGRAM_TOKEN="$2"; shift 2 ;;
    --allowed-users) TELEGRAM_ALLOWED_USERS="$2"; shift 2 ;;
    --home-channel) TELEGRAM_HOME_CHANNEL="$2"; shift 2 ;;
    --hermes-home) HERMES_HOME="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --skip-gateway) SKIP_GATEWAY=1; shift ;;
    --skip-smoke-test) SKIP_SMOKE_TEST=1; shift ;;
    --unattended) UNATTENDED=1; shift ;;
    -h|--help)
      echo "Penggunaan: $0 [options]"
      echo "  --provider <name>        Default provider (deepseek, openrouter, anthropic, dll)"
      echo "  --model <name>           Default model"
      echo "  --api-key <key>          API key provider"
      echo "  --telegram-token <token> Telegram Bot Token dari @BotFather"
      echo "  --allowed-users <ids>    ID Telegram diizinkan (koma jika banyak)"
      echo "  --skip-gateway           Jangan pasang autostart systemd service"
      echo "  --skip-smoke-test        Jangan tes call provider di akhir"
      echo "  --unattended             Mode non-interaktif tanpa tanya"
      exit 0
      ;;
    *) echo "Opsi tidak dikenal: $1"; exit 1 ;;
  esac
done

# UI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

write_step() { echo -e "\n${CYAN}==> $1${NC}"; }
write_ok()   { echo -e "    ${GREEN}[OK]  $1${NC}"; }
write_note() { echo -e "    ${GRAY}$1${NC}"; }
write_warn() { echo -e "    ${YELLOW}[!]   $1${NC}"; }
write_bad()  { echo -e "    ${RED}[x]   $1${NC}"; }
fail()       { write_bad "$1"; exit 1; }

mask_val() {
  local val="$1"
  if [[ -z "$val" ]]; then echo "(kosong)"; return; fi
  local len=${#val}
  if [[ $len -le 8 ]]; then echo "****"; return; fi
  echo "${val:0:4}...${val: -4}"
}

# Cek jangan run as root
if [[ "$EUID" -eq 0 ]]; then
  echo ""
  write_warn "Kamu menjalankan script ini sebagai ROOT (sudo)!"
  write_note "Hermes di Linux berjalan di user space (~/.hermes)."
  write_note "Menjalankan sebagai root akan merusak izin file & autostart systemd user."
  read -r -p "Tetap lanjut sebagai root? [y/N]: " confirm_root || true
  if [[ ! "$confirm_root" =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo -e "\n${CYAN}###########################################################"
echo -e "#   HERMES AGENT - LINUX AUTO INSTALLER                   #"
echo -e "#   install + provider/model + telegram + autostart       #"
echo -e "###########################################################${NC}"

write_step "Target Konfigurasi"
write_note "HERMES_HOME : $HERMES_HOME"
write_note "Provider    : $PROVIDER"
write_note "Model       : $MODEL"
write_note "API Key     : $(mask_val "$API_KEY")"
write_note "Telegram    : $(mask_val "$TELEGRAM_TOKEN")"
write_note "Allowlist   : ${TELEGRAM_ALLOWED_USERS:-(TERBUKA UNTUK SIAPA PUN)}"

# Mapping Env Key Provider
get_provider_env_key() {
  local p="${1,,}"
  case "$p" in
    deepseek) echo "DEEPSEEK_API_KEY" ;;
    openrouter) echo "OPENROUTER_API_KEY" ;;
    openai|openai-api) echo "OPENAI_API_KEY" ;;
    anthropic) echo "ANTHROPIC_API_KEY" ;;
    gemini) echo "GOOGLE_API_KEY" ;;
    zai) echo "GLM_API_KEY" ;;
    kimi-coding) echo "KIMI_API_KEY" ;;
    kimi-coding-cn) echo "KIMI_CN_API_KEY" ;;
    minimax) echo "MINIMAX_API_KEY" ;;
    minimax-cn) echo "MINIMAX_CN_API_KEY" ;;
    xai) echo "XAI_API_KEY" ;;
    nvidia) echo "NVIDIA_API_KEY" ;;
    huggingface) echo "HF_TOKEN" ;;
    ollama-cloud) echo "OLLAMA_API_KEY" ;;
    deepinfra) echo "DEEPINFRA_API_KEY" ;;
    ai-gateway) echo "AI_GATEWAY_API_KEY" ;;
    kilocode) echo "KILOCODE_API_KEY" ;;
    xiaomi) echo "XIAOMI_API_KEY" ;;
    arcee) echo "ARCEEAI_API_KEY" ;;
    alibaba) echo "DASHSCOPE_API_KEY" ;;
    gmi) echo "GMI_API_KEY" ;;
    opencode-zen) echo "OPENCODE_ZEN_API_KEY" ;;
    nous-api) echo "NOUS_API_KEY" ;;
    *) echo "" ;;
  esac
}

# Helper Upsert .env
set_env_value() {
  local file="$1"
  local key="$2"
  local val="$3"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  chmod 600 "$file" 2>/dev/null || true

  # Quote jika value mengandung spasi/karakter khusus
  local serialized="$val"
  if [[ "$val" =~ [[:space:]\"\'#$\\\r\n] ]]; then
    serialized="\"${val//\"/\\\"}\""
  fi

  if grep -q -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file"; then
    sed -i -E "s|^[[:space:]]*(export[[:space:]]+)?${key}=.*|${key}=${serialized}|" "$file"
  else
    echo "${key}=${serialized}" >> "$file"
  fi
}

# Prompt rahasia jika kosong dan bukan unattended
if [[ -z "$API_KEY" && $UNATTENDED -eq 0 ]]; then
  echo ""
  write_note "API key provider '$PROVIDER' belum diisi. (Enter untuk lewati)"
  read -r -s -p "    API Key: " API_KEY || true
  echo ""
fi

if [[ -z "$TELEGRAM_TOKEN" && $SKIP_GATEWAY -eq 0 && $UNATTENDED -eq 0 ]]; then
  echo ""
  write_note "Telegram Bot Token belum diisi (dari @BotFather). (Enter untuk lewati Telegram)"
  read -r -s -p "    Telegram Token: " TELEGRAM_TOKEN || true
  echo ""
  if [[ -n "$TELEGRAM_TOKEN" && -z "$TELEGRAM_ALLOWED_USERS" ]]; then
    read -r -p "    Allowed Telegram User IDs (koma jika banyak, Enter untuk lewati): " TELEGRAM_ALLOWED_USERS || true
  fi
fi

# =============================================================================
# 1) INSTALL HERMES
# =============================================================================
HERMES_BIN="$HOME/.local/bin/hermes"
if [[ ! -x "$HERMES_BIN" && -x "$HERMES_HOME/hermes-agent/venv/bin/hermes" ]]; then
  HERMES_BIN="$HERMES_HOME/hermes-agent/venv/bin/hermes"
fi

if [[ ! -x "$HERMES_BIN" || $FORCE -eq 1 ]]; then
  write_step "Mengunduh & Memasang Hermes Agent via Installer Resmi"
  write_note "URL: https://hermes-agent.nousresearch.com/install.sh"
  
  export NONINTERACTIVE=1
  export SKIP_SETUP=1
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  
  if [[ -x "$HOME/.local/bin/hermes" ]]; then
    HERMES_BIN="$HOME/.local/bin/hermes"
  elif [[ -x "$HERMES_HOME/hermes-agent/venv/bin/hermes" ]]; then
    HERMES_BIN="$HERMES_HOME/hermes-agent/venv/bin/hermes"
  fi

  if [[ ! -x "$HERMES_BIN" ]]; then
    fail "Pemasangan Hermes selesai tetapi binary 'hermes' tidak ditemukan!"
  fi
  write_ok "Hermes Agent berhasil terpasang: $HERMES_BIN"
else
  write_step "Hermes Agent sudah terpasang"
  write_ok "$HERMES_BIN"
fi

# Pastikan path masuk ke session saat ini
export PATH="$HOME/.local/bin:$HERMES_HOME/hermes-agent/venv/bin:$PATH"

# =============================================================================
# 2) SET DEFAULT PROVIDER & MODEL
# =============================================================================
write_step "Mengatur default provider & model"
"$HERMES_BIN" config set model.provider "$PROVIDER"
write_ok "model.provider = $PROVIDER"
if [[ -n "$MODEL" ]]; then
  "$HERMES_BIN" config set model.default "$MODEL"
  write_ok "model.default  = $MODEL"
fi

# =============================================================================
# 3) SIMPAN API KEY PROVIDER
# =============================================================================
ENV_FILE="$HERMES_HOME/.env"
if [[ -n "$API_KEY" ]]; then
  write_step "Menyimpan API Key provider ke $ENV_FILE"
  TARGET_ENV="$API_KEY_ENV"
  if [[ -z "$TARGET_ENV" ]]; then
    TARGET_ENV=$(get_provider_env_key "$PROVIDER")
  fi
  if [[ -z "$TARGET_ENV" ]]; then
    fail "Nama env var untuk provider '$PROVIDER' tidak dikenali. Gunakan --api-key-env NAMA_ENV."
  fi
  set_env_value "$ENV_FILE" "$TARGET_ENV" "$API_KEY"
  write_ok "$TARGET_ENV berhasil disimpan"
else
  write_step "API key provider dilewati"
fi

# =============================================================================
# 4) TELEGRAM
# =============================================================================
if [[ -n "$TELEGRAM_TOKEN" ]]; then
  write_step "Mengatur bot Telegram"
  if [[ ! "$TELEGRAM_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]]; then
    fail "Format bot token Telegram tidak valid! Contoh format: 123456789:ABCdefGHI-jklMNOpqrSTUvwxYZ"
  fi
  set_env_value "$ENV_FILE" "TELEGRAM_BOT_TOKEN" "$TELEGRAM_TOKEN"
  write_ok "TELEGRAM_BOT_TOKEN berhasil disimpan"

  if [[ -n "$TELEGRAM_ALLOWED_USERS" ]]; then
    CLEAN_USERS=$(echo "$TELEGRAM_ALLOWED_USERS" | tr -d ' ')
    set_env_value "$ENV_FILE" "TELEGRAM_ALLOWED_USERS" "$CLEAN_USERS"
    write_ok "TELEGRAM_ALLOWED_USERS = $CLEAN_USERS"
  else
    write_warn "TELEGRAM_ALLOWED_USERS kosong! Bot dapat diakses oleh siapa saja di Telegram."
  fi

  if [[ -n "$TELEGRAM_HOME_CHANNEL" ]]; then
    set_env_value "$ENV_FILE" "TELEGRAM_HOME_CHANNEL" "$TELEGRAM_HOME_CHANNEL"
    write_ok "TELEGRAM_HOME_CHANNEL = $TELEGRAM_HOME_CHANNEL"
  fi
fi

# =============================================================================
# 5) AUTOSTART GATEWAY (systemd --user service)
# =============================================================================
if [[ $SKIP_GATEWAY -eq 0 ]]; then
  write_step "Memasang Autostart Background Gateway (systemd --user)"
  
  if command -v systemctl >/dev/null 2>&1; then
    # Pasang service via CLI Hermes
    "$HERMES_BIN" gateway install --force --start-now --start-on-login || {
      write_warn "Gagal memasang service via 'hermes gateway install'."
    }
    write_ok "Service gateway terdaftar di systemd user"

    # Aktifkan linger agar background service tetap jalan saat terminal SSH logout
    if command -v loginctl >/dev/null 2>&1; then
      write_note "Mengaktifkan lingering pengguna via loginctl (agar gateway tetap aktif setelah logout)..."
      loginctl enable-linger "$USER" 2>/dev/null || {
        write_warn "Tidak dapat mengaktifkan linger otomatis. Jika service mati saat logout SSH, jalankan: sudo loginctl enable-linger $USER"
      }
    fi
  else
    write_warn "systemctl tidak ditemukan (non-systemd distro / container). Gateway autostart dilewati."
  fi
  
  echo ""
  write_note "---- Status Gateway ----"
  "$HERMES_BIN" gateway status || true
  write_note "------------------------"
fi

# =============================================================================
# 6) SMOKE TEST
# =============================================================================
if [[ $SKIP_SMOKE_TEST -eq 0 && -n "$API_KEY" ]]; then
  write_step "Smoke Test: 1x Test Call ke $PROVIDER"
  if "$HERMES_BIN" chat -q "Reply with exactly: OK" -Q >/dev/null 2>&1; then
    write_ok "Inference berhasil! Provider & API Key aktif."
  else
    write_warn "Test call tidak mengembalikan 0 (mungkin limit, koneksi, atau saldo). Cek detail dengan: hermes chat -q 'halo'"
  fi
fi

# =============================================================================
# SELESAI
# =============================================================================
echo -e "\n${GREEN}==========================================================="
echo -e "   PEMASANGAN SELESAI"
echo -e "===========================================================${NC}\n"
echo -e "   HERMES_HOME : $HERMES_HOME"
echo -e "   Config      : $HERMES_HOME/config.yaml"
echo -e "   Secrets     : $ENV_FILE"
echo -e "   Provider    : $PROVIDER ($MODEL)"
if [[ -n "$TELEGRAM_TOKEN" ]]; then
  echo -e "   Telegram    : Bot Token OK (Allowed Users: ${TELEGRAM_ALLOWED_USERS:-TERBUKA})"
fi
echo -e "\n${CYAN}Langkah Selanjutnya:${NC}"
echo -e "  1. Muat ulang PATH atau buka terminal baru:"
echo -e "     source ~/.bashrc  (atau source ~/.zshrc)"
echo -e "  2. Mulai chat di terminal:"
echo -e "     hermes"
if [[ -n "$TELEGRAM_TOKEN" ]]; then
  echo -e "  3. Buka bot kamu di Telegram dan ketik: /start"
  echo -e "     Cek status service : hermes gateway status"
  echo -e "     Cek log gateway    : tail -f $HERMES_HOME/logs/gateway.log"
fi
echo -e "  4. Cek kesehatan sistem: hermes doctor\n"
