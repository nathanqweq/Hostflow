<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

use Modules\HostFlow\Lib\Storage\JsonStore;

/**
 * Listas compartilhadas de valores controlados (sites, clientes, categorias...).
 *
 * Formato em disco:
 * {"id": "sites", "nome": "Sites", "itens": [{"valor": "SITE_A", "rotulo": "Site A", "attrs": {"regiao": "NORTE"}}]}
 *
 * Formato de edição (uma linha por item):  VALOR | Rótulo | chave=valor; chave2=valor2
 */
final class ListSchema {

	public const ATTR_PATTERN = '/^[a-zA-Z0-9_]{1,64}$/';

	private array $errors = [];

	public function validate(array $raw): ?array {
		$this->errors = [];

		$list = [
			'id' => trim((string) ($raw['id'] ?? '')),
			'nome' => trim((string) ($raw['nome'] ?? '')),
			'itens' => []
		];

		if (!JsonStore::isValidId($list['id'])) {
			$this->errors[] = 'ID: use de 1 a 64 caracteres: letras minúsculas, números, "-" e "_".';
		}

		if ($list['nome'] === '') {
			$this->errors[] = 'Nome: obrigatório.';
		}

		$seen = [];

		foreach (is_array($raw['itens'] ?? null) ? $raw['itens'] : [] as $i => $item) {
			$value = trim((string) ($item['valor'] ?? ''));

			if ($value === '') {
				continue;
			}

			if (array_key_exists($value, $seen)) {
				$this->errors[] = sprintf('Item %d: valor "%s" repetido.', $i + 1, $value);
				continue;
			}

			$seen[$value] = true;
			$attrs = [];

			foreach (is_array($item['attrs'] ?? null) ? $item['attrs'] : [] as $key => $attr_value) {
				if (!preg_match(self::ATTR_PATTERN, (string) $key)) {
					$this->errors[] = sprintf('Item "%s": atributo "%s" inválido (use a-z, 0-9 e "_").', $value, $key);
					continue;
				}

				$attrs[(string) $key] = trim((string) $attr_value);
			}

			$label = trim((string) ($item['rotulo'] ?? ''));

			$list['itens'][] = [
				'valor' => $value,
				'rotulo' => ($label !== '') ? $label : $value,
				'attrs' => (object) $attrs
			];
		}

		if (!$list['itens']) {
			$this->errors[] = 'Itens: a lista precisa de pelo menos um item.';
		}

		return $this->errors ? null : $list;
	}

	public function getErrors(): array {
		return $this->errors;
	}

	/**
	 * Converte o texto de edição em itens.
	 */
	public static function parseText(string $text): array {
		$items = [];

		foreach (preg_split('/\r\n|\r|\n/', $text) as $line) {
			if (trim($line) === '' || strpos(ltrim($line), '#') === 0) {
				continue;
			}

			$parts = array_map('trim', explode('|', $line, 3));
			$attrs = [];

			if (isset($parts[2]) && $parts[2] !== '') {
				foreach (explode(';', $parts[2]) as $pair) {
					if (trim($pair) === '') {
						continue;
					}

					[$key, $value] = array_pad(array_map('trim', explode('=', $pair, 2)), 2, '');
					$attrs[$key] = $value;
				}
			}

			$items[] = ['valor' => $parts[0], 'rotulo' => $parts[1] ?? '', 'attrs' => $attrs];
		}

		return $items;
	}

	public static function toText(array $items): string {
		$lines = [];

		foreach ($items as $item) {
			$line = $item['valor'];
			$attrs = (array) ($item['attrs'] ?? []);
			$label = (string) ($item['rotulo'] ?? '');

			if (($label !== '' && $label !== $item['valor']) || $attrs) {
				$line .= ' | '.$label;
			}

			if ($attrs) {
				$pairs = [];

				foreach ($attrs as $key => $value) {
					$pairs[] = $key.'='.$value;
				}

				$line .= ' | '.implode('; ', $pairs);
			}

			$lines[] = $line;
		}

		return implode("\n", $lines);
	}
}
