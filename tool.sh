#!/usr/bin/env bash
FILE="$1"
JOHN_DIR="$HOME/john"
RUN_DIR="$JOHN_DIR/run"

spin() {
  local p=$1 s='|/-\'
  while kill -0 $p 2>/dev/null; do
    for i in {0..3}; do printf "\r[%c] " "${s:$i:1}"; sleep .1; done
  done
  printf "\r"
}

echo "[*] Updating system..."
sudo apt update -y >/dev/null 2>&1 & spin $!
echo "[✔] System updated"

echo "[*] Installing dependencies..."
sudo apt install -y build-essential git perl p7zip-full unrar-free rar unzip libssl-dev zlib1g-dev libbz2-dev >/dev/null 2>&1 & spin $!
echo "[✔] Dependencies ready"

if [ ! -d "$JOHN_DIR" ]; then
  echo "[*] Building John Jumbo..."
  git clone https://github.com/openwall/john "$JOHN_DIR" >/dev/null 2>&1
  cd "$JOHN_DIR/src"
  ./configure >/dev/null 2>&1
  make -sj$(nproc) >/dev/null 2>&1 & spin $!
  echo "[✔] John Jumbo built"
else
  echo "[✔] John Jumbo ready"
fi

[ -z "$FILE" ] || [ ! -f "$FILE" ] && echo "[✖] File not found" && exit 1

OUT="${FILE%.*}.hash"

echo "[*] Extracting hash..."
case "$FILE" in
  *.zip) "$RUN_DIR/zip2john" "$FILE" > "$OUT" ;;
  *.rar) "$RUN_DIR/rar2john" "$FILE" > "$OUT" ;;
  *.7z)  "$RUN_DIR/7z2john"  "$FILE" > "$OUT" ;;
  *) echo "[✖] Unsupported archive"; exit 1 ;;
esac &
spin $!
echo "[✔] Hash saved to $OUT"

HASH_LINE=$(head -n 1 "$OUT")

if echo "$HASH_LINE" | grep -q '\$zip2\$'; then
  MODE=13600
elif echo "$HASH_LINE" | grep -q '\$rar5\$'; then
  MODE=13000
elif echo "$HASH_LINE" | grep -q '\$7z\$'; then
  MODE=11600
else
  echo "[✖] Unable to detect Hashcat mode"
  exit 1
fi

echo
echo "[🔥] Auto‑detected Hashcat mode: $MODE"