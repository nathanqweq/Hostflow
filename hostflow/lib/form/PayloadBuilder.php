<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

/**
 * Converte valores do formulário + mapeamentos + valores fixos em um "payload" de host:
 *
 * {
 *   "hostid": "10601",                         (update/move/delete)
 *   "operacao": "desativar",                   (delete)
 *   "host": {"host": "...", "name": "...", "description": "...", "status": "0"},
 *   "interface": {"type": "snmp", "ip": "...", "port": "161", "snmp": {"version": "2", "community": "..."}},
 *   "groups": {"adicionar": ["A/B"], "substituir": {"Sites/": ["Sites/X/Y"]}},
 *   "templates": {"vincular": ["T1"], "desvincular": []},
 *   "proxy": "proxy-x" | "proxy_group": "grupo-x",
 *   "tags": {"categoria": ["REDE"]},
 *   "macros": {"{$SNMP_COMMUNITY}": "..."},
 *   "inventory": {"location": "..."}
 * }
 *
 * O payload é declarativo (o que deve mudar). Quem aplica a mesclagem com o estado atual é HostState::apply().
 */
final class PayloadBuilder {

	private array $form;
	private Options $options;
	private array $fields_by_id = [];

	public function __construct(array $form, Options $options) {
		$this->form = $form;
		$this->options = $options;

		foreach ($form['campos'] as $field) {
			$this->fields_by_id[$field['id']] = $field;
		}
	}

	public static function emptyPayload(): array {
		return [
			'host' => [],
			'interface' => [],
			'groups' => ['adicionar' => [], 'substituir' => []],
			'templates' => ['vincular' => [], 'desvincular' => []],
			'tags' => [],
			'macros' => [],
			'inventory' => []
		];
	}

	/**
	 * @param array $values  Valores validados (Submission::getValues()); null = campo oculto.
	 */
	public function build(array $values): array {
		$payload = self::emptyPayload();

		foreach ($this->form['campos'] as $field) {
			$value = $values[$field['id']] ?? null;

			if ($value === null || $value === '' || $value === []) {
				continue;
			}

			foreach ($field['mapeamento'] as $map) {
				foreach ((array) $value as $single) {
					$resolved = ($map['padrao'] ?? '') === ''
						? $single
						: $this->resolve($map['padrao'], $values, $field['id'], $single);

					if ($resolved !== null && $resolved !== '') {
						self::apply($payload, $map, $resolved);
					}

					if (!in_array($map['alvo'], ['groups[]', 'templates[]'], true)
							&& strpos($map['alvo'], 'tag:') !== 0) {
						// Alvos de valor único usam só o primeiro valor de um campo múltiplo.
						break;
					}
				}
			}
		}

		foreach ($this->form['valores_fixos'] as $fixed) {
			if (!Submission::isVisible($fixed, $values)) {
				continue;
			}

			$resolved = $this->resolve($fixed['valor'], $values, null, null);

			if ($resolved !== null && $resolved !== '') {
				self::apply($payload, $fixed, $resolved);
			}
		}

		return self::cleanup($payload);
	}

	/**
	 * Substitui {campo} e {campo.atributo}. Retorna null se algum placeholder ficar vazio,
	 * para nunca gerar algo como "Sites//Switches".
	 */
	private function resolve(string $template, array $values, ?string $self_id, ?string $self_value): ?string {
		$failed = false;

		$result = preg_replace_callback(FormSchema::PLACEHOLDER_PATTERN,
			function (array $m) use ($values, $self_id, $self_value, &$failed): string {
				$ref = $m[1];
				$attr = $m[2] ?? '';

				if ($ref === $self_id) {
					$value = $self_value;
				}
				else {
					$value = $values[$ref] ?? null;
					$value = is_array($value) ? (reset($value) ?: null) : $value;
				}

				if ($value === null || $value === '') {
					$failed = true;

					return '';
				}

				if ($attr === '') {
					return (string) $value;
				}

				$field = $this->fields_by_id[$ref] ?? null;
				$attrs = ($field !== null) ? $this->options->attrsOf($field, (string) $value) : [];

				if (!array_key_exists($attr, $attrs) || (string) $attrs[$attr] === '') {
					$failed = true;

					return '';
				}

				return (string) $attrs[$attr];
			},
			$template
		);

		return $failed ? null : $result;
	}

	private static function apply(array &$payload, array $map, string $value): void {
		$target = $map['alvo'];

		if (strpos($target, 'host.') === 0) {
			$payload['host'][substr($target, 5)] = $value;
		}
		elseif (strpos($target, 'interface.snmp.') === 0) {
			$payload['interface']['snmp'][substr($target, 15)] = $value;
		}
		elseif (strpos($target, 'interface.') === 0) {
			$payload['interface'][substr($target, 10)] = $value;
		}
		elseif ($target === 'groups[]') {
			if (($map['modo'] ?? 'adicionar') === 'substituir_prefixo') {
				$prefix = $map['prefixo'];

				if (!in_array($value, $payload['groups']['substituir'][$prefix] ?? [], true)) {
					$payload['groups']['substituir'][$prefix][] = $value;
				}
			}
			elseif (!in_array($value, $payload['groups']['adicionar'], true)) {
				$payload['groups']['adicionar'][] = $value;
			}
		}
		elseif ($target === 'templates[]') {
			$mode = $map['modo'] ?? 'vincular';

			if (!in_array($value, $payload['templates'][$mode], true)) {
				$payload['templates'][$mode][] = $value;
			}
		}
		elseif ($target === 'proxy') {
			$payload['proxy'] = $value;
			unset($payload['proxy_group']);
		}
		elseif ($target === 'proxy_group') {
			$payload['proxy_group'] = $value;
			unset($payload['proxy']);
		}
		elseif ($target === 'hostid' || $target === 'operacao') {
			$payload[$target] = $value;
		}
		elseif (strpos($target, 'tag:') === 0) {
			$tag = substr($target, 4);

			if (!in_array($value, $payload['tags'][$tag] ?? [], true)) {
				$payload['tags'][$tag][] = $value;
			}
		}
		elseif (strpos($target, 'macro:') === 0) {
			$payload['macros'][substr($target, 6)] = $value;
		}
		elseif (strpos($target, 'inventory.') === 0) {
			$payload['inventory'][substr($target, 10)] = $value;
		}
	}

	private static function cleanup(array $payload): array {
		foreach (['host', 'interface', 'tags', 'macros', 'inventory'] as $key) {
			if (!$payload[$key]) {
				unset($payload[$key]);
			}
		}

		if (!$payload['groups']['adicionar'] && !$payload['groups']['substituir']) {
			unset($payload['groups']);
		}

		if (!$payload['templates']['vincular'] && !$payload['templates']['desvincular']) {
			unset($payload['templates']);
		}

		return $payload;
	}
}
