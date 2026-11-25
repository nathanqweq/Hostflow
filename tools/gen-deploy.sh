#!/usr/bin/env bash
# Gera dist/deploy-hostflow.sh: um comando "cat > arquivo <<'HOSTFLOW_EOF'" por arquivo do módulo.
# Uso: bash tools/gen-deploy.sh
set -euo pipefail

cd "$(dirname "$0")/.."
SRC=hostflow
OUT=dist/deploy-hostflow.sh
DELIM=HOSTFLOW_EOF

mkdir -p dist

if grep -rlq "^${DELIM}\$" "$SRC" config; then
	echo "ERRO: algum arquivo contém a linha delimitadora ${DELIM}" >&2
	exit 1
fi

{
	cat <<'HEADER'
#!/usr/bin/env bash
# HostFlow: deploy. Cada bloco "cat > ..." regrava um arquivo inteiro.
# Rode como root no servidor do FRONTEND. Ajuste ZBX_UI se o frontend estiver em outro caminho
# (é o diretório onde fica o zabbix.php).
set -euo pipefail

ZBX_UI="${ZBX_UI:-/usr/share/zabbix}"
MOD="$ZBX_UI/modules/hostflow"

if [ ! -f "$ZBX_UI/zabbix.php" ]; then
	echo "zabbix.php não encontrado em $ZBX_UI. Rode: ZBX_UI=/caminho/do/frontend bash $0" >&2
	exit 1
fi

HEADER

	dirs=$(cd "$SRC" && find . -type d ! -path './examples*' | sed 's|^\./||' | grep -v '^\.$' | sort)
	echo "mkdir -p \"\$MOD\""
	for d in $dirs; do
		echo "mkdir -p \"\$MOD/$d\""
	done
	echo

	for f in $(cd "$SRC" && find . -type f ! -path './examples/*' | sed 's|^\./||' | sort); do
		echo "# ---- $f"
		echo "cat > \"\$MOD/$f\" <<'$DELIM'"
		cat "$SRC/$f"
		# garante quebra de linha antes do delimitador
		[ -n "$(tail -c1 "$SRC/$f")" ] && echo
		echo "$DELIM"
		echo
	done

	cat <<'FOOTER'
# ---- permissões do código do módulo (somente leitura para o servidor web)
chown -R root:root "$MOD"
find "$MOD" -type d -exec chmod 755 {} +
find "$MOD" -type f -exec chmod 644 {} +

echo "HostFlow copiado para $MOD"
FOOTER
} > "$OUT"

# Exemplos: script separado, que NÃO sobrescreve formulários/listas já existentes.
EX=dist/deploy-hostflow-exemplos.sh
{
	cat <<'HEADER'
#!/usr/bin/env bash
# HostFlow: instala listas e formulários de exemplo no diretório de dados.
# Não sobrescreve arquivos existentes. Rode como root.
set -euo pipefail

DATA="${HOSTFLOW_DATA:-/var/lib/zabbix-hostflow}"
mkdir -p "$DATA/forms" "$DATA/lists"

put() { # put <destino>  (conteúdo via stdin)
	if [ -e "$1" ]; then
		echo "mantido (já existe): $1"
		cat > /dev/null
	else
		cat > "$1"
		echo "criado: $1"
	fi
}

HEADER
	for f in $(cd "$SRC/examples" && find . -type f -name '*.json' | sed 's|^\./||' | sort); do
		echo "put \"\$DATA/$f\" <<'$DELIM'"
		cat "$SRC/examples/$f"
		[ -n "$(tail -c1 "$SRC/examples/$f")" ] && echo
		echo "$DELIM"
		echo
	done
} > "$EX"

chmod +x "$OUT" "$EX"
echo "Gerado: $OUT ($(grep -c "^cat > " "$OUT") arquivos)"
echo "Gerado: $EX ($(grep -c '^put ' "$EX") arquivos)"
