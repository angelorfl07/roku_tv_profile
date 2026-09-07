#!/usr/bin/env bash
# Envia manualmente uma URL de stream para o canal sideloaded na Roku, via ECP.
# Útil para testar o canal Roku sem precisar do app Android ainda —
# ou como base para uma Tasker Task / atalho no Termux.
#
# Uso: ./send_to_roku.sh <IP-DA-ROKU> <URL-DO-STREAM> ["Título opcional"]

set -euo pipefail

ROKU_IP="${1:?Uso: send_to_roku.sh <IP-DA-ROKU> <URL-DO-STREAM> [\"Titulo\"]}"
STREAM_URL="${2:?Faltou a URL do stream}"
TITLE="${3:-Stremio}"

urlencode() {
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

ENC_URL=$(urlencode "$STREAM_URL")
ENC_TITLE=$(urlencode "$TITLE")

# Tenta primeiro /input (canal já em execução, não relança/pisca a tela).
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -d '' \
    "http://${ROKU_IP}:8060/input?stremioUrl=${ENC_URL}&stremioTitle=${ENC_TITLE}")

if [ "$STATUS" != "200" ]; then
    echo "Canal não estava rodando (status $STATUS), lançando via /launch..."
    curl -s -o /dev/null -w '%{http_code}\n' -d '' \
        "http://${ROKU_IP}:8060/launch/dev?stremioUrl=${ENC_URL}&stremioTitle=${ENC_TITLE}"
else
    echo "Enviado via /input (status $STATUS)."
fi
