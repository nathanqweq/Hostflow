<?php declare(strict_types = 0);
/**
 * @var CView $this
 * @var array $data
 */

$page = (new CHtmlPage())
	->setTitle(_('Listas de valores'))
	->setControls(
		(new CTag('nav', true,
			(new CList())
				->addItem(new CRedirectButton(_('Nova lista'),
					(new CUrl('zabbix.php'))->setArgument('action', 'hostflow.list.edit')
				))
				->addItem((new CRedirectButton(_('Formulários'),
					(new CUrl('zabbix.php'))->setArgument('action', 'hostflow.form.list')
				))->addClass(ZBX_STYLE_BTN_ALT))
		))->setAttribute('aria-label', _('Content controls'))
	);

$page->addItem((new CDiv(
	'Listas são a fonte única de valores controlados (sites, clientes, categorias...). Um campo do tipo lista '.
	'aceita apenas esses valores, e os atributos de cada item podem montar grupos e tags, ex.: {site.regiao}.'
))->addClass('hf-intro'));

if (!$data['writable']) {
	$page->addItem((new CDiv(sprintf('O diretório de dados "%s" não existe ou não tem permissão de escrita.',
		$data['data_dir']
	)))->addClass('hf-alert hf-alert-bad'));
}

$table = (new CTableInfo())->setHeader([_('Nome'), _('ID'), _('Itens'), _('Atributos'), _('Usada por'), _('Ações')]);

foreach ($data['lists'] as $id => $list) {
	$attrs = [];

	foreach ($list['itens'] ?? [] as $item) {
		$attrs = array_merge($attrs, array_keys((array) ($item['attrs'] ?? [])));
	}

	$delete_form = (new CForm('post', (new CUrl('zabbix.php'))
		->setArgument('action', 'hostflow.list.delete')
		->getUrl()
	))
		->addClass('hf-inline-form')
		->addItem((new CVar(CSRF_TOKEN_NAME, CCsrfTokenHelper::get('hostflow.list.delete')))->removeId())
		->addItem((new CVar('listid', $id))->removeId())
		->addItem((new CSubmit('delete', _('Excluir')))
			->addClass(ZBX_STYLE_BTN_LINK)
			->addClass('js-hf-confirm')
			->setAttribute('data-confirm', sprintf('Excluir a lista "%s"?', $list['nome'] ?? $id))
		);

	$table->addRow([
		new CLink($list['nome'] ?? $id, (new CUrl('zabbix.php'))
			->setArgument('action', 'hostflow.list.edit')
			->setArgument('listid', $id)
		),
		$id,
		count($list['itens'] ?? []),
		$attrs ? implode(', ', array_unique($attrs)) : '—',
		$data['usage'][$id] ? implode(', ', $data['usage'][$id]) : '—',
		$delete_form
	]);
}

$page->addItem($table)->show();
