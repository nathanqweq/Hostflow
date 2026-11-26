#!/usr/bin/env bash
#
# HostFlow: instalador do módulo para o frontend do Zabbix 7.4.
#
# Rode como root no servidor do FRONTEND, a partir do repositório clonado:
#
#   git clone https://github.com/<usuario>/Hostflow.git && cd Hostflow
#   sudo bash install.sh                  # instala ou atualiza
#   sudo bash install.sh --examples       # + formulários e listas de exemplo
#   sudo bash install.sh --uninstall      # remove o módulo (mantém dados e configuração)
#
# Reexecutar o script atualiza o código do módulo. Formulários, listas e configuração nunca são sobrescritos.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/hostflow"
MODULE_NAME="hostflow"

ZBX_UI=""
DATA_DIR="/var/lib/zabbix-hostflow"
CONF_FILE="/etc/zabbix/hostflow.conf.php"   # caminho fixo: é o que lib/Config.php lê
WEB_USER=""
WITH_EXAMPLES=0
ACTION="install"

usage() {
	cat <<'EOF'
Uso: sudo bash install.sh [opções]

  --ui DIR          diretório do frontend (onde está o zabbix.php). Padrão: detecção automática
  --data-dir DIR    diretório de dados (formulários e listas). Padrão: /var/lib/zabbix-hostflow
  --web-user USER   usuário do PHP (php-fpm/apache). Padrão: detecção automática
  --examples        instala formulários e listas de exemplo (não sobrescreve existentes)
  --uninstall       remove o módulo do frontend (mantém dados e configuração)
  -h, --help        esta ajuda
EOF
}

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[aviso]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[erro]\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
		--ui)        [ $# -ge 2 ] || die "--ui precisa de um valor"; ZBX_UI="${2%/}"; shift 2 ;;
		--data-dir)  [ $# -ge 2 ] || die "--data-dir precisa de um valor"; DATA_DIR="${2%/}"; shift 2 ;;
		--web-user)  [ $# -ge 2 ] || die "--web-user precisa de um valor"; WEB_USER="$2"; shift 2 ;;
		--examples)  WITH_EXAMPLES=1; shift ;;
		--uninstall) ACTION="uninstall"; shift ;;
		-h|--help)   usage; exit 0 ;;
		*)           usage; die "opção desconhecida: $1" ;;
	esac
done

[ "$(id -u)" -eq 0 ] || die "rode como root (sudo bash install.sh)."

# O caminho vai para dentro de um arquivo PHP: só caracteres seguros.
[[ "$DATA_DIR" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "--data-dir deve ser absoluto e conter só letras, números, '.', '_', '-' e '/'."

# ------------------------------------------------------------------ detecção

detect_ui() {
	local candidates=(/usr/share/zabbix/ui /usr/share/zabbix /var/www/html/zabbix /var/www/zabbix /var/www/html)
	local dir

	for dir in "${candidates[@]}"; do
		if [ -f "$dir/zabbix.php" ]; then
			echo "$dir"
			return 0
		fi
	done

	local found=""

	if command -v rpm >/dev/null 2>&1; then
		found="$(rpm -qla 2>/dev/null | grep -m1 '/zabbix\.php$' || true)"
	fi

	if [ -z "$found" ] && command -v dpkg >/dev/null 2>&1; then
		found="$(dpkg -L zabbix-frontend-php 2>/dev/null | grep -m1 '/zabbix\.php$' || true)"
	fi

	[ -n "$found" ] && dirname "$found"
}

detect_web_user() {
	local user

	user="$(ps -eo user=,comm= 2>/dev/null \
		| awk '$2 ~ /^(php-fpm|php[0-9.]*-fpm|apache2|httpd)/ && $1 != "root" { print $1 }' \
		| sort | uniq -c | sort -rn | awk 'NR == 1 { print $2 }')"

	if [ -n "$user" ]; then
		echo "$user"
		return 0
	fi

	for user in apache www-data nginx; do
		if id "$user" >/dev/null 2>&1; then
			echo "$user"
			return 0
		fi
	done
}

if [ -z "$ZBX_UI" ]; then
	ZBX_UI="$(detect_ui || true)"
	[ -n "$ZBX_UI" ] || die "frontend do Zabbix não encontrado. Informe com --ui /caminho (onde está o zabbix.php)."
fi

[ -f "$ZBX_UI/zabbix.php" ] || die "zabbix.php não encontrado em $ZBX_UI."

MOD_DIR="$ZBX_UI/modules/$MODULE_NAME"

# ------------------------------------------------------------------ desinstalação

if [ "$ACTION" = "uninstall" ]; then
	if [ -d "$MOD_DIR" ]; then
		rm -rf -- "$MOD_DIR"
		info "Módulo removido de $MOD_DIR."
	else
		warn "Módulo não encontrado em $MOD_DIR."
	fi

	cat <<EOF

Mantidos (apague manualmente se quiser):
  dados:         $DATA_DIR
  configuração:  $CONF_FILE

O registro do módulo continua em Administration › General › Modules: desabilite-o lá
(ou rode "Scan directory" para que ele apareça como ausente).
EOF
	exit 0
fi

# ------------------------------------------------------------------ pré-requisitos

[ -f "$SRC/manifest.json" ] || die "código do módulo não encontrado em $SRC. Rode o script de dentro do repositório."

if [ -z "$WEB_USER" ]; then
	WEB_USER="$(detect_web_user || true)"
	[ -n "$WEB_USER" ] || die "usuário do servidor web não detectado. Informe com --web-user (ex.: apache, www-data)."
fi

id "$WEB_USER" >/dev/null 2>&1 || die "usuário '$WEB_USER' não existe."
WEB_GROUP="$(id -gn "$WEB_USER")"

info "Frontend:       $ZBX_UI"
info "Módulo:         $MOD_DIR"
info "Dados:          $DATA_DIR"
info "Configuração:   $CONF_FILE"
info "Usuário do PHP: $WEB_USER (grupo $WEB_GROUP)"

if command -v php >/dev/null 2>&1; then
	php -r 'exit(PHP_VERSION_ID >= 80000 ? 0 : 1);' || die "PHP 8.0 ou superior é necessário (encontrado: $(php -r 'echo PHP_VERSION;'))."

	info "Verificando sintaxe dos arquivos PHP..."
	lint_errors=0

	while IFS= read -r -d '' file; do
		if ! out="$(php -l "$file" 2>&1)"; then
			echo "$out" >&2
			lint_errors=$((lint_errors + 1))
		fi
	done < <(find "$SRC" -name '*.php' -print0)

	[ "$lint_errors" -eq 0 ] || die "$lint_errors arquivo(s) com erro de sintaxe. Nada foi instalado."
else
	warn "php (CLI) não encontrado: a verificação de sintaxe foi pulada."
fi

# ------------------------------------------------------------------ código do módulo

info "Copiando o módulo..."
mkdir -p "$ZBX_UI/modules"

STAGE="$(mktemp -d "$ZBX_UI/modules/.${MODULE_NAME}.XXXXXX")"
trap 'rm -rf -- "$STAGE" "$ZBX_UI/modules/.${MODULE_NAME}.old" 2>/dev/null || true' EXIT

# Copia tudo, exceto os exemplos (vão para o diretório de dados, não para o webroot).
(cd "$SRC" && tar --exclude='./examples' -cf - .) | (cd "$STAGE" && tar -xf -)

chown -R root:root "$STAGE"
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +

# Troca atômica: o frontend nunca vê o módulo pela metade.
if [ -d "$MOD_DIR" ]; then
	mv -- "$MOD_DIR" "$ZBX_UI/modules/.${MODULE_NAME}.old"
fi

mv -- "$STAGE" "$MOD_DIR"
rm -rf -- "$ZBX_UI/modules/.${MODULE_NAME}.old"

if command -v restorecon >/dev/null 2>&1; then
	restorecon -R "$MOD_DIR" >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------ diretório de dados

info "Preparando o diretório de dados..."

for dir in "$DATA_DIR" "$DATA_DIR/forms" "$DATA_DIR/lists" "$DATA_DIR/settings"; do
	if [ -d "$dir" ]; then
		chown root:"$WEB_GROUP" "$dir"
		chmod 2770 "$dir"
	else
		install -d -o root -g "$WEB_GROUP" -m 2770 "$dir"
	fi
done

if [ "$WITH_EXAMPLES" -eq 1 ]; then
	info "Instalando exemplos (sem sobrescrever)..."

	for kind in forms lists; do
		for file in "$SRC/examples/$kind"/*.json; do
			[ -e "$file" ] || continue
			dest="$DATA_DIR/$kind/$(basename "$file")"

			if [ -e "$dest" ]; then
				echo "    mantido (já existe): $dest"
			else
				install -o root -g "$WEB_GROUP" -m 0660 "$file" "$dest"
				echo "    criado: $dest"
			fi
		done
	done
fi

# Arquivos criados pela interface podem ter ficado com dono/permissão diferentes.
find "$DATA_DIR" -type f -name '*.json' -exec chgrp "$WEB_GROUP" {} + -exec chmod 0660 {} +

# SELinux: o servidor web precisa de escrita no diretório de dados.
if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
	info "SELinux ativo: aplicando contexto httpd_sys_rw_content_t em $DATA_DIR..."

	if command -v semanage >/dev/null 2>&1; then
		semanage fcontext -a -t httpd_sys_rw_content_t "${DATA_DIR}(/.*)?" 2>/dev/null \
			|| semanage fcontext -m -t httpd_sys_rw_content_t "${DATA_DIR}(/.*)?"
		restorecon -R "$DATA_DIR"
	else
		warn "semanage não encontrado (pacote policycoreutils-python-utils). Usando chcon, que não sobrevive a um relabel."
		chcon -R -t httpd_sys_rw_content_t "$DATA_DIR"
	fi
fi

# ------------------------------------------------------------------ configuração

if [ -e "$CONF_FILE" ]; then
	info "Configuração existente mantida: $CONF_FILE"

	if ! grep -q -- "'$DATA_DIR'" "$CONF_FILE"; then
		warn "confira se 'data_dir' em $CONF_FILE aponta para $DATA_DIR."
	fi
else
	info "Criando $CONF_FILE..."
	mkdir -p "$(dirname "$CONF_FILE")"

	cat > "$CONF_FILE" <<EOF
<?php
/*
 * HostFlow: configuração (fora do webroot). Gerado por install.sh.
 */
return [
	// Onde ficam os formulários (forms/*.json) e as listas (lists/*.json).
	'data_dir' => '$DATA_DIR',

	// Classe que implementa Modules\\HostFlow\\Lib\\Submit\\SubmitHandler. null = nada é enviado.
	'submit_handler' => null
];
EOF

	chown root:"$WEB_GROUP" "$CONF_FILE"
	chmod 0640 "$CONF_FILE"
fi

# ------------------------------------------------------------------ teste de escrita

if command -v runuser >/dev/null 2>&1; then
	probe="$DATA_DIR/forms/.hostflow-write-test"

	if runuser -u "$WEB_USER" -- sh -c "touch '$probe' && rm -f '$probe'" 2>/dev/null; then
		info "Teste de escrita como $WEB_USER: OK."
	else
		warn "$WEB_USER não conseguiu gravar em $DATA_DIR/forms. Verifique permissões, SELinux/AppArmor e open_basedir do PHP."
	fi
fi

# ------------------------------------------------------------------ próximos passos

VERSION="$(grep -m1 '"version"' "$MOD_DIR/manifest.json" | sed 's/.*: *"\([^"]*\)".*/\1/')"

cat <<EOF

HostFlow $VERSION instalado em $MOD_DIR.

Próximos passos no frontend (uma vez só):
  1. Administration › General › Modules › "Scan directory" e habilite "HostFlow".
  2. Users › User roles: no role dos solicitantes e no dos Super admins,
     marque "HostFlow" em "Access to modules".
  3. Como Super admin: Solicitações › Listas de valores e Solicitações › Formulários.

Para atualizar no futuro: git pull && sudo bash install.sh
EOF
