<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;
use CControllerResponseFatal;
use Modules\HostFlow\Lib\Form\ListSchema;

class ListEdit extends BaseAction {

	protected function init(): void {
		$this->disableCsrfValidation();
	}

	protected function checkInput(): bool {
		$ret = $this->validateInput(['listid' => 'string']);

		if (!$ret) {
			$this->setResponse(new CControllerResponseFatal());
		}

		return $ret;
	}

	protected function checkPermissions(): bool {
		return $this->isSuperAdmin();
	}

	protected function doAction(): void {
		$data = ['original_id' => '', 'id' => '', 'nome' => '', 'itens_text' => '', 'errors' => []];

		if ($this->hasInput('listid')) {
			$list = $this->repo()->list($this->getInput('listid'));

			if ($list === null) {
				$this->setResponse(new CControllerResponseFatal());

				return;
			}

			$data['original_id'] = $list['id'];
			$data['id'] = $list['id'];
			$data['nome'] = $list['nome'] ?? '';
			$data['itens_text'] = ListSchema::toText($list['itens'] ?? []);
		}

		$response = new CControllerResponseData($data);
		$response->setTitle(_('Editar lista de valores'));
		$this->setResponse($response);
	}
}
