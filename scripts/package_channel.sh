#!/usr/bin/env bash
# Empacota o canal Roku em um .zip pronto para upload no Application Installer
# (http://<IP-DA-ROKU> com o Developer Mode ativado).
set -euo pipefail

cd "$(dirname "$0")/../roku-channel"
OUT="../stremio-cast-receiver.zip"

rm -f "$OUT"

# Preferir `zip`; cair para Python quando não existir (ex.: Git Bash no Windows,
# que não traz `zip`). NÃO usar o Compress-Archive do PowerShell 5.1: ele grava
# os caminhos com "\" e o Application Installer da Roku não acha os arquivos.
if command -v zip >/dev/null 2>&1; then
  zip -r "$OUT" manifest source components images -x '*.DS_Store'
elif command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  PY=$(command -v python || command -v python3)
  "$PY" - "$OUT" <<'PYEOF'
import os, sys, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for d, _, files in os.walk("."):
        for f in files:
            if f == ".DS_Store":
                continue
            full = os.path.join(d, f)
            z.write(full, os.path.relpath(full, ".").replace(os.sep, "/"))
PYEOF
else
  echo "Precisa de 'zip' ou 'python' no PATH para empacotar." >&2
  exit 1
fi

echo "Pacote gerado em: $(realpath "$OUT")"
echo "Envie esse .zip em http://<IP-DA-ROKU> (usuário: rokudev, senha definida no Developer Mode)."
