<?php declare(strict_types = 0);

namespace Modules\HostFlow;

use APP;
use CMenu;
use CMenuItem;
use CWebUser;
use Zabbix\Core\CModule;

/**
 * O frontend só carrega este módulo para usuários cujo User role libera
 * "Access to modules > HostFlow". Sem acesso, nem o menu nem as actions existem.
 */
class Module extends CModule {

	public function init(): void {
		$items = [
			(new CMenuItem(_('Nova solicitação')))
				->setAction('hostflow.request.new')
				->setAliases(['hostflow.request.submit'])
		];

		if (CWebUser::getType() == USER_TYPE_SUPER_ADMIN) {
			$items[] = (new CMenuItem(_('Formulários')))
				->setAction('hostflow.form.list')
				->setAliases(['hostflow.form.edit', 'hostflow.form.save']);
			$items[] = (new CMenuItem(_('Listas de valores')))
				->setAction('hostflow.list.list')
				->setAliases(['hostflow.list.edit', 'hostflow.list.save']);
			$items[] = (new CMenuItem(_('Integração TOPdesk')))
				->setAction('hostflow.topdesk.edit')
				->setAliases(['hostflow.topdesk.save']);
		}

		APP::Component()->get('menu.main')->add(
			(new CMenuItem(_('Solicitações')))
				->setIcon(ZBX_ICON_TEXT)
				->setSubMenu(new CMenu($items))
		);
	}
}
