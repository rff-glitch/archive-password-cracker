#!/usr/bin/env bash
set -e

FILE="$1"
WORKDIR="$(pwd)"
JOHN="/opt/john"
RUN="$JOHN/run"
SESSION_NAME="archive_crack_$(date +%s)"
RESTORE_FILE="hashcat_restore_${SESSION_NAME}.restore"

if [ -z "$FILE" ]; then
  echo "[✖] Usage: sudo ./tool.sh <archive>"
  echo "     Optional: sudo ./tool.sh <archive> --resume   (to resume previous session)"
  echo "               sudo ./tool.sh <archive> --stop     (to stop current session)"
  exit 1
fi

if [ ! -f "$FILE" ]; then
  echo "[✖] File not found"
  exit 1
fi

# Check for resume or stop flags
if [ "$2" = "--resume" ] || [ "$2" = "-r" ]; then
  RESUME_MODE=true
  echo "[*] Attempting to resume previous session..."
elif [ "$2" = "--stop" ] || [ "$2" = "-s" ]; then
  STOP_MODE=true
  echo "[*] Looking for session to stop..."
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

# If in stop mode, find and stop hashcat
if [ "$STOP_MODE" = true ]; then
  echo "[*] Checking for running hashcat sessions..."
  
  # Method 1: Check for hashcat processes
  HC_PIDS=$(pgrep -f "hashcat.*$(basename "$OUT")" || true)
  
  if [ -n "$HC_PIDS" ]; then
    echo "[*] Found hashcat PIDs: $HC_PIDS"
    echo "[*] Sending SIGINT to stop gracefully..."
    kill -SIGINT $HC_PIDS 2>/dev/null || true
    sleep 2
    
    # Force kill if still running
    if pgrep -f "hashcat.*$(basename "$OUT")" >/dev/null; then
      echo "[*] Sending SIGTERM..."
      pkill -f "hashcat.*$(basename "$OUT")" 2>/dev/null || true
      sleep 1
    fi
    
    echo "[✔] Hashcat stopped"
  else
    echo "[!] No running hashcat sessions found for this file"
    
    # Check for restore files
    RESTORE_FILES=$(find . -name "hashcat_restore_*.restore" -o -name "*.restore" 2>/dev/null | head -5)
    if [ -n "$RESTORE_FILES" ]; then
      echo "[!] Found restore files. You can delete them manually:"
      echo "$RESTORE_FILES"
    fi
  fi
  exit 0
fi

# If hash file doesn't exist or we're not resuming, extract it
if [ ! -f "$OUT" ] || [ "$RESUME_MODE" != true ]; then
  echo "[*] Extracting hash..."
  
  case "$EXT" in
    zip)
      # Extract only the hash line starting with $zip2$
      "$RUN/zip2john" "$FILE" | grep -o '\$zip2\$[^:]*' > "$OUT"
      MODE=13600
      ;;
    rar)
      # Extract only the hash line (format: filename:$RAR3$...)
      "$RUN/rar2john" "$FILE" | cut -d: -f2- > "$OUT"
      MODE=13000
      ;;
    7z)
      # Extract only the hash line (format: filename:$7z$...)
      "$RUN/7z2john" "$FILE" | cut -d: -f2- > "$OUT"
      MODE=11600
      ;;
    *)
      echo "[✖] Unsupported archive type"
      exit 1
      ;;
  esac

  # Clean up: remove empty lines and ensure proper format
  sed -i '/^$/d' "$OUT"
  sed -i 's/^\s*//;s/\s*$//' "$OUT"

  if [ ! -s "$OUT" ]; then
    echo "[✖] Hash extraction failed"
    exit 1
  fi
fi

echo "[✔] Hash file ready: $OUT"
echo "Hash content:"
cat "$OUT"
echo

# If resuming, skip setup and directly resume
if [ "$RESUME_MODE" = true ]; then
  # Look for restore files
  RESTORE_FILES=$(find . -name "*.restore" 2>/dev/null | head -1)
  
  if [ -z "$RESTORE_FILES" ]; then
    echo "[✖] No restore file found!"
    echo "[!] Available restore files:"
    find . -name "*.restore" 2>/dev/null || echo "    None found"
    exit 1
  fi
  
  RESTORE_FILE=$(echo "$RESTORE_FILES" | head -1)
  echo "[*] Resuming from: $RESTORE_FILE"
  
  # Try to determine mode from restore file or ask user
  if [ -z "$MODE" ]; then
    read -p "Enter hashcat mode (or press Enter to auto-detect): " USER_MODE
    if [ -n "$USER_MODE" ]; then
      MODE="$USER_MODE"
    else
      # Try to guess from file extension
      case "$EXT" in
        zip) MODE=13600 ;;
        rar) MODE=13000 ;;
        7z) MODE=11600 ;;
        *)
          echo "[✖] Cannot auto-detect mode. Please specify with --resume <mode>"
          exit 1
          ;;
      esac
    fi
  fi
  
  echo "[🔥] Resuming Hashcat attack..."
  echo "Mode: $MODE"
  echo "Restore file: $RESTORE_FILE"
  hashcat --restore --restore-file-path "$RESTORE_FILE" || \
    hashcat -m "$MODE" "$OUT" --session "$SESSION_NAME" --restore --restore-file-path "$RESTORE_FILE"
  exit 0
fi

# Normal mode - ask for attack parameters
echo "Choose bruteforce mode:"
echo "1) Numbers (0-9)"
echo "2) Lowercase letters (a-z)"
echo "3) Uppercase letters (A-Z)"
echo "4) Lower + Upper letters (a-z, A-Z)"
echo "5) Alphanumeric (a-z, A-Z, 0-9)"
echo "6) All printable characters"
echo "7) Custom hashcat mask"
echo "8) Custom hashcat args"
read -p "> " CHOICE

# Ask for password length
read -p "Minimum password length [default: 1]: " MIN_LEN
MIN_LEN=${MIN_LEN:-1}

read -p "Maximum password length [default: 8]: " MAX_LEN
MAX_LEN=${MAX_LEN:-8}

# Validate length inputs
if ! [[ "$MIN_LEN" =~ ^[0-9]+$ ]] || ! [[ "$MAX_LEN" =~ ^[0-9]+$ ]]; then
  echo "[✖] Invalid length. Using defaults (1-8)."
  MIN_LEN=1
  MAX_LEN=8
fi

if [ "$MIN_LEN" -gt "$MAX_LEN" ]; then
  echo "[✖] Minimum length cannot be greater than maximum. Swapping values."
  TEMP=$MIN_LEN
  MIN_LEN=$MAX_LEN
  MAX_LEN=$TEMP
fi

echo "Password length range: $MIN_LEN - $MAX_LEN characters"

case "$CHOICE" in
  1) 
    CHARSET="?d"
    DESC="Numbers (0-9)"
    ;;
  2) 
    CHARSET="?l"
    DESC="Lowercase letters (a-z)"
    ;;
  3) 
    CHARSET="?u"
    DESC="Uppercase letters (A-Z)"
    ;;
  4) 
    CHARSET="?l?u"
    DESC="Lower + Upper letters (a-z, A-Z)"
    ;;
  5) 
    CHARSET="?l?u?d"
    DESC="Alphanumeric (a-z, A-Z, 0-9)"
    ;;
  6) 
    CHARSET="?a"
    DESC="All printable characters"
    ;;
  7)
    read -p "Enter custom hashcat mask (e.g., ?l?l?d?d?s): " CUSTOM_MASK
    echo "[🔥] Running Hashcat with custom mask"
    echo "Mode: $MODE"
    echo "Mask: $CUSTOM_MASK"
    echo "Hash file: $OUT"
    echo "Session: $SESSION_NAME"
    echo
    echo "[💡] To pause/resume:"
    echo "  - Press Ctrl+C once to pause"
    echo "  - Resume with: sudo ./tool.sh '$FILE' --resume"
    echo "  - Stop with: sudo ./tool.sh '$FILE' --stop"
    echo
    
    hashcat -m "$MODE" "$OUT" -a 3 "$CUSTOM_MASK" --session "$SESSION_NAME" \
      --increment --increment-min "$MIN_LEN" --increment-max "$MAX_LEN" \
      --restore-file-path "$RESTORE_FILE"
    exit 0
    ;;
  8)
    read -p "Enter full hashcat args: " CUSTOM_ARGS
    echo "[*] Starting hashcat with custom args..."
    echo "[💡] Tip: Add '--session $SESSION_NAME' to enable resume feature"
    hashcat $CUSTOM_ARGS "$OUT"
    exit 0
    ;;
  *)
    echo "[✖] Invalid option"
    exit 1
    ;;
esac

# Generate mask based on length range
if [ "$MIN_LEN" -eq "$MAX_LEN" ]; then
  # Fixed length
  MASK=$(printf "$CHARSET%.0s" $(seq 1 "$MAX_LEN"))
  echo "[🔥] Running Hashcat (fixed length: $MAX_LEN)"
  echo "Mode: $MODE"
  echo "Charset: $DESC"
  echo "Length: $MAX_LEN characters"
  echo "Hash file: $OUT"
  echo "Session: $SESSION_NAME"
else
  # Variable length using increment
  # Create mask for maximum length
  MAX_MASK=$(printf "$CHARSET%.0s" $(seq 1 "$MAX_LEN"))
  
  echo "[🔥] Running Hashcat (variable length: $MIN_LEN-$MAX_LEN)"
  echo "Mode: $MODE"
  echo "Charset: $DESC"
  echo "Length range: $MIN_LEN - $MAX_LEN characters"
  echo "Hash file: $OUT"
  echo "Session: $SESSION_NAME"
fi

echo
echo "[💡] Controls:"
echo "  - Press Ctrl+C once to pause (creates restore point)"
echo "  - Resume with: sudo ./tool.sh '$FILE' --resume"
echo "  - Stop with: sudo ./tool.sh '$FILE' --stop"
echo

if [ "$MIN_LEN" -eq "$MAX_LEN" ]; then
  hashcat -m "$MODE" "$OUT" -a 3 "$MASK" --session "$SESSION_NAME" \
    --restore-file-path "$RESTORE_FILE"
else
  hashcat -m "$MODE" "$OUT" -a 3 "$MAX_MASK" --session "$SESSION_NAME" \
    --increment --increment-min "$MIN_LEN" --increment-max "$MAX_LEN" \
    --restore-file-path "$RESTORE_FILE"
fi