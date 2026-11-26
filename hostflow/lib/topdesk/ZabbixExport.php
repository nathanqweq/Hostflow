<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Topdesk;

use Modules\HostFlow\Lib\Form\HostState;

/**
 * Gera o arquivo de importação do Zabbix 7.4 (Data collection › Hosts › Import) para o host de uma
 * solicitação de criação. Grupos inexistentes são criados se "Create new" estiver marcado na importação;
 * templates precisam existir.
 */
final class ZabbixExport {

	public const SECRET_PLACEHOLDER = '******';

	private const INTERFACE_TYPES = ['agent' => 'ZABBIX', 'snmp' => 'SNMP', 'ipmi' => 'IPMI', 'jmx' => 'JMX'];
	private const DEFAULT_PORTS = ['agent' => '10050', 'snmp' => '161', 'ipmi' => '623', 'jmx' => '12345'];
	private const SNMP_ENUMS = [
		'version' => ['1' => 'SNMPV1', '2' => 'SNMPV2', '3' => 'SNMPV3'],
		'bulk' => ['0' => 'NO', '1' => 'YES'],
		'securitylevel' => ['0' => 'NOAUTHNOPRIV', '1' => 'AUTHNOPRIV', '2' => 'AUTHPRIV'],
		'authprotocol' => ['0' => 'MD5', '1' => 'SHA1', '2' => 'SHA224', '3' => 'SHA256', '4' => 'SHA384',
			'5' => 'SHA512'
		],
		'privprotocol' => ['0' => 'DES', '1' => 'AES128', '2' => 'AES192', '3' => 'AES256', '4' => 'AES192C',
			'5' => 'AES256C'
		]
	];
	private const SECRET_SNMP_KEYS = ['community', 'authpassphrase', 'privpassphrase'];

	/**
	 * @param array $payload       payload da solicitação (PayloadBuilder)
	 * @param bool  $with_secrets  false = community/passphrases literais viram "******" (macros {$...} são mantidas)
	 */
	public static function build(array $payload, bool $with_secrets): array {
		$state = HostState::apply(HostState::emptyState(), $payload);
		$host = [
			'host' => $state['host']['host'],
			'name' => ($state['host']['name'] !== '') ? $state['host']['name'] : $state['host']['host'],
			'status' => ((string) $state['host']['status'] === '1') ? 'DISABLED' : 'ENABLED'
		];

		if ($state['host']['description'] !== '') {
			$host['description'] = $state['host']['description'];
		}

		if ($state['proxy'] !== null) {
			$host['monitored_by'] = 'PROXY';
			$host['proxy'] = ['name' => $state['proxy']];
		}
		elseif ($state['proxy_group'] !== null) {
			$host['monitored_by'] = 'PROXY_GROUP';
			$host['proxy_group'] = ['name' => $state['proxy_group']];
		}

		if ($state['templates']) {
			$host['templates'] = array_map(static function (string $name): array {
				return ['name' => $name];
			}, $state['templates']);
		}

		$host['groups'] = array_map(static function (string $name): array {
			return ['name' => $name];
		}, $state['groups']);

		if ($state['interface']) {
			$host['interfaces'] = [self::interface($state['interface'], $with_secrets)];
		}

		foreach ($state['tags'] as $tag => $values) {
			foreach ($values ?: [''] as $value) {
				$host['tags'][] = ['tag' => (string) $tag, 'value' => (string) $value];
			}
		}

		foreach ($state['macros'] as $macro => $value) {
			$host['macros'][] = ['macro' => (string) $macro, 'value' => (string) $value];
		}

		if ($state['inventory']) {
			$host['inventory_mode'] = 'MANUAL';
			$host['inventory'] = array_map('strval', $state['inventory']);
		}

		return [
			'zabbix_export' => [
				'version' => '7.4',
				'host_groups' => array_map(static function (string $name): array {
					// A importação exige uuid (v4, 32 hex) nos grupos; derivado do nome para ser estável.
					return ['uuid' => self::uuid('hostflow-group:'.$name), 'name' => $name];
				}, $state['groups']),
				'hosts' => [$host]
			]
		];
	}

	private static function uuid(string $seed): string {
		$h = md5($seed);
		$h[12] = '4';
		$h[16] = '89ab'[hexdec($h[16]) & 3];

		return $h;
	}

	private static function interface(array $if, bool $with_secrets): array {
		$type = $if['type'] ?? 'agent';
		$useip = (string) ($if['useip'] ?? (($if['ip'] ?? '') !== '' ? '1' : '0'));

		$result = [
			'type' => self::INTERFACE_TYPES[$type] ?? strtoupper((string) $type),
			'useip' => ($useip === '0') ? 'NO' : 'YES'
		];

		if (($if['ip'] ?? '') !== '') {
			$result['ip'] = $if['ip'];
		}

		if (($if['dns'] ?? '') !== '') {
			$result['dns'] = $if['dns'];
		}

		$result['port'] = (($if['port'] ?? '') !== '') ? (string) $if['port'] : (self::DEFAULT_PORTS[$type] ?? '');

		if ($type === 'snmp') {
			$details = [];

			foreach ($if['snmp'] ?? [] as $key => $value) {
				$value = (string) $value;

				if (isset(self::SNMP_ENUMS[$key])) {
					$value = self::SNMP_ENUMS[$key][$value] ?? strtoupper($value);
				}
				elseif (!$with_secrets && in_array($key, self::SECRET_SNMP_KEYS, true) && $value !== ''
						&& strpos($value, '{$') !== 0) {
					$value = self::SECRET_PLACEHOLDER;
				}

				$details[$key] = $value;
			}

			if ($details) {
				$result['details'] = $details;
			}
		}

		$result['interface_ref'] = 'if1';

		return $result;
	}
}
