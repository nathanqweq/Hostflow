# HostFlow: formulários de solicitação de hosts (Zabbix 7.4)

Módulo de frontend do Zabbix 7.4 para:

1. **o admin (Super admin) criar formulários** num construtor visual, ou editando o JSON;
2. **o usuário preencher** um formulário que só aceita valores válidos: listas fechadas, grupos/templates/proxies existentes, IP/DNS/regex validados no servidor.

O que acontece **depois do submit fica em aberto nesta versão**. O envio válido monta um pacote completo (resumo, payload técnico, diff contra o host atual, justificativa, solicitante) e o entrega a um `SubmitHandler`. O handler padrão não envia nada. A integração com um sistema de chamados vai entrar como um handler.

O módulo é genérico: nada do ambiente fica fixo no código. Sites, clientes, categorias, árvore de grupos, tags, proxies e templates são cadastrados pela interface, em *Listas de valores* e *Formulários*. Os arquivos em `examples/` são só pontos de partida neutros.

Não cria tabelas no banco do Zabbix e não precisa de banco próprio. Formulários e listas são arquivos JSON num diretório de dados fora do webroot.

## Árvore

```
hostflow/                         -> copiar para <frontend>/modules/hostflow
├── manifest.json                 actions, views e assets (manifest_version 2)
├── Module.php                    menu "Solicitações" (itens de admin só para Super admin)
├── actions/
│   ├── BaseAction.php            base: repositório, checagem de Super admin, redirect com mensagem
│   ├── FormList.php              hostflow.form.list    – lista formulários (admin)
│   ├── FormEdit.php              hostflow.form.edit    – construtor visual (admin)
│   ├── FormSave.php              hostflow.form.save    – POST: valida com FormSchema e grava
│   ├── FormDelete.php            hostflow.form.delete  – POST
│   ├── ListList.php / ListEdit.php / ListSave.php / ListDelete.php   – listas de valores (admin)
│   ├── RequestNew.php            hostflow.request.new  – escolher formulário / preencher (+ pré-preenchimento por host)
│   └── RequestSubmit.php         hostflow.request.submit – POST: valida, monta payload, chama o SubmitHandler
├── lib/
│   ├── Config.php                lê /etc/zabbix/hostflow.conf.php
│   ├── Ui.php                    caixas de erro/aviso
│   ├── storage/JsonStore.php     um JSON por id, gravação atômica (troque esta camada para usar banco)
│   ├── form/FormSchema.php       formato e validação da DEFINIÇÃO do formulário
│   ├── form/ListSchema.php       formato e parser das listas de valores
│   ├── form/Repository.php       formulários + listas
│   ├── form/Options.php          opções válidas de cada campo (mesma fonte para exibir e validar)
│   ├── form/ZabbixLookup.php     consultas à API interna com a sessão do usuário
│   ├── form/Submission.php       validação do ENVIO (obrigatório, regex, IP, listas, duplicidade…)
│   ├── form/PayloadBuilder.php   valores + mapeamentos + valores fixos -> payload do host
│   ├── form/HostState.php        estado atual do host, mesclagem, diff, pré-preenchimento
│   └── submit/SubmitHandler.php, NullSubmitHandler.php   ponto de extensão pós-submit (sistema de chamados)
├── views/                        hostflow.*.php (todo texto passa por CTag, que escapa HTML)
├── assets/js/                    hostflow.builder.js (construtor), hostflow.request.js (form), hostflow.common.js
├── assets/css/hostflow.css
└── examples/                     3 formulários e 3 listas de exemplo
config/hostflow.conf.php.example  -> /etc/zabbix/hostflow.conf.php
tools/gen-deploy.sh               gera dist/*.sh (um heredoc por arquivo)
dist/deploy-hostflow.sh           deploy do módulo
dist/deploy-hostflow-exemplos.sh  exemplos (não sobrescreve nada existente)
```

## Como o 7.4 trata o módulo (verificado no código-fonte `release/7.4`)

- O frontend **só carrega o módulo para quem tem acesso pelo User role** (`modules.module.<id>`). Sem acesso, menu e actions nem existem. Não há fallback para o "default access".
- Os itens de admin (Formulários, Listas) e as actions correspondentes exigem **Super admin** no `checkPermissions()`.
- CSRF: todo POST leva `CCsrfTokenHelper::get('<nome da action>')`. As actions GET chamam `disableCsrfValidation()`.
- As chamadas `API::*` feitas pelo frontend usam a sessão do usuário e **não dependem** da permissão "API access" do role.

## Instalação

### Com o instalador (recomendado)

No servidor do **frontend**, como root:

```bash
git clone https://github.com/nathanqweq/Hostflow.git && cd Hostflow
sudo bash install.sh              # ou: sudo bash install.sh --examples
```

O `install.sh` faz isto:
- detecta o diretório do frontend e o usuário do PHP;
- valida a sintaxe de todo o PHP com `php -l` e não instala nada se houver erro;
- copia o módulo com troca atômica;
- cria `/var/lib/zabbix-hostflow` com as permissões certas e o contexto SELinux;
- gera `/etc/zabbix/hostflow.conf.php` se ele não existir;
- testa se o usuário do PHP consegue gravar no diretório de dados.

Reexecutar o script atualiza só o código do módulo. Formulários, listas e configuração nunca são sobrescritos.

| Opção | Para quê |
|---|---|
| `--ui DIR` | frontend em caminho não padrão (diretório do `zabbix.php`) |
| `--data-dir DIR` | outro diretório de dados |
| `--web-user USER` | quando a detecção do usuário do PHP errar |
| `--examples` | instala os exemplos sem sobrescrever nada |
| `--uninstall` | remove o módulo e mantém dados e configuração |

Depois siga os passos 5 e 6 abaixo, que são feitos na interface. Para atualizar no futuro: `git pull && sudo bash install.sh`.

### Manual (sem git no servidor)

**1. Encontre o diretório do frontend**, onde está o `zabbix.php`:

```bash
rpm -ql zabbix-web 2>/dev/null | grep '/zabbix.php$' || dpkg -L zabbix-frontend-php 2>/dev/null | grep '/zabbix.php$'
```

**2. Copie o módulo.** Cole o conteúdo de `dist/deploy-hostflow.sh` no servidor do frontend e rode como root:

```bash
ZBX_UI=/usr/share/zabbix bash deploy-hostflow.sh      # ajuste ZBX_UI ao passo 1
php -l /usr/share/zabbix/modules/hostflow/Module.php   # e, para conferir tudo:
find /usr/share/zabbix/modules/hostflow -name '*.php' -exec php -l {} \; | grep -v 'No syntax errors'
```

**3. Crie o diretório de dados e a configuração.** Descubra o usuário do PHP com `ps -o user= -C php-fpm | sort -u`. Costuma ser `apache` no RHEL e `www-data` no Debian/Ubuntu.

```bash
WEBUSER=apache    # ou www-data
install -d -o root -g "$WEBUSER" -m 2770 /var/lib/zabbix-hostflow /var/lib/zabbix-hostflow/forms /var/lib/zabbix-hostflow/lists
cp hostflow.conf.php.example /etc/zabbix/hostflow.conf.php     # conteúdo em config/
chown root:"$WEBUSER" /etc/zabbix/hostflow.conf.php && chmod 640 /etc/zabbix/hostflow.conf.php
# Com SELinux (RHEL):
semanage fcontext -a -t httpd_sys_rw_content_t '/var/lib/zabbix-hostflow(/.*)?' && restorecon -Rv /var/lib/zabbix-hostflow
```

**4. Instale os exemplos (opcional).** Rode `HOSTFLOW_DATA=/var/lib/zabbix-hostflow bash deploy-hostflow-exemplos.sh`. Depois: `chown -R root:"$WEBUSER" /var/lib/zabbix-hostflow/*/ && chmod 660 /var/lib/zabbix-hostflow/*/*.json`.

**5. Habilite o módulo.** Vá em *Administration › General › Modules*, clique em **Scan directory** e habilite **HostFlow**.

**6. Libere o acesso no role.** Vá em *Users › User roles*, abra o role dos solicitantes e marque **HostFlow** em *Access to modules*. Faça o mesmo no role dos Super admins.

## Como testar esta etapa

1. **Menu:** quem é Super admin vê *Solicitações › Nova solicitação / Formulários / Listas de valores*. Um usuário comum com o módulo liberado vê só *Nova solicitação*. Um usuário sem o módulo no role não vê o menu, e abrir `zabbix.php?action=hostflow.request.new` dá acesso negado.
2. **Listas:** abra *Listas de valores* e edite `sites` com os valores do seu ambiente. Um item por linha: `SITE_A | Site A | regiao=NORTE; cliente=CLIENTE_A`.
3. **Construtor:** abra *Formulários › Novo switch*.
   - Troque os proxies permitidos (`proxy-01/02` são fictícios) e a árvore de grupos (`Sites/...`) pela do seu ambiente, e salve. O save confere se templates, proxies e grupos citados existem, e recusa com a lista do que falta.
   - Teste também a aba **JSON**: um JSON inválido volta com o erro e o texto é preservado.
4. **Preenchimento (criação):** em *Nova solicitação › Novo switch*, faça estes testes:
   - envie vazio: a página volta com os erros por campo;
   - use o IP `999.1.1.1`: aparece "IP inválido";
   - use o hostname `sw-x`: o envio falha na regex;
   - use um hostname ou IP que já existe: o envio é recusado;
   - use um site cujo grupo `Sites/<regiao>/<site>/Switches` não existe: aparece "Grupo inexistente".

   Um envio válido mostra o resumo, o host a ser criado (grupo e tags `site`, `cliente`, `categoria`, `funcao`) e o payload JSON.
5. **Preenchimento (alteração/exclusão):** em *Desativar/excluir host*, escolha um host. A página recarrega com `&hostid=`.
   - Escolha "Excluir": aparece a caixa de confirmação obrigatória.
   - Envie com "Desativar": o diff mostra `status 0 → 1`, o grupo `Desativados` (crie esse grupo antes) e a tag `status`.
6. **Segurança:** como usuário comum, tente abrir `zabbix.php?action=hostflow.form.list`: deve dar acesso negado. Tente também enviar um valor fora da lista editando o HTML no navegador: o servidor recusa com "Valor ... não é permitido".

## Formato do formulário (resumo)

```jsonc
{
  "id": "novo-switch", "nome": "...", "tipo": "create|update|move|delete", "ativo": true,
  "equipe_responsavel": "Equipe de redes",         // destino do chamado (integração futura)
  "campos": [{
    "id": "site", "rotulo": "Site", "tipo": "select", "obrigatorio": true,
    "lista": "sites",                                // ou "opcoes": [{"valor","rotulo"}]
    "quando": {"campo": "x", "igual": "y"},          // opcional: exibir só quando
    "mapeamento": [
      {"alvo": "groups[]", "padrao": "Sites/{site.regiao}/{site}/{funcao}", "modo": "adicionar"},
      {"alvo": "tag:site"}
    ]
  }],
  "valores_fixos": [{"alvo": "tag:categoria", "valor": "REDE", "quando": null}]
}
```

- **Tipos de campo:** `text`, `textarea`, `ip`, `dns`, `checkbox`, `select`, `multiselect`, `tag_value`, `zbx_hostgroup` (com `prefixo`), `zbx_template` / `zbx_proxy` / `zbx_proxy_group` (com `permitidos`), `zbx_host`.
- **Alvos:**
  - `host.host|name|description|status`;
  - `interface.type|ip|dns|port|useip` e `interface.snmp.*`;
  - `groups[]` (modos `adicionar` / `substituir_prefixo`);
  - `templates[]` (modos `vincular` / `desvincular`);
  - `proxy`, `proxy_group`, `tag:<NOME>`, `macro:{$NOME}`, `inventory.<campo>`;
  - `hostid` e `operacao`.
- **Placeholders** num padrão vazio são ignorados, então nunca geram `A//B`. Em alteração, um campo vazio não muda nada.

## Limitações conhecidas desta versão

- As checagens de duplicidade (hostname, IP) e de existência de grupos rodam com a **sessão de quem envia**. Por isso só enxergam o que esse usuário pode ler. A revalidação completa cabe à etapa de execução.
- Defina `permitidos` para templates e proxies. Usuários do tipo *User* normalmente não leem templates, então `grupo_templates` pode aparecer vazio para eles.
- Segredos digitados no formulário (community e passphrases SNMP) aparecem no payload da tela de confirmação. Prefira macros (`{$SNMP_COMMUNITY}`) nos valores fixos, e não mande segredos ao sistema de chamados.
- O pré-preenchimento extrai o valor de um padrão por regex. Quando o host atual não segue o padrão, o campo vem vazio.

## Próximas etapas

1. **Sistema de chamados:** um `SubmitHandler` que abre o chamado para `equipe_responsavel`, usando o resumo e o diff. Ele é ativado em `submit_handler`.
2. **Histórico:** guardar as solicitações enviadas (hoje nada é gravado depois do submit).
3. **Fila de aprovação e execução via API** com a sessão do aprovador, como no escopo original.
4. **Versão 2:** import em lote via CSV.
