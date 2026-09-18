#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$APP_DIR/.venv"
LOG_DIR="$APP_DIR/logs"
LOG_FILE="$LOG_DIR/keepalive.log"
PID_FILE="$APP_DIR/keepalive.pid"

cd "$APP_DIR"

usage() {
    echo "Usage: $0 {start|stop|restart|status|logs}"
}

is_running() {
    [[ -f "$PID_FILE" ]] || return 1
    local pid
    pid="$(cat "$PID_FILE")"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

stop_service() {
    if ! [[ -f "$PID_FILE" ]]; then
        echo "[INFO] Aucun keepalive en cours."
        return 0
    fi

    local pid
    pid="$(cat "$PID_FILE")"

    if kill -0 "$pid" 2>/dev/null; then
        echo "[INFO] Arrêt du keepalive (PID $pid)..."
        kill "$pid"

        for _ in {1..10}; do
            if ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 1
        done

        if kill -0 "$pid" 2>/dev/null; then
            echo "[WARNING] Arrêt forcé..."
            kill -9 "$pid"
        fi

        echo "[OK] Keepalive arrêté."
    else
        echo "[INFO] Le processus $pid n'existe plus."
    fi

    rm -f "$PID_FILE"
}

start_service() {
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
    echo "[OK] Virtualenv activé"

    echo "[INFO] Mise à jour de pip et des dépendances..."
    python -m pip install --upgrade pip --quiet
    python -m pip install -r requirements.txt --quiet
    echo "[OK] Dépendances à jour"

    mkdir -p "$LOG_DIR"

    if is_running; then
        local pid
        pid="$(cat "$PID_FILE")"
        echo "[WARNING] Keepalive déjà lancé."
        echo "          PID : $pid"
        echo "          Log : $LOG_FILE"
        return 0
    fi

    rm -f "$PID_FILE"

    echo "[INFO] Démarrage du keepalive..."
    nohup "$VENV_DIR/bin/python" "$APP_DIR/keepalive.py" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    sleep 2

    if kill -0 "$pid" 2>/dev/null; then
        echo "[OK] Keepalive démarré."
        echo "     PID : $pid"
        echo "     Log : $LOG_FILE"
    else
        echo "[ERROR] Le keepalive n'a pas démarré."
        rm -f "$PID_FILE"
        return 1
    fi

    echo "========================================"
}

status_service() {
    if is_running; then
        local pid
        pid="$(cat "$PID_FILE")"
        echo "[OK] Keepalive actif — PID $pid"
        echo "     Log : $LOG_FILE"
    else
        echo "[INFO] Keepalive arrêté."
        [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"
    fi
}

logs_service() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    tail -f "$LOG_FILE"
}

case "${1:-start}" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        echo "[INFO] Redémarrage du keepalive..."
        stop_service
        echo "[INFO] Relecture de .env et mise à jour des dépendances..."
        start_service
        ;;
    status)
        status_service
        ;;
    logs)
        logs_service
        ;;
    *)
        usage
        exit 1
        ;;
esac
