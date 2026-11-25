<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

use API;

/**
 * Estado normalizado de um host, a mesclagem de um payload sobre ele e o diff atual × proposto.
 *
 * A mesclagem segue a semântica que a execução vai precisar respeitar, porque host.update do Zabbix
 * SUBSTITUI groups/tags/templates/macros inteiros: aqui só muda o que o payload pede.
 */
final class HostState {

	private const INTERFACE_TYPES = [1 => 'agent', 2 => 'snmp', 3 => 'ipmi', 4 => 'jmx'];
	private const SNMP_KEYS = ['version', 'bulk', 'community', 'securityname', 'securitylevel', 'authprotocol',
		'authpassphrase', 'privprotocol', 'privpassphrase', 'contextname', 'max_repetitions'
	];
	private const SECRET_SNMP_KEYS = ['community', 'authpassphrase', 'privpassphrase'];

	public static function emptyState(): array {
		return [
			'hostid' => null,
			'host' => ['host' => '', 'name' => '', 'description' => '', 'status' => '0'],
			'interface' => [],
			'groups' => [],
			'templates' => [],
			'proxy' => null,
			'proxy_group' => null,
			'tags' => [],
			'macros' => [],
			'inventory' => [],
			'excluir' => false
		];
	}

	/**
	 * Lê o host com a sessão atual. null se não existe ou o usuário não enxerga.
	 */
	public static function read(string $hostid): ?array {
		if (!ctype_digit($hostid)) {
			return null;
		}

		$hosts = API::Host()->get([
			'output' => ['hostid', 'host', 'name', 'description', 'status', 'monitored_by', 'proxyid',
				'proxy_groupid'
			],
			'selectHostGroups' => ['name'],
			'selectParentTemplates' => ['name'],
			'selectTags' => ['tag', 'value'],
			'selectMacros' => ['macro', 'value', 'type'],
			'selectInterfaces' => ['type', 'main', 'ip', 'dns', 'port', 'useip', 'details'],
			'selectInventory' => 'extend',
			'hostids' => [$hostid]
		]);

		if (!$hosts) {
			return null;
		}

		$db = $hosts[0];
		$state = self::emptyState();

		$state['hostid'] = $db['hostid'];
		$state['host'] = [
			'host' => $db['host'],
			'name' => $db['name'],
			'description' => $db['description'],
			'status' => (string) $db['status']
		];

		$state['groups'] = array_column($db['hostgroups'] ?? [], 'name');
		sort($state['groups']);

		$state['templates'] = array_column($db['parentTemplates'] ?? [], 'name');
		sort($state['templates']);

		foreach ($db['tags'] ?? [] as $tag) {
			$state['tags'][$tag['tag']][] = $tag['value'];
		}

		foreach ($db['macros'] ?? [] as $macro) {
			// Macros secretas (type 1) não têm valor legível.
			$state['macros'][$macro['macro']] = ((int) ($macro['type'] ?? 0) === 1) ? '******' : $macro['value'];
		}

		foreach ((array) ($db['inventory'] ?? []) as $key => $value) {
			if ($key !== 'hostid' && $key !== 'inventory_mode' && $value !== '') {
				$state['inventory'][$key] = $value;
			}
		}

		$state['interface'] = self::mainInterface($db['interfaces'] ?? []);

		$monitored_by = (int) ($db['monitored_by'] ?? 0);

		if ($monitored_by === 1 && $db['proxyid'] != 0) {
			$rows = API::Proxy()->get(['output' => ['name'], 'proxyids' => [$db['proxyid']]]);
			$state['proxy'] = $rows ? $rows[0]['name'] : '#'.$db['proxyid'];
		}
		elseif ($monitored_by === 2 && $db['proxy_groupid'] != 0) {
			$rows = API::ProxyGroup()->get(['output' => ['name'], 'proxy_groupids' => [$db['proxy_groupid']]]);
			$state['proxy_group'] = $rows ? $rows[0]['name'] : '#'.$db['proxy_groupid'];
		}

		return $state;
	}

	/**
	 * Interface principal: a "main" do primeiro tipo disponível na ordem agent, snmp, jmx, ipmi.
	 */
	private static function mainInterface(array $interfaces): array {
		foreach ([1, 2, 4, 3] as $type) {
			foreach ($interfaces as $interface) {
				if ((int) $interface['type'] === $type && (int) $interface['main'] === 1) {
					$result = [
						'type' => self::INTERFACE_TYPES[$type],
						'ip' => $interface['ip'],
						'dns' => $interface['dns'],
						'port' => $interface['port'],
						'useip' => (string) $interface['useip']
					];

					if ($type === 2 && is_array($interface['details'] ?? null)) {
						foreach (self::SNMP_KEYS as $key) {
							if (array_key_exists($key, $interface['details'])) {
								$result['snmp'][$key] = (string) $interface['details'][$key];
							}
						}
					}

					return $result;
				}
			}
		}

		return [];
	}

	/**
	 * Aplica o payload sobre o estado (sem tocar no Zabbix).
	 */
	public static function apply(array $state, array $payload): array {
		foreach ($payload['host'] ?? [] as $key => $value) {
			$state['host'][$key] = $value;
		}

		if (!empty($payload['interface'])) {
			$snmp = $payload['interface']['snmp'] ?? [];
			unset($payload['interface']['snmp']);

			$state['interface'] = array_replace($state['interface'], $payload['interface']);

			if ($snmp) {
				$state['interface']['snmp'] = array_replace($state['interface']['snmp'] ?? [], $snmp);
			}
		}

		if (!empty($payload['groups'])) {
			foreach ($payload['groups']['substituir'] ?? [] as $prefix => $names) {
				$state['groups'] = array_values(array_filter($state['groups'], static function ($g) use ($prefix) {
					return strpos($g, (string) $prefix) !== 0;
				}));
				$state['groups'] = array_merge($state['groups'], $names);
			}

			$state['groups'] = array_merge($state['groups'], $payload['groups']['adicionar'] ?? []);
			$state['groups'] = array_values(array_unique($state['groups']));
			sort($state['groups']);
		}

		if (!empty($payload['templates'])) {
			$state['templates'] = array_values(array_diff(
				array_unique(array_merge($state['templates'], $payload['templates']['vincular'] ?? [])),
				$payload['templates']['desvincular'] ?? []
			));
			sort($state['templates']);
		}

		if (array_key_exists('proxy', $payload)) {
			$state['proxy'] = $payload['proxy'];
			$state['proxy_group'] = null;
		}

		if (array_key_exists('proxy_group', $payload)) {
			$state['proxy_group'] = $payload['proxy_group'];
			$state['proxy'] = null;
		}

		foreach ($payload['tags'] ?? [] as $tag => $values) {
			$state['tags'][$tag] = $values;
		}

		ksort($state['tags']);

		foreach ($payload['macros'] ?? [] as $macro => $value) {
			$state['macros'][$macro] = $value;
		}

		foreach ($payload['inventory'] ?? [] as $key => $value) {
			$state['inventory'][$key] = $value;
		}

		$operation = $payload['operacao'] ?? null;

		if ($operation === 'excluir') {
			$state['excluir'] = true;
		}
		elseif ($operation === 'desativar' && !isset($payload['host']['status'])) {
			$state['host']['status'] = '1';
		}

		return $state;
	}

	/**
	 * Achata o estado em "atributo" => "texto" para exibição e diff.
	 */
	public static function flatten(array $state, bool $mask_secrets = true): array {
		$flat = [];

		foreach (['host', 'name', 'description', 'status'] as $key) {
			$flat['host.'.$key] = (string) ($state['host'][$key] ?? '');
		}

		foreach (['type', 'ip', 'dns', 'port', 'useip'] as $key) {
			$flat['interface.'.$key] = (string) ($state['interface'][$key] ?? '');
		}

		foreach ($state['interface']['snmp'] ?? [] as $key => $value) {
			$flat['interface.snmp.'.$key] = ($mask_secrets && in_array($key, self::SECRET_SNMP_KEYS, true)
					&& $value !== '' && strpos((string) $value, '{$') !== 0)
				? '******'
				: (string) $value;
		}

		$flat['groups[]'] = implode("\n", $state['groups']);
		$flat['templates[]'] = implode("\n", $state['templates']);
		$flat['proxy'] = (string) ($state['proxy'] ?? '');
		$flat['proxy_group'] = (string) ($state['proxy_group'] ?? '');

		foreach ($state['tags'] as $tag => $values) {
			$flat['tag:'.$tag] = implode("\n", $values);
		}

		foreach ($state['macros'] as $macro => $value) {
			$flat['macro:'.$macro] = (string) $value;
		}

		foreach ($state['inventory'] as $key => $value) {
			$flat['inventory.'.$key] = (string) $value;
		}

		return $flat;
	}

	/**
	 * @return array<int, array{atributo: string, atual: string, proposto: string}>
	 */
	public static function diff(array $before, array $after): array {
		if (!empty($after['excluir'])) {
			return [['atributo' => 'host', 'atual' => $before['host']['host'] ?? '', 'proposto' => '(EXCLUIR HOST)']];
		}

		$a = self::flatten($before);
		$b = self::flatten($after);
		$rows = [];

		foreach (array_unique(array_merge(array_keys($a), array_keys($b))) as $key) {
			$old = $a[$key] ?? '';
			$new = $b[$key] ?? '';

			if ($old !== $new) {
				$rows[] = ['atributo' => $key, 'atual' => $old, 'proposto' => $new];
			}
		}

		return $rows;
	}

	/**
	 * Valor atual de um alvo, para pré-preencher formulários de update/move/delete.
	 *
	 * @return string|string[]|null
	 */
	public static function valueOf(array $state, string $target) {
		if (strpos($target, 'host.') === 0) {
			return $state['host'][substr($target, 5)] ?? null;
		}

		if (strpos($target, 'interface.snmp.') === 0) {
			return $state['interface']['snmp'][substr($target, 15)] ?? null;
		}

		if (strpos($target, 'interface.') === 0) {
			return $state['interface'][substr($target, 10)] ?? null;
		}

		switch ($target) {
			case 'groups[]':
				return $state['groups'];

			case 'templates[]':
				return $state['templates'];

			case 'proxy':
			case 'proxy_group':
			case 'hostid':
				return $state[$target];
		}

		if (strpos($target, 'tag:') === 0) {
			return $state['tags'][substr($target, 4)] ?? null;
		}

		if (strpos($target, 'macro:') === 0) {
			return $state['macros'][substr($target, 6)] ?? null;
		}

		if (strpos($target, 'inventory.') === 0) {
			return $state['inventory'][substr($target, 10)] ?? null;
		}

		return null;
	}

	/**
	 * Pré-preenchimento: para cada campo, usa o primeiro mapeamento. Se ele tem padrão
	 * (ex.: "Sites/{site.regiao}/{site}/Switches"), extrai o valor do campo por regex.
	 *
	 * @return array<string, string|string[]>
	 */
	public static function prefill(array $form, array $state, Options $options): array {
		$values = [];

		foreach ($form['campos'] as $field) {
			if ($field['tipo'] === 'zbx_host' || !$field['mapeamento']) {
				continue;
			}

			$map = $field['mapeamento'][0];
			$current = self::valueOf($state, $map['alvo']);

			if ($current === null || $current === '' || $current === []) {
				continue;
			}

			$candidates = (array) $current;

			if ($map['alvo'] === 'groups[]' && ($map['modo'] ?? '') === 'substituir_prefixo') {
				$candidates = array_values(array_filter($candidates, static function ($g) use ($map) {
					return strpos($g, $map['prefixo']) === 0;
				}));
			}

			$found = [];

			if (($map['padrao'] ?? '') === '') {
				$found = $candidates;
			}
			else {
				$regex = self::reversePattern($map['padrao'], $field['id']);

				foreach ($candidates as $candidate) {
					if (preg_match($regex, (string) $candidate, $m) && isset($m['v']) && $m['v'] !== '') {
						$found[] = $m['v'];
					}
				}
			}

			$allowed = $options->forField($field);

			if ($allowed !== null) {
				$allowed_values = array_column($allowed, 'valor');
				$found = array_values(array_filter($found, static function ($v) use ($allowed_values) {
					return in_array((string) $v, $allowed_values, true);
				}));
			}

			if (!$found) {
				continue;
			}

			$values[$field['id']] = Options::isMulti($field)
				? array_values(array_unique(array_map('strval', $found)))
				: (string) $found[0];
		}

		return $values;
	}

	/**
	 * Converte o padrão em regex: {campo} vira o grupo de captura "v", outros placeholders viram coringa.
	 */
	private static function reversePattern(string $pattern, string $field_id): string {
		$regex = '';
		$offset = 0;
		$captured = false;

		preg_match_all(FormSchema::PLACEHOLDER_PATTERN, $pattern, $matches, PREG_OFFSET_CAPTURE | PREG_SET_ORDER);

		foreach ($matches as $m) {
			$regex .= preg_quote(substr($pattern, $offset, $m[0][1] - $offset), '/');

			$has_attr = isset($m[2]) && $m[2][1] !== -1;
			$is_self = ($m[1][0] === $field_id && !$has_attr);

			// Coringa preguiçoso: valores podem conter "/" (ex.: "Switch/Core"); o resultado ainda é
			// filtrado pelas opções válidas do campo.
			if ($is_self && !$captured) {
				$regex .= '(?P<v>.+?)';
				$captured = true;
			}
			else {
				$regex .= '.+?';
			}

			$offset = $m[0][1] + strlen($m[0][0]);
		}

		$regex .= preg_quote(substr($pattern, $offset), '/');

		return '/^'.$regex.'$/u';
	}
}
