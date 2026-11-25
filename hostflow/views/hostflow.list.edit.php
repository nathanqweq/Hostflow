<?php declare(strict_types = 0);
/**
 * @var CView $this
 * @var array $data
 */

use Modules\HostFlow\Lib\Ui;

$page = (new CHtmlPage())->setTitle(($data['original_id'] === '') ? _('Nova lista de valores') : _('Editar lista de valores'));

if ($data['errors']) {
	$page->addItem(Ui::errorBox('Não foi possível salvar a lista', $data['errors']));
}

$form = (new CForm('post', (new CUrl('zabbix.php'))->setArgument('action', 'hostflow.list.save')->getUrl()))
	->setName('hf_list_form')
	->addItem((new CVar(CSRF_TOKEN_NAME, CCsrfTokenHelper::get('hostflow.list.save')))->removeId())
	->addItem((new CVar('original_id', $data['original_id']))->removeId());

$form->addItem((new CFormGrid())
	->addItem([
		(new CLabel(_('ID'), 'hf_list_id'))->setAsteriskMark(),
		new CFormField([
			(new CTextBox('id', $data['id'], false, 64))
				->setId('hf_list_id')
				->setWidth(ZBX_TEXTAREA_SMALL_WIDTH)
				->setAttribute('autofocus', 'autofocus'),
			(new CDiv('Usado nos formulários para referenciar a lista. Minúsculas, números, "-" e "_".'))
				->addClass(ZBX_STYLE_FORM_FIELDS_HINT)
		])
	])
	->addItem([
		(new CLabel(_('Nome'), 'hf_list_nome'))->setAsteriskMark(),
		new CFormField((new CTextBox('nome', $data['nome']))->setId('hf_list_nome')->setWidth(ZBX_TEXTAREA_STANDARD_WIDTH))
	])
	->addItem([
		(new CLabel(_('Itens'), 'hf_list_itens'))->setAsteriskMark(),
		new CFormField([
			(new CTextArea('itens_text', $data['itens_text']))
				->setId('hf_list_itens')
				->setRows(18)
				->addClass('hf-mono')
				->setWidth(ZBX_TEXTAREA_BIG_WIDTH),
			(new CDiv([
				'Um item por linha: ', (new CTag('code', true, 'VALOR | Rótulo | chave=valor; chave2=valor2')),
				new CTag('br'),
				'Exemplo: ', (new CTag('code', true, 'SITE_A | Site A | regiao=NORTE; cliente=CLIENTE_A')),
				new CTag('br'),
				'Rótulo e atributos são opcionais. Linhas iniciadas por # são ignoradas.'
			]))->addClass(ZBX_STYLE_FORM_FIELDS_HINT)
		])
	])
	->addItem(new CFormActions(new CSubmit('save', _('Salvar')), [
		new CRedirectButton(_('Cancelar'), (new CUrl('zabbix.php'))->setArgument('action', 'hostflow.list.list'))
	]))
);

$page->addItem($form)->show();
