<?php declare(strict_types = 0);
/**
 * @var CView $this
 * @var array $data
 */

use Modules\HostFlow\Lib\Form\FormSchema;

$page = (new CHtmlPage())
	->setTitle(_('Formulários de solicitação'))
	->setControls(
		(new CTag('nav', true,
			(new CList())
				->addItem(new CRedirectButton(_('Novo formulário'),
					(new CUrl('zabbix.php'))->setArgument('action', 'hostflow.form.edit')
				))
				->addItem((new CRedirectButton(_('Listas de valores'),
					(new CUrl('zabbix.php'))->setArgument('action', 'hostflow.list.list')
				))->addClass(ZBX_STYLE_BTN_ALT))
		))->setAttribute('aria-label', _('Content controls'))
	);

if (!$data['writable']) {
	$page->addItem((new CDiv(sprintf(
		'O diretório de dados "%s" não existe ou não tem permissão de escrita para o servidor web. '.
		'Veja o passo de instalação do diretório de dados.', $data['data_dir']
	)))->addClass('hf-alert hf-alert-bad'));
}

$table = (new CTableInfo())->setHeader([
	_('Nome'), _('ID'), _('Tipo'), _('Campos'), _('Versão'), _('Equipe responsável'), _('Status'), _('Ações')
]);

foreach ($data['forms'] as $form) {
	$delete_form = (new CForm('post', (new CUrl('zabbix.php'))
		->setArgument('action', 'hostflow.form.delete')
		->getUrl()
	))
		->addClass('hf-inline-form')
		->addItem((new CVar(CSRF_TOKEN_NAME, CCsrfTokenHelper::get('hostflow.form.delete')))->removeId())
		->addItem((new CVar('formid', $form['id']))->removeId())
		->addItem((new CSubmit('delete', _('Excluir')))
			->addClass(ZBX_STYLE_BTN_LINK)
			->addClass('js-hf-confirm')
			->setAttribute('data-confirm', sprintf('Excluir o formulário "%s"?', $form['nome']))
		);

	$table->addRow([
		new CLink($form['nome'], (new CUrl('zabbix.php'))
			->setArgument('action', 'hostflow.form.edit')
			->setArgument('formid', $form['id'])
		),
		$form['id'],
		FormSchema::FORM_TYPES[$form['tipo']] ?? $form['tipo'],
		count($form['campos'] ?? []),
		(string) ($form['versao'] ?? 1),
		($form['equipe_responsavel'] ?? '') !== '' ? $form['equipe_responsavel'] : '—',
		!empty($form['ativo'])
			? (new CSpan(_('Ativo')))->addClass(ZBX_STYLE_GREEN)
			: (new CSpan(_('Inativo')))->addClass(ZBX_STYLE_RED),
		(new CDiv([
			new CLink(_('Testar'), (new CUrl('zabbix.php'))
				->setArgument('action', 'hostflow.request.new')
				->setArgument('formid', $form['id'])
			),
			new CLink(_('Duplicar'), (new CUrl('zabbix.php'))
				->setArgument('action', 'hostflow.form.edit')
				->setArgument('formid', $form['id'])
				->setArgument('clone', 1)
			),
			$delete_form
		]))->addClass('hf-row-actions')
	]);
}

$page->addItem($table)->show();
