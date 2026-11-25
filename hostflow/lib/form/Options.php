<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

/**
 * Resolve as opções válidas de um campo: lista estática, lista compartilhada ou objetos do Zabbix
 * visíveis ao usuário. É a mesma fonte para renderizar o formulário e para validar o envio,
 * então o usuário nunca consegue mandar um valor fora da lista.
 */
final class Options {

	private array $lists;

	public function __construct(array $lists) {
		$this->lists = $lists;
	}

	/**
	 * @return array<int, array{valor: string, rotulo: string, attrs: array}>|null  null = campo sem lista fechada.
	 */
	public function forField(array $field): ?array {
		switch ($field['tipo']) {
			case 'select':
			case 'multiselect':
			case 'tag_value':
				if (($field['lista'] ?? '') !== '') {
					$list = $this->lists[$field['lista']] ?? ['itens' => []];

					return array_map(static function (array $item): array {
						return [
							'valor' => (string) $item['valor'],
							'rotulo' => (string) ($item['rotulo'] ?? $item['valor']),
							'attrs' => (array) ($item['attrs'] ?? [])
						];
					}, $list['itens']);
				}

				return array_map(static function (array $o): array {
					return $o + ['attrs' => []];
				}, $field['opcoes'] ?? []);

			case 'zbx_hostgroup':
				return self::names(ZabbixLookup::hostGroupNames($field['prefixo'] ?? ''));

			case 'zbx_template':
				if (!empty($field['permitidos'])) {
					return self::names($field['permitidos']);
				}

				if (($field['grupo_templates'] ?? '') !== '') {
					return self::names(ZabbixLookup::templateNamesInGroup($field['grupo_templates']));
				}

				return [];

			case 'zbx_proxy':
				return self::names(!empty($field['permitidos']) ? $field['permitidos'] : ZabbixLookup::proxyNames());

			case 'zbx_proxy_group':
				return self::names(!empty($field['permitidos'])
					? $field['permitidos']
					: ZabbixLookup::proxyGroupNames()
				);
		}

		return null;
	}

	public function attrsOf(array $field, string $value): array {
		foreach ($this->forField($field) ?? [] as $option) {
			if ($option['valor'] === $value) {
				return $option['attrs'];
			}
		}

		return [];
	}

	public static function isMulti(array $field): bool {
		return $field['tipo'] === 'multiselect'
			|| (in_array($field['tipo'], FormSchema::MULTI_CAPABLE, true) && !empty($field['multiplo']));
	}

	private static function names(array $names): array {
		return array_map(static function (string $name): array {
			return ['valor' => $name, 'rotulo' => $name, 'attrs' => []];
		}, array_values($names));
	}
}
