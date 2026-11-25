<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

use API;
use Modules\HostFlow\Lib\Storage\JsonStore;

/**
 * Define e valida a ESTRUTURA de um formulário (o que o admin monta no construtor).
 * O formato é o mesmo gravado em disco, então construtor visual e edição de JSON passam pela mesma validação.
 */
final class FormSchema {

	public const SCHEMA_VERSION = 1;

	public const FORM_TYPES = [
		'create' => 'Criação de host',
		'update' => 'Alteração de host',
		'move' => 'Movimentação de host',
		'delete' => 'Desativação/exclusão de host'
	];

	public const FIELD_TYPES = [
		'text' => 'Texto',
		'textarea' => 'Texto longo',
		'ip' => 'Endereço IP',
		'dns' => 'Nome DNS / hostname',
		'checkbox' => 'Caixa de seleção',
		'select' => 'Lista (um valor)',
		'multiselect' => 'Lista (vários valores)',
		'tag_value' => 'Valor de tag (lista fechada)',
		'zbx_hostgroup' => 'Zabbix: grupo de hosts',
		'zbx_template' => 'Zabbix: template',
		'zbx_proxy' => 'Zabbix: proxy',
		'zbx_proxy_group' => 'Zabbix: grupo de proxies',
		'zbx_host' => 'Zabbix: host existente'
	];

	/** Tipos que aceitam lista de opções (estática ou lista compartilhada). */
	public const OPTION_TYPES = ['select', 'multiselect', 'tag_value'];

	/** Tipos de texto livre, que aceitam regex. */
	public const TEXT_TYPES = ['text', 'textarea', 'ip', 'dns'];

	/** Tipos que aceitam "permitidos" (lista fechada de nomes de objetos do Zabbix). */
	public const ALLOWED_TYPES = ['zbx_template', 'zbx_proxy', 'zbx_proxy_group'];

	/** Tipos que podem ter "multiplo". */
	public const MULTI_CAPABLE = ['zbx_hostgroup', 'zbx_template'];

	/** Alvos fixos de mapeamento. Prefixados: tag:<NOME>, macro:{$NOME}, inventory.<campo>. */
	public const TARGETS = [
		'host.host' => 'Host: nome técnico',
		'host.name' => 'Host: nome visível',
		'host.description' => 'Host: descrição',
		'host.status' => 'Host: status (0 ativo, 1 desativado)',
		'interface.type' => 'Interface: tipo (agent, snmp, ipmi, jmx)',
		'interface.ip' => 'Interface: IP',
		'interface.dns' => 'Interface: DNS',
		'interface.port' => 'Interface: porta',
		'interface.useip' => 'Interface: conectar por (1 IP, 0 DNS)',
		'interface.snmp.version' => 'SNMP: versão (1, 2, 3)',
		'interface.snmp.community' => 'SNMP: community',
		'interface.snmp.bulk' => 'SNMP: bulk (0, 1)',
		'interface.snmp.securityname' => 'SNMPv3: security name',
		'interface.snmp.securitylevel' => 'SNMPv3: security level (0, 1, 2)',
		'interface.snmp.authprotocol' => 'SNMPv3: auth protocol',
		'interface.snmp.authpassphrase' => 'SNMPv3: auth passphrase',
		'interface.snmp.privprotocol' => 'SNMPv3: priv protocol',
		'interface.snmp.privpassphrase' => 'SNMPv3: priv passphrase',
		'interface.snmp.contextname' => 'SNMPv3: context name',
		'groups[]' => 'Grupos de hosts',
		'templates[]' => 'Templates',
		'proxy' => 'Monitorado por proxy',
		'proxy_group' => 'Monitorado por grupo de proxies',
		'hostid' => 'Host alvo (somente campo Zabbix: host existente)',
		'operacao' => 'Operação de exclusão (desativar, excluir)'
	];

	public const TARGET_PREFIXES = [
		'tag:' => 'Tag',
		'macro:' => 'Macro de usuário',
		'inventory.' => 'Inventário'
	];

	public const GROUP_MODES = ['adicionar', 'substituir_prefixo'];
	public const TEMPLATE_MODES = ['vincular', 'desvincular'];

	public const CONDITION_LOGICS = ['e', 'ou'];
	public const CONDITION_OPERATORS = ['igual', 'diferente'];

	public const INTERFACE_TYPES = ['agent', 'snmp', 'ipmi', 'jmx'];
	public const OPERATIONS = ['desativar', 'excluir'];

	public const FIELD_ID_PATTERN = '/^[a-z][a-z0-9_]{0,31}$/';
	public const PLACEHOLDER_PATTERN = '/\{([a-z][a-z0-9_]{0,31})(?:\.([a-zA-Z0-9_]{1,64}))?\}/';
	public const MACRO_PATTERN = '/^\{\$[A-Z0-9_.]+\}$/';

	private array $errors = [];

	/**
	 * Valida e normaliza uma definição de formulário.
	 *
	 * @param array $def          Definição vinda do construtor ou do JSON.
	 * @param array $lists        Listas compartilhadas existentes, indexadas por id.
	 * @param bool  $check_zabbix Confere se templates, proxies e grupos fixos existem (com a sessão atual).
	 *
	 * @return array|null  Definição normalizada ou null se houver erros (ver getErrors()).
	 */
	public function validate(array $def, array $lists, bool $check_zabbix = true): ?array {
		$this->errors = [];

		$form = [
			'schema_version' => self::SCHEMA_VERSION,
			'id' => self::str($def, 'id'),
			'versao' => max(1, (int) ($def['versao'] ?? 1)),
			'nome' => self::str($def, 'nome'),
			'descricao' => self::str($def, 'descricao'),
			'tipo' => self::str($def, 'tipo'),
			'ativo' => self::bool($def, 'ativo', true),
			'equipe_responsavel' => self::str($def, 'equipe_responsavel'),
			'campos' => [],
			'valores_fixos' => []
		];

		if (!JsonStore::isValidId($form['id'])) {
			$this->error('ID do formulário', 'use de 1 a 64 caracteres: letras minúsculas, números, "-" e "_".');
		}

		if ($form['nome'] === '') {
			$this->error('Nome', 'obrigatório.');
		}

		if (!array_key_exists($form['tipo'], self::FORM_TYPES)) {
			$this->error('Tipo', 'deve ser create, update, move ou delete.');
		}

		$raw_fields = (isset($def['campos']) && is_array($def['campos'])) ? array_values($def['campos']) : [];

		if (!$raw_fields) {
			$this->error('Campos', 'o formulário precisa de pelo menos um campo.');
		}

		$field_ids = [];

		foreach ($raw_fields as $i => $raw) {
			$id = is_array($raw) ? self::str($raw, 'id') : '';

			if ($id !== '') {
				if (in_array($id, $field_ids, true)) {
					$this->error(sprintf('Campo #%d', $i + 1), sprintf('ID "%s" repetido.', $id));
				}

				$field_ids[] = $id;
			}
		}

		foreach ($raw_fields as $i => $raw) {
			$field = $this->validateField(is_array($raw) ? $raw : [], $i, $field_ids, $lists, $form['tipo']);

			if ($field !== null) {
				$form['campos'][] = $field;
			}
		}

		$raw_fixed = (isset($def['valores_fixos']) && is_array($def['valores_fixos']))
			? array_values($def['valores_fixos'])
			: [];

		foreach ($raw_fixed as $i => $raw) {
			$fixed = $this->validateFixed(is_array($raw) ? $raw : [], $i, $field_ids);

			if ($fixed !== null) {
				$form['valores_fixos'][] = $fixed;
			}
		}

		$this->validateTypeRules($form);

		if ($check_zabbix && !$this->errors) {
			$this->validateZabbixObjects($form);
		}

		return $this->errors ? null : $form;
	}

	public function getErrors(): array {
		return $this->errors;
	}

	private function validateField(array $raw, int $i, array $field_ids, array $lists, string $form_type): ?array {
		$label = sprintf('Campo #%d', $i + 1);

		$field = [
			'id' => self::str($raw, 'id'),
			'rotulo' => self::str($raw, 'rotulo'),
			'tipo' => self::str($raw, 'tipo'),
			'obrigatorio' => self::bool($raw, 'obrigatorio', false),
			'ajuda' => self::str($raw, 'ajuda'),
			'valor_padrao' => self::str($raw, 'valor_padrao')
		];

		if ($field['rotulo'] !== '') {
			$label .= ' ('.$field['rotulo'].')';
		}

		if (!preg_match(self::FIELD_ID_PATTERN, $field['id'])) {
			$this->error($label, 'ID deve começar com letra minúscula e ter só a-z, 0-9 e "_" (máx. 32).');
		}

		if ($field['rotulo'] === '') {
			$this->error($label, 'rótulo obrigatório.');
		}

		if (!array_key_exists($field['tipo'], self::FIELD_TYPES)) {
			$this->error($label, 'tipo de campo inválido.');

			return null;
		}

		$type = $field['tipo'];

		if (in_array($type, self::TEXT_TYPES, true)) {
			$field['regex'] = self::str($raw, 'regex');

			if ($field['regex'] !== '' && !self::isValidRegex($field['regex'])) {
				$this->error($label, 'regex inválida.');
			}
		}

		if (in_array($type, self::OPTION_TYPES, true)) {
			$field['lista'] = self::str($raw, 'lista');
			$field['opcoes'] = self::normalizeOptions($raw['opcoes'] ?? []);

			if ($field['lista'] !== '') {
				if (!array_key_exists($field['lista'], $lists)) {
					$this->error($label, sprintf('lista "%s" não existe.', $field['lista']));
				}

				$field['opcoes'] = [];
			}
			elseif (!$field['opcoes']) {
				$this->error($label, 'informe as opções ou escolha uma lista compartilhada.');
			}
		}

		if ($type === 'tag_value') {
			$field['tag'] = self::str($raw, 'tag');

			if ($field['tag'] === '') {
				$this->error($label, 'informe o nome da tag.');
			}
		}

		if ($type === 'zbx_hostgroup') {
			$field['prefixo'] = self::str($raw, 'prefixo');
		}

		if (in_array($type, self::MULTI_CAPABLE, true)) {
			$field['multiplo'] = self::bool($raw, 'multiplo', false);
		}

		if (in_array($type, self::ALLOWED_TYPES, true)) {
			$field['permitidos'] = self::normalizeStringList($raw['permitidos'] ?? []);
		}

		if ($type === 'zbx_template') {
			$field['grupo_templates'] = self::str($raw, 'grupo_templates');
		}

		$field['quando'] = $this->validateCondition($raw['quando'] ?? null, $label, $field_ids, $field['id']);

		$field['mapeamento'] = [];
		$raw_maps = (isset($raw['mapeamento']) && is_array($raw['mapeamento'])) ? array_values($raw['mapeamento']) : [];

		foreach ($raw_maps as $j => $raw_map) {
			$map = $this->validateMapping(is_array($raw_map) ? $raw_map : [], sprintf('%s, mapeamento #%d', $label, $j + 1),
				$field_ids
			);

			if ($map === null) {
				continue;
			}

			if ($map['alvo'] === 'hostid' && $type !== 'zbx_host') {
				$this->error($label, 'só um campo "Zabbix: host existente" pode mapear para "hostid".');
			}

			if ($map['alvo'] === 'operacao' && $form_type !== 'delete') {
				$this->error($label, '"operacao" só existe em formulários de exclusão.');
			}

			$field['mapeamento'][] = $map;
		}

		if ($type === 'tag_value' && !$field['mapeamento'] && $field['tag'] !== '') {
			$field['mapeamento'][] = ['alvo' => 'tag:'.$field['tag'], 'padrao' => ''];
		}

		return $field;
	}

	private function validateFixed(array $raw, int $i, array $field_ids): ?array {
		$label = sprintf('Valor fixo #%d', $i + 1);
		$map = $this->validateMapping($raw, $label, $field_ids, true);

		if ($map === null) {
			return null;
		}

		if ($map['alvo'] === 'hostid') {
			$this->error($label, '"hostid" não pode ser valor fixo.');
		}

		$map['quando'] = $this->validateCondition($raw['quando'] ?? null, $label, $field_ids, null);

		return $map;
	}

	private function validateMapping(array $raw, string $label, array $field_ids, bool $is_fixed = false): ?array {
		$target = self::str($raw, 'alvo');

		if ($target === '') {
			$this->error($label, 'alvo obrigatório.');

			return null;
		}

		if (!self::isValidTarget($target, $reason)) {
			$this->error($label, $reason);

			return null;
		}

		$map = ['alvo' => $target];

		if ($is_fixed) {
			$map['valor'] = self::str($raw, 'valor');
			$template = $map['valor'];

			if ($map['valor'] === '') {
				$this->error($label, 'valor obrigatório.');
			}
		}
		else {
			$map['padrao'] = self::str($raw, 'padrao');
			$template = $map['padrao'];
		}

		if (preg_match_all(self::PLACEHOLDER_PATTERN, $template, $m)) {
			foreach ($m[1] as $ref) {
				if (!in_array($ref, $field_ids, true)) {
					$this->error($label, sprintf('o padrão referencia o campo "{%s}", que não existe.', $ref));
				}
			}
		}

		if ($target === 'groups[]') {
			$map['modo'] = self::str($raw, 'modo') ?: 'adicionar';

			if (!in_array($map['modo'], self::GROUP_MODES, true)) {
				$this->error($label, 'modo de grupo inválido.');
			}

			if ($map['modo'] === 'substituir_prefixo') {
				$map['prefixo'] = self::str($raw, 'prefixo');

				if ($map['prefixo'] === '') {
					$this->error($label, 'o modo "substituir_prefixo" exige um prefixo.');
				}
			}
		}
		elseif ($target === 'templates[]') {
			$map['modo'] = self::str($raw, 'modo') ?: 'vincular';

			if (!in_array($map['modo'], self::TEMPLATE_MODES, true)) {
				$this->error($label, 'modo de template inválido.');
			}
		}

		if ($is_fixed && !preg_match(self::PLACEHOLDER_PATTERN, $map['valor'])) {
			$this->validateLiteralValue($target, $map['valor'], $label);
		}

		return $map;
	}

	private function validateLiteralValue(string $target, string $value, string $label): void {
		$enums = [
			'interface.type' => self::INTERFACE_TYPES,
			'host.status' => ['0', '1'],
			'interface.useip' => ['0', '1'],
			'interface.snmp.version' => ['1', '2', '3'],
			'interface.snmp.bulk' => ['0', '1'],
			'interface.snmp.securitylevel' => ['0', '1', '2'],
			'operacao' => self::OPERATIONS
		];

		if (array_key_exists($target, $enums) && !in_array($value, $enums[$target], true)) {
			$this->error($label, sprintf('valor de "%s" deve ser: %s.', $target, implode(', ', $enums[$target])));
		}

		if ($target === 'interface.ip' && filter_var($value, FILTER_VALIDATE_IP) === false) {
			$this->error($label, 'IP inválido.');
		}
	}

	/**
	 * Condição de exibição/aplicação:
	 *   {"logica": "e"|"ou", "regras": [{"campo": "x", "operador": "igual"|"diferente", "valores": ["a", "b"]}]}
	 *
	 * Uma regra "igual" é verdadeira se o campo tiver QUALQUER um dos valores; "diferente", se não tiver nenhum.
	 * As regras são combinadas com E (todas) ou OU (qualquer uma).
	 * O formato antigo {"campo": "x", "igual": "a"} é convertido automaticamente.
	 */
	private function validateCondition($raw, string $label, array $field_ids, ?string $self_id): ?array {
		if (!is_array($raw)) {
			return null;
		}

		if (array_key_exists('campo', $raw)) {
			$raw = [
				'logica' => 'e',
				'regras' => [[
					'campo' => $raw['campo'],
					'operador' => 'igual',
					'valores' => [self::str($raw, 'igual')]
				]]
			];
		}

		$logic = self::str($raw, 'logica') ?: 'e';

		if (!in_array($logic, self::CONDITION_LOGICS, true)) {
			$this->error($label, 'lógica da condição deve ser "e" ou "ou".');
			$logic = 'e';
		}

		$rules = [];

		foreach (is_array($raw['regras'] ?? null) ? array_values($raw['regras']) : [] as $k => $rule) {
			if (!is_array($rule) || self::str($rule, 'campo') === '') {
				continue;
			}

			$where = sprintf('%s, condição #%d', $label, $k + 1);
			$field = self::str($rule, 'campo');
			$operator = self::str($rule, 'operador') ?: 'igual';

			if (!in_array($field, $field_ids, true) || $field === $self_id) {
				$this->error($where, sprintf('referencia campo inválido "%s".', $field));
			}

			if (!in_array($operator, self::CONDITION_OPERATORS, true)) {
				$this->error($where, 'operador deve ser "igual" ou "diferente".');
			}

			$values = $rule['valores'] ?? [];

			if (is_string($values)) {
				$values = explode(',', $values);
			}

			$values = is_array($values) ? self::normalizeStringList($values) : [];

			if (!$values) {
				$this->error($where, 'informe pelo menos um valor.');
			}

			$rules[] = ['campo' => $field, 'operador' => $operator, 'valores' => $values];
		}

		return $rules ? ['logica' => $logic, 'regras' => $rules] : null;
	}

	private function validateTypeRules(array $form): void {
		$targets = [];

		foreach ($form['campos'] as $field) {
			foreach ($field['mapeamento'] as $map) {
				$targets[] = $map['alvo'];
			}
		}

		foreach ($form['valores_fixos'] as $fixed) {
			$targets[] = $fixed['alvo'];
		}

		$host_fields = array_filter($form['campos'], static function (array $f): bool {
			return $f['tipo'] === 'zbx_host';
		});

		$hostid_fields = array_filter($host_fields, static function (array $f): bool {
			return in_array('hostid', array_column($f['mapeamento'], 'alvo'), true);
		});

		if ($form['tipo'] === 'create') {
			if ($hostid_fields) {
				$this->error('Tipo', 'formulário de criação não pode ter campo mapeado para "hostid".');
			}

			if (!in_array('host.host', $targets, true)) {
				$this->error('Mapeamento', 'formulário de criação precisa mapear "host.host".');
			}

			if (!in_array('groups[]', $targets, true)) {
				$this->error('Mapeamento', 'formulário de criação precisa mapear ao menos um "groups[]".');
			}
		}
		elseif (array_key_exists($form['tipo'], self::FORM_TYPES)) {
			if (count($hostid_fields) !== 1) {
				$this->error('Host alvo', 'este tipo precisa de exatamente um campo "Zabbix: host existente" mapeado para "hostid".');
			}
			else {
				$host_field = reset($hostid_fields);

				if (!$host_field['obrigatorio'] || $host_field['quando'] !== null) {
					$this->error('Host alvo', 'o campo do host alvo deve ser obrigatório e sempre visível.');
				}
			}
		}

		if ($form['tipo'] === 'move' && !in_array('groups[]', $targets, true)) {
			$this->error('Mapeamento', 'formulário de movimentação precisa mapear "groups[]".');
		}
	}

	/**
	 * Confere, com a sessão de quem salva (Super admin), que objetos citados literalmente existem.
	 */
	private function validateZabbixObjects(array $form): void {
		$names = ['template' => [], 'proxy' => [], 'proxy_group' => [], 'group' => []];

		foreach ($form['campos'] as $field) {
			$allowed = $field['permitidos'] ?? [];

			if ($field['tipo'] === 'zbx_template') {
				$names['template'] = array_merge($names['template'], $allowed);
			}
			elseif ($field['tipo'] === 'zbx_proxy') {
				$names['proxy'] = array_merge($names['proxy'], $allowed);
			}
			elseif ($field['tipo'] === 'zbx_proxy_group') {
				$names['proxy_group'] = array_merge($names['proxy_group'], $allowed);
			}
		}

		foreach ($form['valores_fixos'] as $fixed) {
			if (preg_match(self::PLACEHOLDER_PATTERN, $fixed['valor'])) {
				continue;
			}

			$kind = [
				'templates[]' => 'template',
				'proxy' => 'proxy',
				'proxy_group' => 'proxy_group',
				'groups[]' => 'group'
			][$fixed['alvo']] ?? null;

			if ($kind !== null) {
				$names[$kind][] = $fixed['valor'];
			}
		}

		$missing = [
			'template' => ZabbixLookup::missingTemplates(array_unique($names['template'])),
			'proxy' => ZabbixLookup::missingProxies(array_unique($names['proxy'])),
			'proxy_group' => ZabbixLookup::missingProxyGroups(array_unique($names['proxy_group'])),
			'group' => ZabbixLookup::missingHostGroups(array_unique($names['group']))
		];

		$labels = [
			'template' => 'Templates não encontrados',
			'proxy' => 'Proxies não encontrados',
			'proxy_group' => 'Grupos de proxies não encontrados',
			'group' => 'Grupos de hosts não encontrados'
		];

		foreach ($missing as $kind => $list) {
			if ($list) {
				$this->error($labels[$kind], implode(', ', $list));
			}
		}
	}

	/**
	 * Converte condições do formato antigo ({campo, igual}) para o atual, sem validar.
	 * Usado na leitura de formulários gravados antes da mudança.
	 */
	public static function upgradeForm(array $form): array {
		foreach (['campos', 'valores_fixos'] as $section) {
			foreach ($form[$section] ?? [] as $i => $item) {
				$cond = $item['quando'] ?? null;

				if (is_array($cond) && array_key_exists('campo', $cond)) {
					$form[$section][$i]['quando'] = ($cond['campo'] === '') ? null : [
						'logica' => 'e',
						'regras' => [[
							'campo' => (string) $cond['campo'],
							'operador' => 'igual',
							'valores' => [(string) ($cond['igual'] ?? '')]
						]]
					];
				}
			}
		}

		return $form;
	}

	public static function isValidTarget(string $target, ?string &$reason = null): bool {
		$reason = null;

		if (array_key_exists($target, self::TARGETS)) {
			return true;
		}

		if (strpos($target, 'tag:') === 0) {
			$name = substr($target, 4);

			if ($name === '' || mb_strlen($name) > 255) {
				$reason = 'nome de tag inválido.';

				return false;
			}

			return true;
		}

		if (strpos($target, 'macro:') === 0) {
			if (!preg_match(self::MACRO_PATTERN, substr($target, 6))) {
				$reason = 'macro deve ter o formato {$NOME} (A-Z, 0-9, "_" e ".").';

				return false;
			}

			return true;
		}

		if (strpos($target, 'inventory.') === 0) {
			$name = substr($target, 10);
			$fields = self::inventoryFields();

			if ($fields !== null ? !in_array($name, $fields, true) : !preg_match('/^[a-z_0-9]+$/', $name)) {
				$reason = sprintf('campo de inventário "%s" não existe.', $name);

				return false;
			}

			return true;
		}

		$reason = sprintf('alvo "%s" desconhecido.', $target);

		return false;
	}

	public static function inventoryFields(): ?array {
		if (!function_exists('getHostInventories')) {
			return null;
		}

		return array_values(array_column(getHostInventories(), 'db_field'));
	}

	public static function isValidRegex(string $regex): bool {
		return @preg_match(self::wrapRegex($regex), '') !== false;
	}

	public static function wrapRegex(string $regex): string {
		return '/'.str_replace('/', '\/', $regex).'/u';
	}

	/**
	 * Aceita [{valor, rotulo}] ou ["valor", ...].
	 */
	public static function normalizeOptions($raw): array {
		if (!is_array($raw)) {
			return [];
		}

		$options = [];
		$seen = [];

		foreach ($raw as $item) {
			if (is_array($item)) {
				$value = trim((string) ($item['valor'] ?? ''));
				$label = trim((string) ($item['rotulo'] ?? ''));
			}
			else {
				$value = trim((string) $item);
				$label = '';
			}

			if ($value === '' || array_key_exists($value, $seen)) {
				continue;
			}

			$seen[$value] = true;
			$options[] = ['valor' => $value, 'rotulo' => ($label !== '') ? $label : $value];
		}

		return $options;
	}

	public static function normalizeStringList($raw): array {
		if (is_string($raw)) {
			$raw = preg_split('/\r\n|\r|\n/', $raw);
		}

		if (!is_array($raw)) {
			return [];
		}

		$list = [];

		foreach ($raw as $item) {
			$item = trim((string) $item);

			if ($item !== '' && !in_array($item, $list, true)) {
				$list[] = $item;
			}
		}

		return $list;
	}

	private static function str(array $a, string $key): string {
		return (array_key_exists($key, $a) && is_scalar($a[$key])) ? trim((string) $a[$key]) : '';
	}

	private static function bool(array $a, string $key, bool $default): bool {
		if (!array_key_exists($key, $a)) {
			return $default;
		}

		return in_array($a[$key], [true, 1, '1', 'true', 'on'], true);
	}

	private function error(string $where, string $message): void {
		$this->errors[] = $where.': '.$message;
	}
}
