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

put "$DATA/forms/desativar-excluir-host.json" <<'HOSTFLOW_EOF'
{
    "schema_version": 1,
    "id": "desativar-excluir-host",
    "versao": 1,
    "nome": "Desativar/excluir host",
    "descricao": "Exemplo: desativa (mantém histórico) ou exclui um host existente.",
    "tipo": "delete",
    "ativo": true,
    "equipe_responsavel": "Equipe de monitoramento",
    "campos": [
        {
            "id": "host",
            "rotulo": "Host",
            "tipo": "zbx_host",
            "obrigatorio": true,
            "ajuda": "Só aparecem hosts que você tem permissão de ler.",
            "valor_padrao": "",
            "quando": null,
            "mapeamento": [
                { "alvo": "hostid", "padrao": "" }
            ]
        },
        {
            "id": "operacao",
            "rotulo": "Operação",
            "tipo": "select",
            "obrigatorio": true,
            "ajuda": "Desativar mantém o histórico; excluir apaga o host e todos os dados.",
            "valor_padrao": "desativar",
            "lista": "",
            "opcoes": [
                { "valor": "desativar", "rotulo": "Desativar (recomendado)" },
                { "valor": "excluir", "rotulo": "Excluir definitivamente" }
            ],
            "quando": null,
            "mapeamento": [
                { "alvo": "operacao", "padrao": "" }
            ]
        },
        {
            "id": "confirmo_exclusao",
            "rotulo": "Confirmo que o histórico será perdido",
            "tipo": "checkbox",
            "obrigatorio": true,
            "ajuda": "",
            "valor_padrao": "",
            "quando": { "campo": "operacao", "igual": "excluir" },
            "mapeamento": []
        }
    ],
    "valores_fixos": [
        { "alvo": "groups[]", "valor": "Desativados", "modo": "adicionar", "quando": { "campo": "operacao", "igual": "desativar" } },
        { "alvo": "tag:status", "valor": "desativado", "quando": { "campo": "operacao", "igual": "desativar" } }
    ]
}
HOSTFLOW_EOF

put "$DATA/forms/novo-link-internet.json" <<'HOSTFLOW_EOF'
{
    "schema_version": 1,
    "id": "novo-link-internet",
    "versao": 1,
    "nome": "Novo link de internet",
    "descricao": "Exemplo: link de internet. Proxy, template de ping e categoria são aplicados automaticamente.",
    "tipo": "create",
    "ativo": true,
    "equipe_responsavel": "Equipe de links",
    "campos": [
        {
            "id": "site",
            "rotulo": "Site",
            "tipo": "select",
            "obrigatorio": true,
            "ajuda": "",
            "valor_padrao": "",
            "lista": "sites",
            "opcoes": [],
            "quando": null,
            "mapeamento": [
                { "alvo": "groups[]", "padrao": "Sites/{site.regiao}/{site}/Links", "modo": "adicionar" },
                { "alvo": "tag:site", "padrao": "" },
                { "alvo": "tag:cliente", "padrao": "{site.cliente}" }
            ]
        },
        {
            "id": "operadora",
            "rotulo": "Operadora",
            "tipo": "select",
            "obrigatorio": true,
            "ajuda": "",
            "valor_padrao": "",
            "lista": "operadoras",
            "opcoes": [],
            "quando": null,
            "mapeamento": [
                { "alvo": "host.host", "padrao": "LINK-{site}-{operadora}" },
                { "alvo": "tag:operadora", "padrao": "" }
            ]
        },
        {
            "id": "nome_visivel",
            "rotulo": "Nome visível",
            "tipo": "text",
            "obrigatorio": true,
            "ajuda": "Ex.: Link Operadora A - Site A",
            "valor_padrao": "",
            "regex": "",
            "quando": null,
            "mapeamento": [
                { "alvo": "host.name", "padrao": "" }
            ]
        },
        {
            "id": "ip",
            "rotulo": "IP público monitorado",
            "tipo": "ip",
            "obrigatorio": true,
            "ajuda": "",
            "valor_padrao": "",
            "regex": "",
            "quando": null,
            "mapeamento": [
                { "alvo": "interface.ip", "padrao": "" }
            ]
        },
        {
            "id": "circuito",
            "rotulo": "Designação do circuito",
            "tipo": "text",
            "obrigatorio": true,
            "ajuda": "Código do circuito na operadora.",
            "valor_padrao": "",
            "regex": "^[A-Za-z0-9/_.-]{3,64}$",
            "quando": null,
            "mapeamento": [
                { "alvo": "macro:{$LINK.CIRCUITO}", "padrao": "" },
                { "alvo": "inventory.serialno_a", "padrao": "" }
            ]
        },
        {
            "id": "banda",
            "rotulo": "Banda contratada (Mbps)",
            "tipo": "text",
            "obrigatorio": false,
            "ajuda": "Somente números.",
            "valor_padrao": "",
            "regex": "^[0-9]{1,6}$",
            "quando": null,
            "mapeamento": [
                { "alvo": "macro:{$LINK.BANDA}", "padrao": "" }
            ]
        }
    ],
    "valores_fixos": [
        { "alvo": "interface.type", "valor": "agent", "quando": null },
        { "alvo": "interface.port", "valor": "10050", "quando": null },
        { "alvo": "interface.useip", "valor": "1", "quando": null },
        { "alvo": "proxy", "valor": "proxy-links", "quando": null },
        { "alvo": "templates[]", "valor": "ICMP Ping", "modo": "vincular", "quando": null },
        { "alvo": "tag:categoria", "valor": "LINK", "quando": null }
    ]
}
HOSTFLOW_EOF

put "$DATA/forms/novo-switch.json" <<'HOSTFLOW_EOF'
{
    "schema_version": 1,
    "id": "novo-switch",
    "versao": 1,
    "nome": "Novo switch",
    "descricao": "Exemplo: cadastro de switch de acesso ou core. Grupo e tags são montados a partir do site.",
    "tipo": "create",
    "ativo": true,
    "equipe_responsavel": "Equipe de redes",
    "campos": [
        {
            "id": "site",
            "rotulo": "Site",
            "tipo": "select",
            "obrigatorio": true,
            "ajuda": "",
            "valor_padrao": "",
            "lista": "sites",
            "opcoes": [],
            "quando": null,
            "mapeamento": [
                { "alvo": "groups[]", "padrao": "Sites/{site.regiao}/{site}/{funcao}", "modo": "adicionar" },
                { "alvo": "tag:site", "padrao": "" },
                { "alvo": "tag:cliente", "padrao": "{site.cliente}" }
            ]
        },
        {
            "id": "funcao",
            "rotulo": "Função",
            "tipo": "select",
            "obrigatorio": true,
            "ajuda": "",
            "valor_padrao": "Switches",
            "lista": "",
            "opcoes": [
                { "valor": "Switches", "rotulo": "Switch de acesso" },
                { "valor": "Switches/Core", "rotulo": "Switch core" }
            ],
            "quando": null,
            "mapeamento": []
        },
        {
            "id": "hostname",
            "rotulo": "Hostname",
            "tipo": "text",
            "obrigatorio": true,
            "ajuda": "Padrão SW-<SITE>-<NN>, em maiúsculas.",
            "valor_padrao": "",
            "regex": "^SW-[A-Z0-9_]+-[0-9]{2}$",
            "quando": null,
            "mapeamento": [
                { "alvo": "host.host", "padrao": "" },
                { "alvo": "host.name", "padrao": "" }
            ]
        },
        {
            "id": "ip",
            "rotulo": "IP de gerência",
            "tipo": "ip",
            "obrigatorio": true,
            "ajuda": "",
            "valor_padrao": "",
            "regex": "",
            "quando": null,
            "mapeamento": [
                { "alvo": "interface.ip", "padrao": "" }
            ]
        },
        {
            "id": "proxy",
            "rotulo": "Proxy",
            "tipo": "zbx_proxy",
            "obrigatorio": true,
            "ajuda": "",
            "valor_padrao": "",
            "permitidos": ["proxy-01", "proxy-02"],
            "quando": null,
            "mapeamento": [
                { "alvo": "proxy", "padrao": "" }
            ]
        },
        {
            "id": "observacoes",
            "rotulo": "Observações",
            "tipo": "textarea",
            "obrigatorio": false,
            "ajuda": "Modelo, rack, posição etc.",
            "valor_padrao": "",
            "regex": "",
            "quando": null,
            "mapeamento": [
                { "alvo": "host.description", "padrao": "" }
            ]
        }
    ],
    "valores_fixos": [
        { "alvo": "interface.type", "valor": "snmp", "quando": null },
        { "alvo": "interface.port", "valor": "161", "quando": null },
        { "alvo": "interface.useip", "valor": "1", "quando": null },
        { "alvo": "interface.snmp.version", "valor": "2", "quando": null },
        { "alvo": "interface.snmp.community", "valor": "{$SNMP_COMMUNITY}", "quando": null },
        { "alvo": "templates[]", "valor": "Network Generic Device by SNMP", "modo": "vincular", "quando": null },
        { "alvo": "tag:categoria", "valor": "REDE", "quando": null },
        { "alvo": "tag:funcao", "valor": "ACESSO", "quando": { "campo": "funcao", "igual": "Switches" } },
        { "alvo": "tag:funcao", "valor": "CORE", "quando": { "campo": "funcao", "igual": "Switches/Core" } }
    ]
}
HOSTFLOW_EOF

put "$DATA/lists/categorias.json" <<'HOSTFLOW_EOF'
{
    "id": "categorias",
    "nome": "Categorias de host",
    "itens": [
        { "valor": "SERVIDOR", "rotulo": "Servidor", "attrs": {} },
        { "valor": "REDE", "rotulo": "Equipamento de rede", "attrs": {} },
        { "valor": "LINK", "rotulo": "Link de internet", "attrs": {} },
        { "valor": "URL", "rotulo": "URL / serviço web", "attrs": {} }
    ]
}
HOSTFLOW_EOF

put "$DATA/lists/operadoras.json" <<'HOSTFLOW_EOF'
{
    "id": "operadoras",
    "nome": "Operadoras de link",
    "itens": [
        { "valor": "OPERADORA_A", "rotulo": "Operadora A", "attrs": {} },
        { "valor": "OPERADORA_B", "rotulo": "Operadora B", "attrs": {} },
        { "valor": "OPERADORA_C", "rotulo": "Operadora C", "attrs": {} }
    ]
}
HOSTFLOW_EOF

put "$DATA/lists/sites.json" <<'HOSTFLOW_EOF'
{
    "id": "sites",
    "nome": "Sites",
    "itens": [
        { "valor": "SITE_A", "rotulo": "Site A", "attrs": { "regiao": "NORTE", "cliente": "CLIENTE_A" } },
        { "valor": "SITE_B", "rotulo": "Site B", "attrs": { "regiao": "NORTE", "cliente": "CLIENTE_B" } },
        { "valor": "SITE_C", "rotulo": "Site C", "attrs": { "regiao": "SUL", "cliente": "CLIENTE_A" } }
    ]
}
HOSTFLOW_EOF

