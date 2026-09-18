#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$APP_DIR/.venv"
LOG_DIR="$APP_DIR/logs"
LOG_FILE="$LOG_DIR/keepalive.log"
PID_FILE="$APP_DIR/keepalive.pid"

cd "$APP_DIR"
echo "========================================"
echo " PostgreSQL Keepalive"
echo "========================================"

if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] Python 3 est introuvable."
    exit 1
fi

echo "[OK] Python : $(python3 --version)"

if [[ ! -f "$APP_DIR/.env" ]]; then
    echo "[ERROR] Fichier .env introuvable."
    exit 1
fi

echo "[OK] .env trouvé"

if [[ ! -d "$VENV_DIR" ]]; then
    echo "[INFO] Création du virtualenv..."
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
echo "[OK] Virtualenv activé : $VENV_DIR"

echo "[INFO] Vérification des dépendances..."
python -m pip install --upgrade pip --quiet
python -m pip install -r requirements.txt --quiet
echo "[OK] Dépendances installées"

mkdir -p "$LOG_DIR"

if [[ -f "$PID_FILE" ]]; then
    OLD_PID="$(cat "$PID_FILE")"
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[WARNING] Keepalive déjà lancé."
        echo "          PID : $OLD_PID"
        echo "          Log : $LOG_FILE"
        exit 0
    fi
    rm -f "$PID_FILE"
fi

echo "[INFO] Démarrage du keepalive..."
nohup "$VENV_DIR/bin/python" "$APP_DIR/keepalive.py" >> "$LOG_FILE" 2>&1 &
PID=$!
echo "$PID" > "$PID_FILE"

sleep 2

if kill -0 "$PID" 2>/dev/null; then
    echo "[OK] Keepalive démarré."
    echo "     PID  : $PID"
    echo "     Log  : $LOG_FILE"
    echo "     Mode : arrière-plan"
else
    echo "[ERROR] Le keepalive n'a pas démarré."
    rm -f "$PID_FILE"
    exit 1
fi

echo "========================================"
