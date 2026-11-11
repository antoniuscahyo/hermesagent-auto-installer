#!/usr/bin/env bash
# =============================================================================
#  Hermes Agent - macOS One-Shot Installer
# =============================================================================
#  Satu script, sekali jalan, selesai:
#    1. Install Hermes Agent (curl resmi install.sh --non-interactive --skip-setup)
#    2. Set default provider + model
#    3. Simpan API key provider ke ~/.hermes/.env
#    4. Simpan Telegram bot token + allowlist + home channel ke ~/.hermes/.env
#    5. Install autostart gateway (launchd ~/Library/LaunchAgents, auto jalan tiap login)
#    6. Smoke test 1x call ke provider + cek status service
#
#  Cara pakai (pilih salah satu):
#
#    A. Zero-prompt (edit blok CFG di bawah, lalu jalankan):
#       chmod +x install-hermes-macos.sh
#       ./install-hermes-macos.sh
#       (atau double-click install-hermes-macos.command)
#
#    B. Satu baris command (tanpa edit file):
#       ./install-hermes-macos.sh \
#         --provider deepseek --model deepseek-v4-flash \
#         --api-key "sk-xxxx" \
#         --telegram-token "123456789:AAxxxx" \
#         --allowed-users "111111111,222222222"
#
#    C. Semi-interaktif (kosongkan API key / token, script nanya):
#       ./install-hermes-macos.sh
#
#  Catatan:
#    - Kompatibel dengan /bin/bash bawaan macOS (Bash 3.2) & Apple Silicon / Intel.
#    - JANGAN jalankan pakai sudo!
#    - Script idempotent (aman dijalankan ulang).
# =============================================================================

set -eo pipefail

# =============================================================================
#  EDIT DI SINI (Blok CFG) jika ingin mode Zero-Prompt
# =============================================================================
CFG_PROVIDER="deepseek"
CFG_MODEL="deepseek-v4-flash"
CFG_BASE_URL=""
CFG_API_MODE=""
CFG_API_KEY=""
CFG_API_KEY_ENV=""
CFG_TELEGRAM_TOKEN=""
CFG_TELEGRAM_ALLOWED_USERS=""
CFG_TELEGRAM_HOME_CHANNEL=""
# =============================================================================

PROVIDER="${CFG_PROVIDER}"
MODEL="${CFG_MODEL}"
BASE_URL="${CFG_BASE_URL}"
API_MODE="${CFG_API_MODE}"
API_KEY="${CFG_API_KEY}"
API_KEY_ENV="${CFG_API_KEY_ENV}"
TELEGRAM_TOKEN="${CFG_TELEGRAM_TOKEN}"
TELEGRAM_ALLOWED_USERS="${CFG_TELEGRAM_ALLOWED_USERS}"
TELEGRAM_HOME_CHANNEL="${CFG_TELEGRAM_HOME_CHANNEL}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
FORCE=0
SKIP_GATEWAY=0
SKIP_SMOKE_TEST=0
SKIP_BROWSER=0
NO_INSTALL=0
UNATTENDED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --provider)       PROVIDER="$2"; shift 2 ;;
    --model)          MODEL="$2"; shift 2 ;;
    --base-url)       BASE_URL="$2"; shift 2 ;;
    --api-mode)       API_MODE="$2"; shift 2 ;;
    --api-key)        API_KEY="$2"; shift 2 ;;
    --api-key-env)    API_KEY_ENV="$2"; shift 2 ;;
    --telegram-token) TELEGRAM_TOKEN="$2"; shift 2 ;;
    --allowed-users)  TELEGRAM_ALLOWED_USERS="$2"; shift 2 ;;
    --home-channel)   TELEGRAM_HOME_CHANNEL="$2"; shift 2 ;;
    --hermes-home)    HERMES_HOME="$2"; shift 2 ;;
    --force)          FORCE=1; shift ;;
    --skip-gateway)   SKIP_GATEWAY=1; shift ;;
    --skip-smoke-test) SKIP_SMOKE_TEST=1; shift ;;
    --skip-browser)   SKIP_BROWSER=1; shift ;;
    --no-install)     NO_INSTALL=1; shift ;;
    --unattended)     UNATTENDED=1; shift ;;
    -h|--help)
      echo "Penggunaan: $0 [options]"
      echo "  --provider <name>        Provider (deepseek, 9router, custom, ollama, vllm, openrouter, dll)"
      echo "  --model <name>           Default model (atau custom model, mis. cc/claude-sonnet-4-5)"
      echo "  --base-url <url>         Endpoint URL (wajib utk 'custom'; default 9router: http://localhost:20128/v1)"
      echo "  --api-mode <mode>        Opsional: chat_completions | anthropic_messages | codex_responses"
      echo "  --api-key <key>          API key provider"
      echo "  --api-key-env <ENV>      Override nama env var untuk API key"
      echo "  --telegram-token <token> Telegram Bot Token dari @BotFather"
      echo "  --allowed-users <ids>    ID Telegram diizinkan (pisah koma jika >1)"
      echo "  --home-channel <id>      Opsional: Telegram home channel ID"
      echo "  --hermes-home <path>     Override HERMES_HOME (default: ~/.hermes)"
      echo "  --force                  Reinstall Hermes walau sudah terpasang"
      echo "  --no-install             Skip tahap install (hanya konfigurasi)"
      echo "  --skip-browser           Skip install Playwright/Chromium"
      echo "  --skip-gateway           Jangan pasang autostart launchd service"
      echo "  --skip-smoke-test        Jangan tes call provider di akhir"
      echo "  --unattended             Nol prompt; nilai kosong dilewati"
      exit 0
      ;;
    *) echo "Opsi tidak dikenal: $1" >&2; exit 1 ;;
  esac
done

# Pastikan Homebrew (Apple Silicon & Intel) dan ~/.local/bin masuk PATH
for p in "/opt/homebrew/bin" "/usr/local/bin" "$HOME/.local/bin"; do
  if [ -d "$p" ]; then
    case ":$PATH:" in
      *":$p:"*) ;;
      *) PATH="$p:$PATH" ;;
    esac
  fi
done
export PATH
export HERMES_HOME

# UI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

write_step() { printf "\n${CYAN}==> %s${NC}\n" "$1"; }
write_ok()   { printf "    ${GREEN}[OK]  %s${NC}\n" "$1"; }
write_note() { printf "    ${GRAY}%s${NC}\n" "$1"; }
write_warn() { printf "    ${YELLOW}[!]   %s${NC}\n" "$1"; }
write_bad()  { printf "    ${RED}[x]   %s${NC}\n" "$1"; }
fail()       { write_bad "$1"; exit 1; }

mask_val() {
  local val="$1"
  if [ -z "$val" ]; then echo "(kosong)"; return; fi
  local len=${#val}
  if [ "$len" -le 8 ]; then echo "****"; return; fi
  local tail_idx=$((len - 4))
  echo "${val:0:4}...${val:$tail_idx:4}"
}

# Cek OS (harus macOS, atau beri warning jelas)
if [ "$(uname -s)" != "Darwin" ]; then
  write_warn "OS terdeteksi $(uname -s), bukan macOS (Darwin)."
  write_note "Untuk Linux gunakan ./install-hermes.sh."
fi

# Cek jangan run as root (sudo)
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo ""
  write_warn "Kamu menjalankan script ini sebagai ROOT (sudo)!"
  write_note "Di macOS, Hermes & launchd LaunchAgent berjalan di user space (~/.hermes)."
  write_note "Jangan pakai sudo agar izin file dan autostart login bekerja normal."
  if [ "$UNATTENDED" -eq 1 ]; then
    fail "Dibatalkan karena berjalan sebagai root di mode --unattended."
  fi
  printf "    Tetap lanjut sebagai root? [y/N]: "
  read -r confirm_root || true
  case "$confirm_root" in
    [Yy]*) ;;
    *) exit 1 ;;
  esac
fi

printf "\n${CYAN}###########################################################\n"
printf "#   HERMES AGENT - macOS AUTO INSTALLER                   #\n"
printf "#   install + provider/model + telegram + launchd         #\n"
printf "###########################################################${NC}\n"

write_step "Target Konfigurasi"
write_note "Arch        : $(uname -m)"
write_note "HERMES_HOME : $HERMES_HOME"

# Resolve custom/router provider alias (Bash 3.2 safe)
PROV_NORM=$(printf '%s' "$PROVIDER" | tr '[:upper:]' '[:lower:]')
EFFECTIVE_PROVIDER="$PROVIDER"
case "$PROV_NORM" in
  9router)  EFFECTIVE_PROVIDER="custom"; [ -z "$BASE_URL" ] && BASE_URL="http://localhost:20128/v1" ;;
  ollama)   EFFECTIVE_PROVIDER="custom"; [ -z "$BASE_URL" ] && BASE_URL="http://localhost:11434/v1" ;;
  vllm)     EFFECTIVE_PROVIDER="custom"; [ -z "$BASE_URL" ] && BASE_URL="http://localhost:8000/v1" ;;
  llamacpp) EFFECTIVE_PROVIDER="custom"; [ -z "$BASE_URL" ] && BASE_URL="http://localhost:8080/v1" ;;
  custom)   EFFECTIVE_PROVIDER="custom" ;;
esac

if [ "$PROV_NORM" != "$(printf '%s' "$EFFECTIVE_PROVIDER" | tr '[:upper:]' '[:lower:]')" ]; then
  write_note "Provider    : $EFFECTIVE_PROVIDER ($PROVIDER)"
else
  write_note "Provider    : $EFFECTIVE_PROVIDER"
fi
[ -n "$BASE_URL" ] && write_note "Base URL    : $BASE_URL"
write_note "Model       : $MODEL"
[ -n "$API_MODE" ] && write_note "API Mode    : $API_MODE"
write_note "API Key     : $(mask_val "$API_KEY")"
write_note "Telegram    : $(mask_val "$TELEGRAM_TOKEN")"
write_note "Allowlist   : ${TELEGRAM_ALLOWED_USERS:-(kosong - SIAPA PUN bisa pakai bot!)}"

# Mapping Env Key Provider (Bash 3.2 safe: pakai tr, bukan ${1,,})
get_provider_env_key() {
  local p
  p=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$p" in
    deepseek)            echo "DEEPSEEK_API_KEY" ;;
    openrouter)          echo "OPENROUTER_API_KEY" ;;
    openai|openai-api)   echo "OPENAI_API_KEY" ;;
    custom|9router|ollama|vllm|llamacpp) echo "OPENAI_API_KEY" ;;
    anthropic)           echo "ANTHROPIC_API_KEY" ;;
    gemini)              echo "GOOGLE_API_KEY" ;;
    zai)                 echo "GLM_API_KEY" ;;
    kimi-coding)         echo "KIMI_API_KEY" ;;
    kimi-coding-cn)      echo "KIMI_CN_API_KEY" ;;
    minimax)             echo "MINIMAX_API_KEY" ;;
    minimax-cn)          echo "MINIMAX_CN_API_KEY" ;;
    xai)                 echo "XAI_API_KEY" ;;
    nvidia)              echo "NVIDIA_API_KEY" ;;
    huggingface)         echo "HF_TOKEN" ;;
    ollama-cloud)        echo "OLLAMA_API_KEY" ;;
    deepinfra)           echo "DEEPINFRA_API_KEY" ;;
    ai-gateway)          echo "AI_GATEWAY_API_KEY" ;;
    kilocode)            echo "KILOCODE_API_KEY" ;;
    xiaomi)              echo "XIAOMI_API_KEY" ;;
    arcee)               echo "ARCEEAI_API_KEY" ;;
    alibaba)             echo "DASHSCOPE_API_KEY" ;;
    gmi)                 echo "GMI_API_KEY" ;;
    opencode-zen)        echo "OPENCODE_ZEN_API_KEY" ;;
    nous-api)            echo "NOUS_API_KEY" ;;
    *)                   echo "" ;;
  esac
}

# Helper Upsert .env (pure Bash 3.2 + atomic temp file: aman di macOS BSD, aman untuk & / $)
set_env_value() {
  local file="$1"
  local key="$2"
  local val="$3"
  local dir
  dir=$(dirname "$file")
  mkdir -p "$dir"
  [ -f "$file" ] || : > "$file"
  chmod 600 "$file" 2>/dev/null || true

  local serialized="$val"
  case "$val" in
    *[[:space:]\"\'\#\$\\]*)
      # Escape backslash and double quote for dotenv
      local esc="$val"
      esc="${esc//\\/\\\\}"
      esc="${esc//\"/\\\"}"
      serialized="\"$esc\""
      ;;
  esac

  local tmp="${file}.tmp.$$"
  local found=0
  local line
  : > "$tmp"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$key="*|"export $key="*|" $key="*)
        if [ "$found" -eq 0 ]; then
          printf '%s=%s\n' "$key" "$serialized" >> "$tmp"
          found=1
        fi
        ;;
      *)
        printf '%s\n' "$line" >> "$tmp"
        ;;
    esac
  done < "$file"

  if [ "$found" -eq 0 ]; then
    printf '%s=%s\n' "$key" "$serialized" >> "$tmp"
  fi

  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$file"
}

# Prompt secrets jika kosong dan tidak unattended
if [ "$EFFECTIVE_PROVIDER" = "custom" ] && [ -z "$BASE_URL" ]; then
  if [ "$UNATTENDED" -eq 0 ]; then
    echo ""
    write_note "Endpoint custom/router butuh Base URL (contoh 9Router: http://localhost:20128/v1)."
    printf "    Base URL endpoint: "
    read -r BASE_URL || true
  fi
  if [ -z "$BASE_URL" ]; then
    fail "Base URL wajib diisi untuk provider 'custom' (mis. --base-url http://localhost:20128/v1)."
  fi
fi

if [ -z "$API_KEY" ] && [ "$UNATTENDED" -eq 0 ]; then
  echo ""
  write_note "API key provider '$PROVIDER' belum diisi. (Enter untuk lewati)"
  printf "    API Key %s: " "$PROVIDER"
  read -r -s API_KEY || true
  echo ""
fi

if [ -z "$TELEGRAM_TOKEN" ] && [ "$SKIP_GATEWAY" -eq 0 ] && [ "$UNATTENDED" -eq 0 ]; then
  echo ""
  write_note "Telegram Bot Token belum diisi (dari @BotFather). (Enter untuk lewati Telegram)"
  printf "    Telegram Token: "
  read -r -s TELEGRAM_TOKEN || true
  echo ""
  if [ -n "$TELEGRAM_TOKEN" ] && [ -z "$TELEGRAM_ALLOWED_USERS" ]; then
    printf "    Allowed Telegram User IDs (pisah koma, Enter = tanpa allowlist): "
    read -r TELEGRAM_ALLOWED_USERS || true
  fi
fi

# =============================================================================
# 1) INSTALL HERMES
# =============================================================================
resolve_hermes_bin() {
  if [ -x "$HERMES_HOME/hermes-agent/venv/bin/hermes" ]; then
    echo "$HERMES_HOME/hermes-agent/venv/bin/hermes"
  elif [ -x "$HOME/.local/bin/hermes" ]; then
    echo "$HOME/.local/bin/hermes"
  elif command -v hermes >/dev/null 2>&1; then
    command -v hermes
  else
    echo ""
  fi
}

HERMES_BIN=$(resolve_hermes_bin)

if [ -z "$HERMES_BIN" ] || [ "$FORCE" -eq 1 ]; then
  if [ "$NO_INSTALL" -eq 1 ]; then
    fail "Hermes belum terpasang dan --no-install aktif. Batalkan."
  fi

  write_step "Mengunduh & Memasang Hermes Agent via Installer Resmi"
  write_note "URL: https://hermes-agent.nousresearch.com/install.sh"

  installer_tmp=$(mktemp /tmp/hermes-install.XXXXXX.sh)
  trap 'rm -f "$installer_tmp"' EXIT
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o "$installer_tmp"

  if [ "$SKIP_BROWSER" -eq 1 ]; then
    bash "$installer_tmp" --non-interactive --skip-setup --skip-browser --hermes-home "$HERMES_HOME"
  else
    bash "$installer_tmp" --non-interactive --skip-setup --hermes-home "$HERMES_HOME"
  fi
  rm -f "$installer_tmp"

  HERMES_BIN=$(resolve_hermes_bin)
  if [ -z "$HERMES_BIN" ] || [ ! -x "$HERMES_BIN" ]; then
    fail "Instalasi selesai tetapi binary 'hermes' tidak ditemukan di ~/.local/bin atau $HERMES_HOME/hermes-agent/venv/bin."
  fi
  write_ok "Hermes Agent terpasang: $HERMES_BIN"
else
  write_step "Hermes Agent sudah terpasang"
  write_ok "$HERMES_BIN"
fi

export PATH="$(dirname "$HERMES_BIN"):$HOME/.local/bin:$PATH"

# =============================================================================
# 2) SET DEFAULT PROVIDER & MODEL
# =============================================================================
write_step "Mengatur default provider & model"
"$HERMES_BIN" config set model.provider "$EFFECTIVE_PROVIDER"
write_ok "model.provider = $EFFECTIVE_PROVIDER"
if [ -n "$BASE_URL" ]; then
  "$HERMES_BIN" config set model.base_url "$BASE_URL"
  write_ok "model.base_url = $BASE_URL"
fi
if [ -n "$MODEL" ]; then
  "$HERMES_BIN" config set model.default "$MODEL"
  write_ok "model.default  = $MODEL"
fi
if [ -n "$API_MODE" ]; then
  "$HERMES_BIN" config set model.api_mode "$API_MODE"
  write_ok "model.api_mode = $API_MODE"
fi

# =============================================================================
# 3) SIMPAN API KEY PROVIDER -> .env
# =============================================================================
ENV_FILE="$HERMES_HOME/.env"
if [ -n "$API_KEY" ]; then
  write_step "Menyimpan API key provider ke $ENV_FILE"
  TARGET_ENV="$API_KEY_ENV"
  if [ -z "$TARGET_ENV" ]; then
    TARGET_ENV=$(get_provider_env_key "$EFFECTIVE_PROVIDER")
  fi
  if [ -z "$TARGET_ENV" ]; then
    fail "Nama env var untuk provider '$PROVIDER' tidak dikenali. Gunakan --api-key-env NAMA_ENV."
  fi
  set_env_value "$ENV_FILE" "$TARGET_ENV" "$API_KEY"
  write_ok "$TARGET_ENV tersimpan"
else
  write_step "API key provider dilewati"
  write_note "Bisa di-set nanti: hermes config set <PROVIDER>_API_KEY <key>"
fi

# =============================================================================
# 4) TELEGRAM
# =============================================================================
if [ -n "$TELEGRAM_TOKEN" ]; then
  write_step "Mengatur bot Telegram"
  if ! printf '%s' "$TELEGRAM_TOKEN" | grep -Eq '^[0-9]+:[A-Za-z0-9_-]{30,}$'; then
    fail "Format bot token Telegram tidak valid! Contoh: 123456789:AA_<token_dari_botfather>"
  fi
  set_env_value "$ENV_FILE" "TELEGRAM_BOT_TOKEN" "$TELEGRAM_TOKEN"
  write_ok "TELEGRAM_BOT_TOKEN tersimpan"

  if [ -n "$TELEGRAM_ALLOWED_USERS" ]; then
    CLEAN_USERS=$(printf '%s' "$TELEGRAM_ALLOWED_USERS" | tr -d '[:space:]')
    if ! printf '%s' "$CLEAN_USERS" | grep -Eq '^-?[0-9]+(,-?[0-9]+)*$'; then
      fail "TELEGRAM_ALLOWED_USERS harus ID numerik dipisah koma (mis. 111111111,222222222)."
    fi
    set_env_value "$ENV_FILE" "TELEGRAM_ALLOWED_USERS" "$CLEAN_USERS"
    write_ok "TELEGRAM_ALLOWED_USERS = $CLEAN_USERS"
  else
    write_warn "TELEGRAM_ALLOWED_USERS kosong! Siapa pun di Telegram bisa chat bot kamu."
    write_note "Cari ID lewat @userinfobot, lalu isi di $ENV_FILE atau ulangi script."
  fi

  if [ -n "$TELEGRAM_HOME_CHANNEL" ]; then
    set_env_value "$ENV_FILE" "TELEGRAM_HOME_CHANNEL" "$TELEGRAM_HOME_CHANNEL"
    write_ok "TELEGRAM_HOME_CHANNEL = $TELEGRAM_HOME_CHANNEL"
  fi
else
  write_step "Telegram dilewati"
  write_note "Bisa diatur nanti: hermes gateway setup"
fi

# =============================================================================
# 5) AUTOSTART GATEWAY (macOS launchd LaunchAgent)
# =============================================================================
if [ "$SKIP_GATEWAY" -eq 0 ]; then
  write_step "Memasang autostart gateway (macOS launchd LaunchAgent)"
  if "$HERMES_BIN" gateway install --force; then
    write_ok "LaunchAgent terpasang di ~/Library/LaunchAgents/"
  else
    write_warn "hermes gateway install gagal. Coba manual: hermes gateway install --force"
  fi

  echo ""
  write_note "---- Status Gateway ----"
  "$HERMES_BIN" gateway status || true
  write_note "------------------------"
else
  write_step "Autostart gateway dilewati (--skip-gateway)"
  write_note "Aktifkan nanti: hermes gateway install --force"
fi

# =============================================================================
# 6) SMOKE TEST
# =============================================================================
if [ "$SKIP_SMOKE_TEST" -eq 0 ] && { [ -n "$API_KEY" ] || [ "$EFFECTIVE_PROVIDER" = "custom" ]; }; then
  write_step "Smoke Test: 1x call ke $EFFECTIVE_PROVIDER"
  if "$HERMES_BIN" chat -q "Reply with exactly: OK" -Q >/dev/null 2>&1; then
    write_ok "Provider merespons - API key & model valid"
  else
    write_warn "Smoke test belum berhasil (tidak fatal). Cek detail: hermes chat -q 'halo'"
  fi
fi

# =============================================================================
# RINGKASAN
# =============================================================================
printf "\n${GREEN}===========================================================\n"
printf "   PEMASANGAN SELESAI (macOS)\n"
printf "===========================================================${NC}\n\n"
echo "   HERMES_HOME : $HERMES_HOME"
echo "   Config      : $HERMES_HOME/config.yaml"
echo "   Secrets     : $ENV_FILE"
echo "   Provider    : $EFFECTIVE_PROVIDER ($MODEL)"
[ -n "$BASE_URL" ] && echo "   Base URL    : $BASE_URL"
if [ -n "$TELEGRAM_TOKEN" ]; then
  echo "   Telegram    : token OK (Allowed Users: ${TELEGRAM_ALLOWED_USERS:-TERBUKA})"
fi
printf "\n${CYAN}Langkah Selanjutnya:${NC}\n"
echo "  1. Buka tab/jendela Terminal baru (atau: source ~/.zshrc)"
echo "  2. Mulai chat di terminal:"
echo "       hermes"
if [ -n "$TELEGRAM_TOKEN" ]; then
  echo "  3. Buka bot kamu di Telegram lalu kirim /start"
  echo "       Cek status  : hermes gateway status"
  echo "       Cek log     : tail -f $HERMES_HOME/logs/gateway.log"
fi
echo "  4. Diagnosa: hermes doctor"
echo ""
echo "  Tips Mac (kalau dipakai server/24 jam, cegah sleep):"
echo "       caffeinate -dimsu &"
echo ""
