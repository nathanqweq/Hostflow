<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;
use Modules\HostFlow\Lib\Topdesk\TopdeskSettings;

class TopdeskEdit extends BaseAction {

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
		$this->setResponse(self::response(TopdeskSettings::load(), [], null));
	}

	/**
	 * A senha nunca vai para a view: só o indicador de que existe uma gravada.
	 */
	public static function response(array $settings, array $errors, ?array $test): CControllerResponseData {
		$has_password = ($settings['senha'] !== '');
		$settings['senha'] = '';

		$response = new CControllerResponseData([
			'settings' => $settings,
			'has_password' => $has_password,
			'errors' => $errors,
			'test' => $test,
			'writable' => TopdeskSettings::isWritable()
		]);
		$response->setTitle(_('Integração TOPdesk'));

		return $response;
	}
}
