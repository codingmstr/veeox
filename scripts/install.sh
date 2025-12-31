#!/usr/bin/env bash
set -Eeuo pipefail

die () { echo "${1}" >&2; exit "${2:-1}"; }

IFS=$'\n\t'
alias_name="vx"
got_alias=0

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -a|--alias|--alise)
            shift || true
            [[ $# -gt 0 ]] || die "Missing value for --alias" 2
            alias_name="${1}"
            got_alias=1
            shift
        ;;
        *)
            if (( got_alias )); then
                die "Unknown arg: ${1}" 2
            fi
            alias_name="${1}"
            got_alias=1
            shift
        ;;
    esac
done

ENTRY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/run.sh"
BIN_DIR="${HOME}/.local/bin"
BIN="${BIN_DIR}/${alias_name}"
RC_FILES=( "${HOME}/.bashrc" "${HOME}/.zshrc" )

[[ -f "${ENTRY}" ]] || { echo "Missing: ${ENTRY}" >&2; exit 2; }
[[ "${alias_name}" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || die "Invalid alias name: ${alias_name}" 2

mkdir -p "${BIN_DIR}"
chmod +x "${ENTRY}" 2>/dev/null || true

entry_q="$(printf '%q' "${ENTRY}")"

cat > "${BIN}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=\$'\\n\\t'

ENTRY=${entry_q}

[[ -f "\${ENTRY}" ]] || {
    echo "${alias_name} error: missing entry: \${ENTRY}" >&2
    echo "Hint: repo moved? re-run: ./scripts/install.sh ${alias_name}" >&2
    exit 2
}

chmod +x "\${ENTRY}" 2>/dev/null || true
exec bash "\${ENTRY}" "\$@"
EOF

chmod +x "${BIN}"

for rc in "${RC_FILES[@]}"; do

    touch "${rc}" 2>/dev/null || continue
    grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "${rc}" 2>/dev/null && continue
    printf '\n# vx launcher\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "${rc}"

done

echo "Installed: ${BIN}"
echo "Run: ${alias_name} -h"
