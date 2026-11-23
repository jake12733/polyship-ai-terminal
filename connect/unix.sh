#!/bin/sh
# DARK CODE - Ollama 원클릭 연결 (macOS / Linux)
# 실행: curl -fsSL https://jake12733.github.io/darkcode-ai/connect/unix.sh | sh
# 하는 일: Ollama 설치 확인/설치 -> 사이트 접속 허용(OLLAMA_ORIGINS) -> 재시작 -> 연결 확인 -> 없는 모델 생성 -> 사이트 열기

SITE="https://jake12733.github.io/darkcode-ai/"
BASE="https://jake12733.github.io/darkcode-ai/models/"
ORIGIN="https://jake12733.github.io"
API="http://127.0.0.1:11434"
BASEMODEL="qwen3:8b"
DC="$HOME/.darkcode"
OS="$(uname -s)"

say()  { printf '\033[32m%s\033[0m\n' "$1"; }
warn() { printf '\033[33m%s\033[0m\n' "$1"; }
err()  { printf '\033[31m%s\033[0m\n' "$1"; }
step() { printf '\n\033[36m[%s/6] %s\033[0m\n' "$1" "$2"; }
api_up() { curl -fsS -m 3 "$API/api/version" >/dev/null 2>&1; }
wait_api() { i=0; while [ $i -lt "$1" ]; do api_up && return 0; sleep 1; i=$((i+1)); done; return 1; }

say "=============================================="
say "   DARK CODE  ::  Ollama 원클릭 연결"
say "=============================================="

step 1 "Ollama 설치 확인"
if ! command -v ollama >/dev/null 2>&1 && [ ! -d "/Applications/Ollama.app" ]; then
  warn "Ollama가 없어 자동으로 설치합니다."
  if [ "$OS" = "Darwin" ]; then
    warn "공식 앱 다운로드 중... (ollama.com)"
    TMPZ="$(mktemp -d)/Ollama.zip"
    if curl -fL --progress-bar https://ollama.com/download/Ollama-darwin.zip -o "$TMPZ" && ditto -x -k "$TMPZ" /Applications; then
      say "OK  /Applications/Ollama.app 설치"
      open -a Ollama; sleep 5
    elif command -v brew >/dev/null 2>&1; then brew install --cask ollama
    else err "자동 설치 실패. https://ollama.com/download 에서 설치 후 다시 실행해 주세요."; open "https://ollama.com/download"; exit 1; fi
  else
    curl -fsSL https://ollama.com/install.sh | sh
  fi
else
  say "이미 설치돼 있어 설치는 건너뜁니다."
fi
OLLAMA="$(command -v ollama || echo /Applications/Ollama.app/Contents/Resources/ollama)"
say "OK  $OLLAMA"

step 2 "사이트 접속 허용 + 3. Ollama 재시작"
if [ "$OS" = "Darwin" ]; then
  CUR="$(launchctl getenv OLLAMA_ORIGINS)"
  case ",$CUR," in *",$ORIGIN,"*) NEW="$CUR" ;; *) NEW="${CUR:+$CUR,}$ORIGIN" ;; esac
  launchctl setenv OLLAMA_ORIGINS "$NEW"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$HOME/Library/LaunchAgents/com.darkcode.ollama-origins.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.darkcode.ollama-origins</string>
<key>ProgramArguments</key><array><string>/bin/launchctl</string><string>setenv</string><string>OLLAMA_ORIGINS</string><string>$NEW</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
EOF
  osascript -e 'quit app "Ollama"' >/dev/null 2>&1; pkill -x ollama >/dev/null 2>&1; sleep 2
  open -a Ollama 2>/dev/null || (OLLAMA_ORIGINS="$NEW" nohup "$OLLAMA" serve >/dev/null 2>&1 &)
elif command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q '^ollama.service'; then
  NEW="$ORIGIN"
  sudo mkdir -p /etc/systemd/system/ollama.service.d
  printf '[Service]\nEnvironment="OLLAMA_ORIGINS=%s"\n' "$NEW" | sudo tee /etc/systemd/system/ollama.service.d/darkcode.conf >/dev/null
  sudo systemctl daemon-reload && sudo systemctl restart ollama
else
  NEW="$ORIGIN"
  pkill -x ollama >/dev/null 2>&1; sleep 1
  OLLAMA_ORIGINS="$NEW" nohup "$OLLAMA" serve >/dev/null 2>&1 &
  grep -q OLLAMA_ORIGINS "$HOME/.profile" 2>/dev/null || echo "export OLLAMA_ORIGINS=\"$NEW\"" >> "$HOME/.profile"
fi
say "OK  OLLAMA_ORIGINS = $NEW"
if wait_api 60; then say "OK  Ollama 실행 중"; else err "Ollama가 켜지지 않았어요. 직접 실행 후 다시 시도해 주세요."; exit 1; fi

step 4 "사이트 연결 확인"
CODE="$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS -H "Origin: $ORIGIN" -H 'Access-Control-Request-Method: POST' "$API/api/tags")"
case "$CODE" in 2*) say "OK  사이트에서 Ollama 호출 허용됨" ;; *) warn "허용 확인 실패 ($CODE). 사이트에서 다시 확인해 보세요." ;; esac

step 5 "DARK CODE 모델 확인"
TAGS="$(curl -fsS "$API/api/tags")"
mkdir -p "$DC/models"
NEED_BASE=1; echo "$TAGS" | grep -q "\"$BASEMODEL\"" && NEED_BASE=0
for m in router music dev media qa critic; do
  if echo "$TAGS" | grep -q "\"ai-$m:latest\""; then say "OK  ai-$m"; continue; fi
  if [ $NEED_BASE -eq 1 ]; then warn "기본 모델 $BASEMODEL 받는 중 (약 5GB, 처음 한 번만)"; "$OLLAMA" pull "$BASEMODEL"; NEED_BASE=0; fi
  curl -fsSL "${BASE}Modelfile.$m" -o "$DC/models/Modelfile.$m" && "$OLLAMA" create "ai-$m" -f "$DC/models/Modelfile.$m" && say "OK  ai-$m 생성"
done

step 6 "사이트 열기"
URL="${SITE}?connected=1"
if [ "$OS" = "Darwin" ]; then open "$URL"; else (xdg-open "$URL" >/dev/null 2>&1 &) ; fi
say "=============================================="
say "   연결 완료! 브라우저에서 DARK CODE가 열립니다."
say "=============================================="
