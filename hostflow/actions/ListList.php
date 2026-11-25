<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;

class ListList extends BaseAction {

	protected function init(): void {
		$this->disableCsrfValidation();
	}

	protected function checkInput(): bool {
		return true;
	}

	protected function checkPermissions(): bool {
		return $this->isSuperAdmin();
	}

	protected function doAction(): void {
		$lists = $this->repo()->lists();
		$usage = [];

		foreach (array_keys($lists) as $id) {
			$usage[$id] = $this->repo()->formsUsingList($id);
		}

		$response = new CControllerResponseData([
			'lists' => $lists,
			'usage' => $usage,
			'writable' => $this->repo()->listsStore()->isWritable(),
			'data_dir' => dirname($this->repo()->listsStore()->getDir())
		]);
		$response->setTitle(_('Listas de valores'));
		$this->setResponse($response);
	}
}
