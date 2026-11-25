<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

use Modules\HostFlow\Lib\Config;
use Modules\HostFlow\Lib\Storage\JsonStore;

/**
 * Acesso a formulários (<data_dir>/forms) e listas compartilhadas (<data_dir>/lists).
 * Trocar o backend (ex.: banco) depois significa reimplementar só esta classe.
 */
final class Repository {

	private JsonStore $forms;
	private JsonStore $lists;

	public function __construct(?string $data_dir = null) {
		$data_dir = $data_dir ?? Config::dataDir();

		$this->forms = new JsonStore($data_dir.'/forms');
		$this->lists = new JsonStore($data_dir.'/lists');
	}

	public function formsStore(): JsonStore {
		return $this->forms;
	}

	public function listsStore(): JsonStore {
		return $this->lists;
	}

	/**
	 * @return array<string, array>
	 */
	public function forms(bool $only_active = false): array {
		$forms = $this->forms->all();

		if ($only_active) {
			$forms = array_filter($forms, static function (array $form): bool {
				return !empty($form['ativo']);
			});
		}

		uasort($forms, static function (array $a, array $b): int {
			return strcasecmp((string) ($a['nome'] ?? ''), (string) ($b['nome'] ?? ''));
		});

		return $forms;
	}

	public function form(string $id): ?array {
		return $this->forms->get($id);
	}

	public function saveForm(array $form): void {
		$this->forms->put($form['id'], $form);
	}

	public function deleteForm(string $id): void {
		$this->forms->delete($id);
	}

	/**
	 * @return array<string, array>
	 */
	public function lists(): array {
		return $this->lists->all();
	}

	public function list(string $id): ?array {
		return $this->lists->get($id);
	}

	public function saveList(array $list): void {
		$this->lists->put($list['id'], $list);
	}

	public function deleteList(string $id): void {
		$this->lists->delete($id);
	}

	/**
	 * Formulários que usam a lista (para impedir exclusão de lista em uso).
	 */
	public function formsUsingList(string $list_id): array {
		$names = [];

		foreach ($this->forms->all() as $form) {
			foreach ($form['campos'] ?? [] as $field) {
				if (($field['lista'] ?? '') === $list_id) {
					$names[] = $form['nome'] ?? $form['id'];
					break;
				}
			}
		}

		return $names;
	}
}
