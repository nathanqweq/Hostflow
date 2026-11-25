<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;

class FormList extends BaseAction {

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
		$store = $this->repo()->formsStore();

		$response = new CControllerResponseData([
			'forms' => $this->repo()->forms(),
			'data_dir' => dirname($store->getDir()),
			'writable' => $store->isWritable()
		]);
		$response->setTitle(_('Formulários de solicitação'));
		$this->setResponse($response);
	}
}
