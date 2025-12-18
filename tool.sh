#!/usr/bin/env bash
set -e

FILE="$1"
WORKDIR="$(pwd)"
JOHN="/opt/john"
RUN="$JOHN/run"

if [ -z "$FILE" ]; then
  echo "[✖] Usage: sudo ./tool.sh <archive>"
  exit 1
fi

if [ ! -f "$FILE" ]; then
  echo "[✖] File not found"
  exit 1
fi

echo "[*] Installing deps..."
apt update -y >/dev/null
apt install -y git build-essential python3 perl p7zip-full rar unzip hashcat libssl-dev zlib1g-dev >/dev/null
echo "[✔] Deps ready"

if [ -d "$JOHN/run" ]; then
  echo "[✔] John already built"
else
  echo "[*] Building John Jumbo..."
  rm -rf "$JOHN"
  git clone https://github.com/openwall/john "$JOHN" >/dev/null
  cd "$JOHN/src"
  ./configure >/dev/null
  make -sj$(nproc) >/dev/null
  cd "$WORKDIR"
  echo "[✔] John ready"
fi

EXT="${FILE##*.}"
OUT="${FILE}.hash"

echo "[*] Extracting hash..."

case "$EXT" in
  zip)
    "$RUN/zip2john" "$FILE" | sed -n 's/.*\(\$zip2\$.*\$\).*/\1/p' > "$OUT"
    MODE=13600
    ;;
  rar)
    "$RUN/rar2john" "$FILE" > "$OUT"
    MODE=13000
    ;;
  7z)
    "$RUN/7z2john" "$FILE" > "$OUT"
    MODE=11600
    ;;
  *)
    echo "[✖] Unsupported archive type"
    exit 1
    ;;
esac

if [ ! -s "$OUT" ]; then
  echo "[✖] Hash extraction failed"
  exit 1
fi

echo "[✔] Hash extracted to $OUT"
echo
echo "Choose bruteforce mode:"
echo "1) Numbers"
echo "2) Lowercase"
echo "3) Uppercase"
echo "4) Lower + Upper"
echo "5) Custom hashcat args"
read -p "> " CHOICE

case "$CHOICE" in
  1) MASK="?d?d?d?d?d?d?d?d" ;;
  2) MASK="?l?l?l?l?l?l?l?l" ;;
  3) MASK="?u?u?u?u?u?u?u?u" ;;
  4) MASK="?l?l?l?l?l?l?l?l" ;;
  5)
     read -p "Enter full hashcat args: " CUSTOM
     hashcat $CUSTOM "$OUT"
     exit 0
     ;;
  *)
     echo "[✖] Invalid option"
     exit 1
     ;;
esac

echo "[🔥] Running Hashcat"
echo "Mode: $MODE"
hashcat -m "$MODE" "$OUT" -a 3 "$MASK"
