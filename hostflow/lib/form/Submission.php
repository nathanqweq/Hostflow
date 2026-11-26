<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

/**
 * Valida os valores enviados pelo usuário contra a definição do formulário
 * e monta o estado proposto do host.
 */
final class Submission {

	private const HOST_NAME_PATTERN = '/^[0-9a-zA-Z_. \-]+$/';
	private const DNS_PATTERN = '/^(?=.{1,255}$)[A-Za-z0-9](?:[A-Za-z0-9_-]{0,62}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9_-]{0,62}[A-Za-z0-9])?)*\.?$/';

	private array $form;
	private Options $options;

	/** @var array<string, string[]> erros por id de campo */
	private array $field_errors = [];

	/** @var string[] erros gerais */
	private array $errors = [];

	/** @var array<string, string|string[]|null> valores normalizados (null = campo oculto) */
	private array $values = [];

	public function __construct(array $form, Options $options) {
		$this->form = $form;
		$this->options = $options;
	}

	public function getValues(): array {
		return $this->values;
	}

	public function getFieldErrors(): array {
		return $this->field_errors;
	}

	public function getErrors(): array {
		return $this->errors;
	}

	public function hasErrors(): bool {
		return $this->field_errors || $this->errors;
	}

	/**
	 * Etapa 1: valida cada campo isoladamente.
	 */
	public function validateFields(array $raw): bool {
		$this->values = [];

		// Primeiro normaliza tudo, porque a visibilidade depende do valor de outros campos.
		$normalized = [];

		foreach ($this->form['campos'] as $field) {
			$normalized[$field['id']] = self::normalize($field, $raw[$field['id']] ?? null);
		}

		$visible = self::visibility($this->form['campos'], $normalized);

		foreach ($this->form['campos'] as $field) {
			$id = $field['id'];

			if (!$visible[$id]) {
				$this->values[$id] = null;
				continue;
			}

			$value = $normalized[$id];
			$this->values[$id] = $value;

			$empty = is_array($value) ? !$value : ($value === '' || ($field['tipo'] === 'checkbox' && $value === '0'));

			if ($empty) {
				if ($field['obrigatorio']) {
					$this->fieldError($id, 'Campo obrigatório.');
				}

				continue;
			}

			$this->validateValue($field, $value);
		}

		return !$this->hasErrors();
	}

	/**
	 * Etapa 2: monta o payload e faz as checagens que dependem do Zabbix.
	 */
	public function buildPayload(): array {
		return (new PayloadBuilder($this->form, $this->options))->build($this->values);
	}

	/**
	 * Checagens cruzadas com o estado do Zabbix. Rodam com a sessão de quem envia, então só
	 * enxergam o que esse usuário pode ler. A revalidação completa acontece depois do submit.
	 */
	public function validatePayload(array $payload, ?array $current_host): bool {
		$type = $this->form['tipo'];

		if ($type !== 'create') {
			if ($current_host === null) {
				$this->errors[] = 'Host não encontrado ou sem permissão de leitura.';

				return false;
			}
		}

		$host_name = $payload['host']['host'] ?? null;

		if ($host_name !== null) {
			if (!preg_match(self::HOST_NAME_PATTERN, $host_name)) {
				$this->errors[] = sprintf('Nome técnico "%s" inválido: use letras, números, espaço, ".", "_" e "-".',
					$host_name
				);
			}
			else {
				foreach (ZabbixLookup::hostsByTechnicalName($host_name) as $other) {
					if ($current_host === null || $other['hostid'] !== $current_host['hostid']) {
						$this->errors[] = sprintf('Já existe um host com o nome técnico "%s".', $host_name);
						break;
					}
				}
			}
		}

		$visible_name = $payload['host']['name'] ?? null;

		if ($visible_name !== null) {
			foreach (ZabbixLookup::hostsByVisibleName($visible_name) as $other) {
				if ($current_host === null || $other['hostid'] !== $current_host['hostid']) {
					$this->errors[] = sprintf('Já existe um host com o nome visível "%s".', $visible_name);
					break;
				}
			}
		}

		// IP repetido é permitido: vários hosts podem compartilhar o mesmo IP (ex.: hosts lógicos no mesmo
		// equipamento). Só os nomes técnico e visível precisam ser únicos, como no próprio Zabbix.

		$groups = $payload['groups']['adicionar'] ?? [];

		foreach ($payload['groups']['substituir'] ?? [] as $names) {
			$groups = array_merge($groups, $names);
		}

		$missing = ZabbixLookup::missingHostGroups(array_values(array_unique($groups)));

		if ($missing) {
			$this->errors[] = sprintf('Grupo(s) inexistente(s) ou sem permissão: %s. Peça a criação ao administrador.',
				implode(', ', $missing)
			);
		}

		if ($type === 'create' && !$groups) {
			$this->errors[] = 'Nenhum grupo de hosts foi definido.';
		}

		return !$this->hasErrors();
	}

	private function validateValue(array $field, $value): void {
		$id = $field['id'];
		$type = $field['tipo'];

		if (in_array($type, FormSchema::TEXT_TYPES, true)) {
			if ($type === 'ip' && filter_var($value, FILTER_VALIDATE_IP) === false) {
				$this->fieldError($id, 'Endereço IP inválido.');
			}

			if ($type === 'dns' && !preg_match(self::DNS_PATTERN, $value)) {
				$this->fieldError($id, 'Nome DNS inválido.');
			}

			if (mb_strlen($value) > ($type === 'textarea' ? 65535 : 2048)) {
				$this->fieldError($id, 'Texto longo demais.');
			}

			if (($field['regex'] ?? '') !== '' && !preg_match(FormSchema::wrapRegex($field['regex']), $value)) {
				$this->fieldError($id, 'Formato inválido.'
					.(($field['ajuda'] ?? '') !== '' ? ' '.$field['ajuda'] : '')
				);
			}

			return;
		}

		if ($type === 'zbx_host') {
			if (ZabbixLookup::host($value) === null) {
				$this->fieldError($id, 'Host não encontrado ou sem permissão de leitura.');
			}

			return;
		}

		$options = $this->options->forField($field);

		if ($options === null) {
			return;
		}

		$allowed = array_column($options, 'valor');

		foreach ((array) $value as $v) {
			if (!in_array($v, $allowed, true)) {
				$this->fieldError($id, sprintf('Valor "%s" não é permitido.', $v));
			}
		}
	}

	/**
	 * @return string|string[]
	 */
	public static function normalize(array $field, $raw) {
		if (Options::isMulti($field)) {
			$values = [];

			foreach (is_array($raw) ? $raw : (($raw === null || $raw === '') ? [] : [$raw]) as $v) {
				if (is_scalar($v) && trim((string) $v) !== '' && !in_array(trim((string) $v), $values, true)) {
					$values[] = trim((string) $v);
				}
			}

			return $values;
		}

		if ($field['tipo'] === 'checkbox') {
			return ($raw === '1' || $raw === 1 || $raw === true || $raw === 'on') ? '1' : '0';
		}

		if ($field['tipo'] === 'zbx_host' && is_array($raw)) {
			$raw = reset($raw);
		}

		if (!is_scalar($raw)) {
			return '';
		}

		$raw = (string) $raw;

		return ($field['tipo'] === 'textarea') ? trim(str_replace("\r\n", "\n", $raw)) : trim($raw);
	}

	/**
	 * Visibilidade de todos os campos. Um campo oculto conta como vazio para as condições que dependem dele
	 * (mesma regra do navegador, em hostflow.request.js).
	 *
	 * @return array<string, bool>
	 */
	public static function visibility(array $fields, array $normalized): array {
		$by_id = array_column($fields, null, 'id');
		$visible = [];

		$resolve = function (string $id, array $stack) use (&$resolve, &$visible, $by_id, $normalized): bool {
			if (array_key_exists($id, $visible)) {
				return $visible[$id];
			}

			if (!array_key_exists($id, $by_id) || in_array($id, $stack, true)) {
				return false;
			}

			$stack[] = $id;

			$result = self::conditionMet($by_id[$id]['quando'] ?? null,
				function (string $ref) use (&$resolve, $stack, $normalized): array {
					return $resolve($ref, $stack) ? self::asList($normalized[$ref] ?? null) : [];
				}
			);

			return $visible[$id] = $result;
		};

		foreach ($fields as $field) {
			$resolve($field['id'], []);
		}

		return $visible;
	}

	/**
	 * Condição de um item (campo ou valor fixo) contra valores já resolvidos (null = campo oculto).
	 */
	public static function isVisible(array $item, array $values): bool {
		return self::conditionMet($item['quando'] ?? null, function (string $ref) use ($values): array {
			return self::asList($values[$ref] ?? null);
		});
	}

	/**
	 * @param callable $value_of  fn(string $campo): string[]
	 */
	public static function conditionMet(?array $cond, callable $value_of): bool {
		if ($cond === null || empty($cond['regras'])) {
			return true;
		}

		$results = [];

		foreach ($cond['regras'] as $rule) {
			$hit = (bool) array_intersect($value_of($rule['campo']), $rule['valores']);
			$results[] = ($rule['operador'] === 'diferente') ? !$hit : $hit;
		}

		return (($cond['logica'] ?? 'e') === 'ou')
			? in_array(true, $results, true)
			: !in_array(false, $results, true);
	}

	private static function asList($value): array {
		if ($value === null) {
			return [];
		}

		return array_map('strval', is_array($value) ? array_values($value) : [$value]);
	}

	private function fieldError(string $id, string $message): void {
		$this->field_errors[$id][] = $message;
	}
}
