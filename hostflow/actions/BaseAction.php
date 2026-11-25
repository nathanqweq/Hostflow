<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CController;
use CControllerResponseRedirect;
use CMessageHelper;
use CUrl;
use Modules\HostFlow\Lib\Form\FormSchema;
use Modules\HostFlow\Lib\Form\Repository;

abstract class BaseAction extends CController {

	private ?Repository $repository = null;

	protected function repo(): Repository {
		if ($this->repository === null) {
			$this->repository = new Repository();
		}

		return $this->repository;
	}

	protected function isSuperAdmin(): bool {
		return $this->getUserType() == USER_TYPE_SUPER_ADMIN;
	}

	protected function redirectTo(string $action, ?string $success = null, ?string $error = null): void {
		if ($success !== null) {
			CMessageHelper::setSuccessTitle($success);
		}

		if ($error !== null) {
			CMessageHelper::setErrorTitle($error);
		}

		$this->setResponse(new CControllerResponseRedirect((new CUrl('zabbix.php'))->setArgument('action', $action)));
	}

	/**
	 * Dados de apoio para o construtor de formulários (renderizado em JS).
	 */
	protected function builderConfig(): array {
		$lists = [];

		foreach ($this->repo()->lists() as $id => $list) {
			$lists[] = [
				'id' => $id,
				'nome' => $list['nome'] ?? $id,
				// Para o editor de condições oferecer os valores da lista como caixas de seleção.
				'itens' => array_map(static function (array $item): array {
					return [(string) $item['valor'], (string) ($item['rotulo'] ?? $item['valor'])];
				}, $list['itens'] ?? [])
			];
		}

		return [
			'form_types' => FormSchema::FORM_TYPES,
			'field_types' => FormSchema::FIELD_TYPES,
			'option_types' => FormSchema::OPTION_TYPES,
			'text_types' => FormSchema::TEXT_TYPES,
			'allowed_types' => FormSchema::ALLOWED_TYPES,
			'multi_capable' => FormSchema::MULTI_CAPABLE,
			'targets' => FormSchema::TARGETS,
			'target_prefixes' => FormSchema::TARGET_PREFIXES,
			'group_modes' => FormSchema::GROUP_MODES,
			'template_modes' => FormSchema::TEMPLATE_MODES,
			'inventory_fields' => FormSchema::inventoryFields() ?? [],
			'lists' => $lists
		];
	}
}
