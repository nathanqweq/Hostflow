<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;
use CControllerResponseFatal;
use CWebUser;
use Modules\HostFlow\Lib\Config;
use Modules\HostFlow\Lib\Form\HostState;
use Modules\HostFlow\Lib\Form\Options;
use Modules\HostFlow\Lib\Form\Submission;
use Modules\HostFlow\Lib\Submit\NullSubmitHandler;
use Modules\HostFlow\Lib\Submit\SubmitHandler;
use Throwable;

class RequestSubmit extends BaseAction {

	protected function checkInput(): bool {
		$ret = $this->validateInput([
			'formid' => 'required|string',
			'campos' => 'array',
			'justificativa' => 'string'
		]);

		if (!$ret) {
			$this->setResponse(new CControllerResponseFatal());
		}

		return $ret;
	}

	protected function checkPermissions(): bool {
		return true;
	}

	protected function doAction(): void {
		$form = $this->repo()->form($this->getInput('formid'));

		if ($form === null || (empty($form['ativo']) && !$this->isSuperAdmin())) {
			$this->setResponse(new CControllerResponseFatal());

			return;
		}

		$options = new Options($this->repo()->lists());
		$submission = new Submission($form, $options);
		$raw = $this->getInput('campos', []);
		$justificativa = trim($this->getInput('justificativa', ''));

		$submission->validateFields($raw);

		$errors = [];

		if ($justificativa === '') {
			$errors[] = 'Informe a justificativa.';
		}
		elseif (mb_strlen($justificativa) > 4000) {
			$errors[] = 'A justificativa deve ter no máximo 4000 caracteres.';
		}

		$payload = null;
		$current = null;

		if (!$submission->hasErrors()) {
			$payload = $submission->buildPayload();

			if ($form['tipo'] !== 'create') {
				$current = HostState::read((string) ($payload['hostid'] ?? ''));
			}

			$submission->validatePayload($payload, $current);
		}

		if ($submission->hasErrors() || $errors) {
			$values = $submission->getValues();

			// Mantém o que o usuário digitou, inclusive campos ocultos.
			foreach ($form['campos'] as $field) {
				if ($values[$field['id']] === null && array_key_exists($field['id'], $raw)) {
					$values[$field['id']] = Submission::normalize($field, $raw[$field['id']]);
				}
			}

			$response = new CControllerResponseData(RequestNew::formViewData($form, $options, $values,
				$submission->getFieldErrors(), array_merge($submission->getErrors(), $errors), $justificativa, null
			));
			$response->setTitle($form['nome']);
			$this->setResponse($response);

			return;
		}

		$before = $current ?? HostState::emptyState();
		$after = HostState::apply($before, $payload);

		$data = [
			'formulario' => $form,
			'valores' => $submission->getValues(),
			'resumo' => self::summary($form, $submission->getValues(), $options),
			'payload' => $payload,
			'host_atual' => $current,
			'diff' => HostState::diff($before, $after),
			'justificativa' => $justificativa,
			'solicitante' => [
				'userid' => CWebUser::$data['userid'] ?? null,
				'username' => CWebUser::$data['username'] ?? null,
				'name' => CWebUser::$data['name'] ?? '',
				'surname' => CWebUser::$data['surname'] ?? ''
			],
			'enviado_em' => time()
		];

		try {
			$result = self::handler()->handle($data);
		}
		catch (Throwable $e) {
			$result = ['ok' => false, 'mensagem' => 'Falha no envio: '.$e->getMessage(), 'referencia' => null];
		}

		$response = new CControllerResponseData([
			'mode' => 'done',
			'form' => $form,
			'submission' => $data,
			'result' => $result + ['ok' => false, 'mensagem' => '', 'referencia' => null]
		]);
		$response->setTitle($form['nome']);
		$this->setResponse($response);
	}

	private static function handler(): SubmitHandler {
		$class = Config::get('submit_handler');

		if (is_string($class) && $class !== '' && class_exists($class)
				&& is_subclass_of($class, SubmitHandler::class)) {
			return new $class();
		}

		return new NullSubmitHandler();
	}

	/**
	 * Resumo legível: rótulo do campo => rótulo do valor escolhido.
	 */
	private static function summary(array $form, array $values, Options $options): array {
		$rows = [];

		foreach ($form['campos'] as $field) {
			$value = $values[$field['id']] ?? null;

			if ($value === null || $value === '' || $value === []) {
				continue;
			}

			if ($field['tipo'] === 'checkbox') {
				$text = ($value === '1') ? 'Sim' : 'Não';
			}
			elseif ($field['tipo'] === 'zbx_host') {
				$state = HostState::read((string) $value);
				$text = ($state !== null) ? $state['host']['name'].' ('.$state['host']['host'].')' : (string) $value;
			}
			else {
				$labels = [];
				$field_options = $options->forField($field);

				foreach ((array) $value as $v) {
					$label = $v;

					foreach ($field_options ?? [] as $option) {
						if ($option['valor'] === $v) {
							$label = $option['rotulo'];
							break;
						}
					}

					$labels[] = $label;
				}

				$text = implode(', ', $labels);
			}

			$rows[] = ['campo' => $field['id'], 'rotulo' => $field['rotulo'], 'valor' => $text];
		}

		return $rows;
	}
}
