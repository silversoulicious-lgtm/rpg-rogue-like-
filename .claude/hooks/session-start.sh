#!/bin/bash
# Hook SessionStart — installe Godot 4.3 headless pour que le test de fumée
# (res://_SmokeTest.tscn) et les captures xvfb tournent dans les sessions
# Claude Code on the web. Web-only, idempotent, et TOLÉRANT à l'échec :
# tant que la politique réseau ferme le téléchargement, il quitte proprement
# (exit 0) sans bloquer le démarrage de la session.
set -uo pipefail

# Web uniquement : en local, le dev gère son propre Godot.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.3-stable"
GODOT_ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
GODOT_BIN_NAME="Godot_v${GODOT_VERSION}_linux.x86_64"
GODOT_DIR="${HOME}/.local/godot"
GODOT_BIN="${GODOT_DIR}/${GODOT_BIN_NAME}"

mkdir -p "$GODOT_DIR"

# --- Téléchargement (sauté si le binaire est déjà présent : idempotent) ---
if [ ! -x "$GODOT_BIN" ]; then
  echo "[session-start] Téléchargement de Godot ${GODOT_VERSION}…" >&2
  url_primary="https://downloads.godotengine.org/releases/${GODOT_VERSION}/${GODOT_ZIP}"
  url_github="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${GODOT_ZIP}"
  ok=0
  for url in "$url_primary" "$url_github"; do
    if curl -fsSL --connect-timeout 20 -o "${GODOT_DIR}/g.zip" "$url"; then
      ok=1
      break
    fi
  done
  if [ "$ok" != "1" ]; then
    echo "[session-start] Godot indisponible : la politique réseau de l'environnement" >&2
    echo "[session-start] bloque downloads.godotengine.org ET github.com (403 egress)." >&2
    echo "[session-start] → Autorise l'un de ces hôtes dans la politique réseau pour" >&2
    echo "[session-start]   activer le test de fumée en local. La session démarre quand même." >&2
    exit 0
  fi
  if command -v unzip >/dev/null 2>&1; then
    unzip -oq "${GODOT_DIR}/g.zip" -d "$GODOT_DIR"
  else
    (cd "$GODOT_DIR" && python3 -c "import zipfile; zipfile.ZipFile('g.zip').extractall('.')")
  fi
  rm -f "${GODOT_DIR}/g.zip"
  chmod +x "$GODOT_BIN" 2>/dev/null || true
fi

if [ ! -x "$GODOT_BIN" ]; then
  echo "[session-start] Binaire Godot introuvable après extraction — abandon silencieux." >&2
  exit 0
fi

# --- Expose le chemin à la session (utilisable comme $GODOT_BIN) ---
echo "export GODOT_BIN=\"$GODOT_BIN\"" >> "$CLAUDE_ENV_FILE"

# --- Passe d'import obligatoire (peuple le cache de classes + importe les
#     assets ; sans elle, load() renvoie null en silence). Peu coûteuse si
#     .godot/ existe déjà. ---
echo "[session-start] Passe d'import Godot (cache de classes + assets)…" >&2
"$GODOT_BIN" --headless --editor --quit --path "$CLAUDE_PROJECT_DIR" >/dev/null 2>&1 || true

echo "[session-start] Godot prêt : $GODOT_BIN" >&2
echo "[session-start] Test de fumée : \"\$GODOT_BIN\" --headless --path . res://_SmokeTest.tscn" >&2
