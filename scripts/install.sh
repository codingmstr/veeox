#!/usr/bin/env bash
set -Eeuo pipefail

ENTRY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/run.sh"
BIN_DIR="${HOME}/.local/bin"
BIN="${BIN_DIR}/vx"
RC_FILES=( "${HOME}/.bashrc" "${HOME}/.zshrc" )

[ -f "${ENTRY}" ] || { echo "Missing: ${ENTRY}" >&2; exit 2; }

mkdir -p "${BIN_DIR}"
chmod +x "${ENTRY}" 2>/dev/null || true

cat > "${BIN}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

ENTRY="${ENTRY}"
[ -f "\${ENTRY}" ] || { echo "vx error: missing entry: \${ENTRY}" >&2; exit 2; }

chmod +x "\${ENTRY}" 2>/dev/null || true
exec bash "\${ENTRY}" "\$@"
EOF

chmod +x "${BIN}"

for rc in "${RC_FILES[@]}"; do
    touch "${rc}" 2>/dev/null || continue
    grep -qE '^[[:space:]]*(export[[:space:]]+)?PATH=.*(\$HOME/)?\.local/bin' "${rc}" 2>/dev/null && continue
    printf '\n# vx launcher\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "${rc}"
done

echo "Installed: ${BIN}"
