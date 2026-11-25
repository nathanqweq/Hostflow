<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;
use CControllerResponseFatal;
use Modules\HostFlow\Lib\Form\ListSchema;
use Throwable;

class ListSave extends BaseAction {

	protected function checkInput(): bool {
		$ret = $this->validateInput([
			'original_id' => 'string',
			'id' => 'required|string',
			'nome' => 'required|string',
			'itens_text' => 'required|string'
		]);

		if (!$ret) {
			$this->setResponse(new CControllerResponseFatal());
		}

		return $ret;
	}

	protected function checkPermissions(): bool {
		return $this->isSuperAdmin();
	}

	protected function doAction(): void {
		$original_id = $this->getInput('original_id', '');
		$schema = new ListSchema();

		$list = $schema->validate([
			'id' => $this->getInput('id'),
			'nome' => $this->getInput('nome'),
			'itens' => ListSchema::parseText($this->getInput('itens_text'))
		]);

		$errors = $schema->getErrors();

		if ($list !== null) {
			if ($list['id'] !== $original_id && $this->repo()->list($list['id']) !== null) {
				$errors[] = sprintf('Já existe uma lista com o ID "%s".', $list['id']);
			}
			elseif ($original_id !== '' && $list['id'] !== $original_id
					&& ($used_by = $this->repo()->formsUsingList($original_id))) {
				$errors[] = sprintf('O ID não pode mudar: a lista é usada por %s.', implode(', ', $used_by));
			}
		}

		if (!$errors) {
			try {
				$this->repo()->saveList($list);

				if ($original_id !== '' && $original_id !== $list['id']) {
					$this->repo()->deleteList($original_id);
				}

				$this->redirectTo('hostflow.list.list', sprintf('Lista "%s" salva com %d itens.', $list['nome'],
					count($list['itens'])
				));

				return;
			}
			catch (Throwable $e) {
				$errors[] = $e->getMessage();
			}
		}

		$response = new CControllerResponseData([
			'original_id' => $original_id,
			'id' => $this->getInput('id'),
			'nome' => $this->getInput('nome'),
			'itens_text' => $this->getInput('itens_text'),
			'errors' => $errors
		]);
		$response->setTitle(_('Editar lista de valores'));
		$this->setResponse($response);
	}
}
