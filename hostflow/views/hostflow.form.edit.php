<?php declare(strict_types = 0);
/**
 * Construtor visual de formulários. A interface é montada por assets/js/hostflow.builder.js
 * a partir de data-definition. Ao salvar, o JS serializa tudo no campo oculto "definition",
 * que o servidor valida com FormSchema (a mesma validação da edição direta do JSON).
 *
 * @var CView $this
 * @var array $data
 */

use Modules\HostFlow\Lib\Ui;

$page = (new CHtmlPage())->setTitle(($data['original_id'] === '') ? _('Novo formulário') : _('Editar formulário'));

if ($data['errors']) {
	$page->addItem(Ui::errorBox('Não foi possível salvar o formulário', $data['errors']));
}

$form = (new CForm('post', (new CUrl('zabbix.php'))->setArgument('action', 'hostflow.form.save')->getUrl()))
	->setId('hf-builder-form')
	->setName('hf_builder_form')
	->addItem((new CVar(CSRF_TOKEN_NAME, CCsrfTokenHelper::get('hostflow.form.save')))->removeId())
	->addItem((new CVar('original_id', $data['original_id']))->removeId())
	->addItem((new CVar('definition', ''))->setId('hf-definition'));

$form->addItem(
	(new CDiv((new CTag('noscript', true, 'O construtor de formulários precisa de JavaScript.'))))
		->setId('hf-builder')
		->setAttribute('data-config', $data['builder'])
		->setAttribute('data-definition', $data['definition'])
		->setAttribute('data-raw', $data['definition_raw'] ?? '')
);

$form->addItem(
	(new CDiv([
		(new CSubmit('save', _('Salvar formulário')))->setId('hf-save'),
		new CRedirectButton(_('Cancelar'), (new CUrl('zabbix.php'))->setArgument('action', 'hostflow.form.list'))
	]))->addClass('hf-builder-actions')
);

$page->addItem($form)->show();
