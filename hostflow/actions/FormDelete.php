<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseFatal;
use Throwable;

class FormDelete extends BaseAction {

	protected function checkInput(): bool {
		$ret = $this->validateInput(['formid' => 'required|string']);

		if (!$ret) {
			$this->setResponse(new CControllerResponseFatal());
		}

		return $ret;
	}

	protected function checkPermissions(): bool {
		return $this->isSuperAdmin();
	}

	protected function doAction(): void {
		$id = $this->getInput('formid');

		try {
			$this->repo()->deleteForm($id);
			$this->redirectTo('hostflow.form.list', sprintf('Formulário "%s" excluído.', $id));
		}
		catch (Throwable $e) {
			$this->redirectTo('hostflow.form.list', null, $e->getMessage());
		}
	}
}
