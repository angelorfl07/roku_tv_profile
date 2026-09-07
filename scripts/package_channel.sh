#!/usr/bin/env bash
# Empacota o canal Roku em um .zip pronto para upload no Application Installer
# (http://<IP-DA-ROKU> com o Developer Mode ativado).
set -euo pipefail

cd "$(dirname "$0")/../roku-channel"
OUT="../stremio-cast-receiver.zip"

rm -f "$OUT"
zip -r "$OUT" manifest source components images -x '*.DS_Store'

echo "Pacote gerado em: $(realpath "$OUT")"
echo "Envie esse .zip em http://<IP-DA-ROKU> (usuário: rokudev, senha definida no Developer Mode)."
