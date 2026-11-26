<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseFatal;
use Modules\HostFlow\Lib\Topdesk\TopdeskClient;
use Modules\HostFlow\Lib\Topdesk\TopdeskSettings;
use Throwable;

class TopdeskSave extends BaseAction {

	protected function checkInput(): bool {
		$rules = [
			'ativo' => 'in 0,1',
			'url' => 'string',
			'usuario' => 'string',
			'senha' => 'string',
			'limpar_senha' => 'in 0,1',
			'cliente' => 'string',
			'solicitante_padrao' => 'string',
			'verificar_ssl' => 'in 0,1',
			'enviar_segredos' => 'in 0,1',
			'campos_extras' => 'string',
			'testar' => 'string'
		];

		foreach (array_keys(TopdeskSettings::LOOKUPS) as $key) {
			$rules[$key] = 'string';
		}

		$ret = $this->validateInput($rules);

		if (!$ret) {
			$this->setResponse(new CControllerResponseFatal());
		}

		return $ret;
	}

	protected function checkPermissions(): bool {
		return $this->isSuperAdmin();
	}

	protected function doAction(): void {
		$current = TopdeskSettings::load();
		$s = TopdeskSettings::defaults();

		foreach (array_keys($s) as $key) {
			if (is_bool($s[$key])) {
				$s[$key] = ($this->getInput($key, '0') === '1');
			}
			else {
				$s[$key] = trim($this->getInput($key, ''));
			}
		}

		$s['url'] = rtrim($s['url'], '/');

		// Senha vazia = manter a gravada.
		if ($this->getInput('limpar_senha', '0') === '1') {
			$s['senha'] = '';
		}
		elseif ($s['senha'] === '') {
			$s['senha'] = $current['senha'];
		}

		$errors = TopdeskSettings::validate($s);

		if (!$errors) {
			try {
				TopdeskSettings::save($s);
			}
			catch (Throwable $e) {
				$errors[] = $e->getMessage();
			}
		}

		if ($errors || !$this->hasInput('testar')) {
			if (!$errors) {
				$this->redirectTo('hostflow.topdesk.edit', $s['ativo']
					? 'Configuração salva. Novas solicitações abrirão chamado no TOPdesk.'
					: 'Configuração salva. A integração está desativada.'
				);

				return;
			}

			$this->setResponse(TopdeskEdit::response($s, $errors, null));

			return;
		}

		try {
			$test = ['ok' => true, 'mensagem' => 'Configuração salva. '.TopdeskClient::fromSettings($s)->test()];
		}
		catch (Throwable $e) {
			$test = ['ok' => false, 'mensagem' => 'Configuração salva, mas o teste falhou: '.$e->getMessage()];
		}

		$this->setResponse(TopdeskEdit::response($s, [], $test));
	}
}
