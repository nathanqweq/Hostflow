<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;
use CControllerResponseFatal;

class FormEdit extends BaseAction {

	protected function init(): void {
		$this->disableCsrfValidation();
	}

	protected function checkInput(): bool {
		$ret = $this->validateInput([
			'formid' => 'string',
			'clone' => 'in 1'
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
		$original_id = '';

		if ($this->hasInput('formid')) {
			$definition = $this->repo()->form($this->getInput('formid'));

			if ($definition === null) {
				$this->setResponse(new CControllerResponseFatal());

				return;
			}

			if ($this->hasInput('clone')) {
				$definition['id'] .= '-copia';
				$definition['nome'] .= ' (cópia)';
				$definition['versao'] = 1;
			}
			else {
				$original_id = $definition['id'];
			}
		}
		else {
			$definition = self::newDefinition();
		}

		$response = new CControllerResponseData([
			'definition' => $definition,
			'definition_raw' => null,
			'original_id' => $original_id,
			'errors' => [],
			'builder' => $this->builderConfig()
		]);
		$response->setTitle(_('Editar formulário'));
		$this->setResponse($response);
	}

	public static function newDefinition(): array {
		return [
			'schema_version' => 1,
			'id' => '',
			'versao' => 1,
			'nome' => '',
			'descricao' => '',
			'tipo' => 'create',
			'ativo' => true,
			'equipe_responsavel' => '',
			'campos' => [
				[
					'id' => 'hostname',
					'rotulo' => 'Hostname',
					'tipo' => 'text',
					'obrigatorio' => true,
					'ajuda' => '',
					'valor_padrao' => '',
					'regex' => '',
					'quando' => null,
					'mapeamento' => [['alvo' => 'host.host', 'padrao' => ''], ['alvo' => 'host.name', 'padrao' => '']]
				]
			],
			'valores_fixos' => []
		];
	}
}
