<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;
use CControllerResponseFatal;
use Modules\HostFlow\Lib\Form\HostState;
use Modules\HostFlow\Lib\Form\Options;
use Modules\HostFlow\Lib\Form\ZabbixLookup;

/**
 * Sem formid: lista os formulários ativos. Com formid: renderiza o formulário.
 * Em update/move/delete, escolher o host recarrega a página com &hostid=..., e os campos
 * vêm preenchidos com os valores atuais do host.
 */
class RequestNew extends BaseAction {

	protected function init(): void {
		$this->disableCsrfValidation();
	}

	protected function checkInput(): bool {
		$ret = $this->validateInput([
			'formid' => 'string',
			'hostid' => 'id'
		]);

		if (!$ret) {
			$this->setResponse(new CControllerResponseFatal());
		}

		return $ret;
	}

	protected function checkPermissions(): bool {
		// Quem chegou aqui já tem acesso ao módulo pelo User role (o frontend não carrega o módulo sem isso).
		return true;
	}

	protected function doAction(): void {
		if (!$this->hasInput('formid')) {
			$response = new CControllerResponseData([
				'mode' => 'picker',
				'forms' => $this->repo()->forms(true),
				'is_super_admin' => $this->isSuperAdmin()
			]);
			$response->setTitle(_('Nova solicitação'));
			$this->setResponse($response);

			return;
		}

		$form = $this->repo()->form($this->getInput('formid'));

		// Formulário inativo: só o Super admin abre (para testar antes de publicar).
		if ($form === null || (empty($form['ativo']) && !$this->isSuperAdmin())) {
			$this->setResponse(new CControllerResponseFatal());

			return;
		}

		$options = new Options($this->repo()->lists());
		$values = [];
		$notice = null;

		foreach ($form['campos'] as $field) {
			if (($field['valor_padrao'] ?? '') !== '') {
				$values[$field['id']] = Options::isMulti($field) ? [$field['valor_padrao']] : $field['valor_padrao'];
			}
		}

		if ($this->hasInput('hostid') && $form['tipo'] !== 'create') {
			$state = HostState::read($this->getInput('hostid'));

			if ($state !== null) {
				$values = array_replace($values, HostState::prefill($form, $state, $options));
				$values[self::hostFieldId($form)] = $state['hostid'];
				$notice = sprintf('Valores atuais de "%s" carregados. Altere apenas o necessário.',
					$state['host']['name']
				);
			}
			else {
				$notice = 'Host não encontrado ou sem permissão de leitura.';
			}
		}

		$response = new CControllerResponseData(self::formViewData($form, $options, $values, [], [], '', $notice));
		$response->setTitle($form['nome']);
		$this->setResponse($response);
	}

	public static function hostFieldId(array $form): ?string {
		foreach ($form['campos'] as $field) {
			if ($field['tipo'] === 'zbx_host' && in_array('hostid', array_column($field['mapeamento'], 'alvo'), true)) {
				return $field['id'];
			}
		}

		return null;
	}

	/**
	 * Dados da view no modo "form" (também usado quando o envio volta com erros).
	 */
	public static function formViewData(array $form, Options $options, array $values, array $field_errors,
			array $errors, string $justificativa, ?string $notice): array {
		$field_options = [];
		$host_data = [];

		foreach ($form['campos'] as $field) {
			$field_options[$field['id']] = $options->forField($field);

			if ($field['tipo'] === 'zbx_host' && !empty($values[$field['id']])) {
				$host = ZabbixLookup::host((string) $values[$field['id']]);

				if ($host !== null) {
					$host_data[$field['id']] = [['id' => $host['hostid'], 'name' => $host['name']]];
				}
			}
		}

		return [
			'mode' => 'form',
			'form' => $form,
			'field_options' => $field_options,
			'host_data' => $host_data,
			'host_field' => self::hostFieldId($form),
			'values' => $values,
			'field_errors' => $field_errors,
			'errors' => $errors,
			'justificativa' => $justificativa,
			'notice' => $notice
		];
	}
}
