#!/usr/bin/env bash
# Empacota o canal Roku em um .zip pronto para upload no Application Installer
# (http://<IP-DA-ROKU> com o Developer Mode ativado).
#
# Antes de empacotar, valida o BrightScript/SceneGraph com o brighterscript
# (se houver Node no PATH) — a Roku só diz "Compilation Failed. MainScene" sem
# número de linha, então essa checagem local evita ciclos de sideload cego.
set -euo pipefail

cd "$(dirname "$0")/../roku-channel"
OUT="../stremio-cast-receiver.zip"
INCLUDE=(manifest source components images)

# --- validação (não fatal se não houver Node) -------------------------------
if command -v npx >/dev/null 2>&1; then
  echo "Validando com brighterscript..."
  if ! npx -y brighterscript@latest --project bsconfig.json; then
    echo "ERRO: brighterscript apontou problemas — corrija antes de empacotar." >&2
    exit 1
  fi
else
  echo "AVISO: Node/npx nao encontrado — pulando a validacao brighterscript." >&2
fi

# --- empacotamento ---------------------------------------------------------
rm -f "$OUT"

# `zip` (Linux/mac) ou fallback em Python (Git Bash no Windows nao traz `zip`).
# NAO usar o Compress-Archive do PowerShell 5.1: grava os caminhos com "\" e o
# Application Installer da Roku nao acha os arquivos.
if command -v zip >/dev/null 2>&1; then
  zip -r "$OUT" "${INCLUDE[@]}" -x '*.DS_Store'
elif command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  PY=$(command -v python || command -v python3)
  "$PY" - "$OUT" "${INCLUDE[@]}" <<'PYEOF'
import os, sys, zipfile
out, includes = sys.argv[1], sys.argv[2:]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name in includes:
        if os.path.isfile(name):
            z.write(name, name)
            continue
        for d, _, files in os.walk(name):
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
