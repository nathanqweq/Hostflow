<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseFatal;
use Throwable;

class ListDelete extends BaseAction {

	protected function checkInput(): bool {
		$ret = $this->validateInput(['listid' => 'required|string']);

		if (!$ret) {
			$this->setResponse(new CControllerResponseFatal());
		}

		return $ret;
	}

	protected function checkPermissions(): bool {
		return $this->isSuperAdmin();
	}

	protected function doAction(): void {
		$id = $this->getInput('listid');
		$used_by = $this->repo()->formsUsingList($id);

		if ($used_by) {
			$this->redirectTo('hostflow.list.list', null,
				sprintf('A lista "%s" é usada por: %s. Remova-a desses formulários antes.', $id, implode(', ', $used_by))
			);

			return;
		}

		try {
			$this->repo()->deleteList($id);
			$this->redirectTo('hostflow.list.list', sprintf('Lista "%s" excluída.', $id));
		}
		catch (Throwable $e) {
			$this->redirectTo('hostflow.list.list', null, $e->getMessage());
		}
	}
}
