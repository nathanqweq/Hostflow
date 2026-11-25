<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

use API;

/**
 * Consultas à API interna do frontend. Todas rodam com a sessão do usuário logado,
 * então só retornam o que ele tem permissão de ler.
 */
final class ZabbixLookup {

	private static array $cache = [];

	/**
	 * @return string[]  Nomes de grupos de hosts visíveis que começam com $prefix.
	 */
	public static function hostGroupNames(string $prefix = ''): array {
		return self::cached('hg:'.$prefix, static function () use ($prefix): array {
			$options = ['output' => ['name'], 'sortfield' => 'name'];

			if ($prefix !== '') {
				$options['search'] = ['name' => $prefix];
				$options['startSearch'] = true;
			}

			$rows = API::HostGroup()->get($options);

			$names = is_array($rows) ? array_column($rows, 'name') : [];

			// startSearch não diferencia maiúsculas; garante o prefixo exato.
			return array_values(array_filter($names, static function (string $name) use ($prefix): bool {
				return $prefix === '' || strpos($name, $prefix) === 0;
			}));
		});
	}

	public static function templateNamesInGroup(string $group_name): array {
		return self::cached('tg:'.$group_name, static function () use ($group_name): array {
			$groups = API::TemplateGroup()->get(['output' => ['groupid'], 'filter' => ['name' => $group_name]]);

			if (!$groups) {
				return [];
			}

			$rows = API::Template()->get([
				'output' => ['name'],
				'groupids' => array_column($groups, 'groupid'),
				'sortfield' => 'name'
			]);

			return is_array($rows) ? array_column($rows, 'name') : [];
		});
	}

	public static function proxyNames(): array {
		return self::cached('px', static function (): array {
			$rows = API::Proxy()->get(['output' => ['name'], 'sortfield' => 'name']);

			return is_array($rows) ? array_column($rows, 'name') : [];
		});
	}

	public static function proxyGroupNames(): array {
		return self::cached('pg', static function (): array {
			$rows = API::ProxyGroup()->get(['output' => ['name'], 'sortfield' => 'name']);

			return is_array($rows) ? array_column($rows, 'name') : [];
		});
	}

	public static function missingTemplates(array $names): array {
		return self::missing($names, static function (array $names) {
			return API::Template()->get(['output' => ['name'], 'filter' => ['name' => $names]]);
		});
	}

	public static function missingProxies(array $names): array {
		return self::missing($names, static function (array $names) {
			return API::Proxy()->get(['output' => ['name'], 'filter' => ['name' => $names]]);
		});
	}

	public static function missingProxyGroups(array $names): array {
		return self::missing($names, static function (array $names) {
			return API::ProxyGroup()->get(['output' => ['name'], 'filter' => ['name' => $names]]);
		});
	}

	public static function missingHostGroups(array $names): array {
		return self::missing($names, static function (array $names) {
			return API::HostGroup()->get(['output' => ['name'], 'filter' => ['name' => $names]]);
		});
	}

	/**
	 * @return array|null  ['hostid', 'host', 'name'] ou null se não existe ou o usuário não enxerga.
	 */
	public static function host(string $hostid): ?array {
		if (!ctype_digit($hostid)) {
			return null;
		}

		$rows = API::Host()->get(['output' => ['hostid', 'host', 'name'], 'hostids' => [$hostid]]);

		return $rows ? $rows[0] : null;
	}

	/**
	 * Hosts com esse nome técnico (entre os que o usuário enxerga).
	 */
	public static function hostsByTechnicalName(string $host): array {
		$rows = API::Host()->get(['output' => ['hostid', 'host', 'name'], 'filter' => ['host' => $host]]);

		return is_array($rows) ? $rows : [];
	}

	public static function hostsByVisibleName(string $name): array {
		$rows = API::Host()->get(['output' => ['hostid', 'host', 'name'], 'filter' => ['name' => $name]]);

		return is_array($rows) ? $rows : [];
	}

	/**
	 * Hosts que já têm interface com esse IP (entre os que o usuário enxerga).
	 */
	public static function hostsWithIp(string $ip): array {
		$interfaces = API::HostInterface()->get(['output' => ['hostid'], 'filter' => ['ip' => $ip]]);

		if (!$interfaces) {
			return [];
		}

		$rows = API::Host()->get([
			'output' => ['hostid', 'host', 'name'],
			'hostids' => array_unique(array_column($interfaces, 'hostid'))
		]);

		return is_array($rows) ? $rows : [];
	}

	private static function missing(array $names, callable $fetch): array {
		$names = array_values(array_filter($names, 'strlen'));

		if (!$names) {
			return [];
		}

		$rows = $fetch($names);
		$found = is_array($rows) ? array_column($rows, 'name') : [];

		return array_values(array_diff($names, $found));
	}

	private static function cached(string $key, callable $fn): array {
		if (!array_key_exists($key, self::$cache)) {
			self::$cache[$key] = $fn();
		}

		return self::$cache[$key];
	}
}
