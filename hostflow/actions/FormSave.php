<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;
use CControllerResponseFatal;
use Modules\HostFlow\Lib\Form\FormSchema;
use Throwable;

class FormSave extends BaseAction {

	protected function checkInput(): bool {
		$ret = $this->validateInput([
			'definition' => 'required|string',
			'original_id' => 'string'
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
		$raw = $this->getInput('definition');
		$original_id = $this->getInput('original_id', '');
		$definition = json_decode($raw, true);

		if (!is_array($definition)) {
			$this->showErrors(null, $raw, $original_id, ['JSON inválido: '.json_last_error_msg().'.']);

			return;
		}

		$schema = new FormSchema();
		$form = $schema->validate($definition, $this->repo()->lists());

		if ($form === null) {
			$this->showErrors($definition, null, $original_id, $schema->getErrors());

			return;
		}

		$existing = $this->repo()->form($form['id']);

		if ($existing !== null && $form['id'] !== $original_id) {
			$this->showErrors($definition, null, $original_id,
				[sprintf('Já existe um formulário com o ID "%s".', $form['id'])]
			);

			return;
		}

		if ($original_id !== '' && ($previous = $this->repo()->form($original_id)) !== null) {
			$form['versao'] = (int) ($previous['versao'] ?? 1) + 1;
		}

		try {
			$this->repo()->saveForm($form);

			if ($original_id !== '' && $original_id !== $form['id']) {
				$this->repo()->deleteForm($original_id);
			}
		}
		catch (Throwable $e) {
			$this->showErrors($definition, null, $original_id, [$e->getMessage()]);

			return;
		}

		$this->redirectTo('hostflow.form.list', sprintf('Formulário "%s" salvo (versão %d).', $form['nome'],
			$form['versao']
		));
	}

	private function showErrors(?array $definition, ?string $raw, string $original_id, array $errors): void {
		$response = new CControllerResponseData([
			'definition' => $definition ?? FormEdit::newDefinition(),
			'definition_raw' => $raw,
			'original_id' => $original_id,
			'errors' => $errors,
			'builder' => $this->builderConfig()
		]);
		$response->setTitle(_('Editar formulário'));
		$this->setResponse($response);
	}
}
