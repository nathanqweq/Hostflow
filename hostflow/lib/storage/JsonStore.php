<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Storage;

use RuntimeException;

/**
 * Diretório de documentos JSON, um arquivo por id (<dir>/<id>.json).
 * A gravação é atômica: escreve num arquivo temporário e renomeia.
 */
class JsonStore {

	public const ID_PATTERN = '/^[a-z0-9][a-z0-9_-]{0,63}$/';

	private string $dir;

	public function __construct(string $dir) {
		$this->dir = rtrim($dir, '/');
	}

	public function getDir(): string {
		return $this->dir;
	}

	public static function isValidId(string $id): bool {
		return (bool) preg_match(self::ID_PATTERN, $id);
	}

	public function isWritable(): bool {
		if (is_dir($this->dir)) {
			return is_writable($this->dir);
		}

		$parent = dirname($this->dir);

		return is_dir($parent) && is_writable($parent);
	}

	/**
	 * @return string[]
	 */
	public function ids(): array {
		if (!is_dir($this->dir)) {
			return [];
		}

		$ids = [];

		foreach (glob($this->dir.'/*.json') ?: [] as $file) {
			$id = basename($file, '.json');

			if (self::isValidId($id)) {
				$ids[] = $id;
			}
		}

		sort($ids);

		return $ids;
	}

	public function exists(string $id): bool {
		return self::isValidId($id) && is_file($this->path($id));
	}

	public function get(string $id): ?array {
		if (!$this->exists($id)) {
			return null;
		}

		$raw = file_get_contents($this->path($id));
		$data = ($raw === false) ? null : json_decode($raw, true);

		return is_array($data) ? $data : null;
	}

	/**
	 * @return array<string, array>
	 */
	public function all(): array {
		$all = [];

		foreach ($this->ids() as $id) {
			$doc = $this->get($id);

			if ($doc !== null) {
				$all[$id] = $doc;
			}
		}

		return $all;
	}

	public function put(string $id, array $data): void {
		if (!self::isValidId($id)) {
			throw new RuntimeException(sprintf('ID inválido: "%s".', $id));
		}

		if (!is_dir($this->dir) && !@mkdir($this->dir, 0770, true) && !is_dir($this->dir)) {
			throw new RuntimeException(sprintf('Não foi possível criar o diretório "%s".', $this->dir));
		}

		$json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

		if ($json === false) {
			throw new RuntimeException('Falha ao serializar JSON.');
		}

		$tmp = $this->dir.'/.'.$id.'.'.bin2hex(random_bytes(4)).'.tmp';

		if (@file_put_contents($tmp, $json."\n", LOCK_EX) === false) {
			throw new RuntimeException(sprintf('Sem permissão de escrita em "%s".', $this->dir));
		}

		@chmod($tmp, 0660);

		if (!@rename($tmp, $this->path($id))) {
			@unlink($tmp);
			throw new RuntimeException(sprintf('Não foi possível gravar "%s".', $this->path($id)));
		}
	}

	public function delete(string $id): void {
		if ($this->exists($id) && !@unlink($this->path($id))) {
			throw new RuntimeException(sprintf('Não foi possível excluir "%s".', $this->path($id)));
		}
	}

	private function path(string $id): string {
		return $this->dir.'/'.$id.'.json';
	}
}
