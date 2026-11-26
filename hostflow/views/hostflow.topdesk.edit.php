<?php declare(strict_types = 0);
/**
 * @var CView $this
 * @var array $data
 */

use Modules\HostFlow\Lib\Topdesk\TopdeskSettings;
use Modules\HostFlow\Lib\Ui;

$s = $data['settings'];
$page = (new CHtmlPage())->setTitle(_('Integração TOPdesk'));

$page->addItem((new CDiv(
	'Com a integração ativa, cada solicitação válida abre um chamado no TOPdesk com o título '.
	'"[CLIENTE] - Nova solicitação - <formulário>". O solicitante é o e-mail do usuário do Zabbix que preencheu. '.
	'O JSON da solicitação vai como ação oculta para o solicitante e, em formulários de criação, o arquivo de '.
	'importação do host no Zabbix é anexado (também oculto).'
))->addClass('hf-intro'));

if (!$data['writable']) {
	$page->addItem(Ui::notice('O diretório de dados não tem permissão de escrita: a configuração não poderá ser salva.',
		'bad'
	));
}

if ($data['errors']) {
	$page->addItem(Ui::errorBox('Não foi possível salvar', $data['errors']));
}

if ($data['test'] !== null) {
	$page->addItem(Ui::notice($data['test']['mensagem'], $data['test']['ok'] ? 'good' : 'bad'));
}

$hint = static function (string $text): CDiv {
	return (new CDiv($text))->addClass(ZBX_STYLE_FORM_FIELDS_HINT);
};

$text = static function (string $name, string $value, string $hint_text = '') use ($hint): CFormField {
	$items = [(new CTextBox($name, $value))->setId('hf_td_'.$name)->setWidth(ZBX_TEXTAREA_STANDARD_WIDTH)];

	if ($hint_text !== '') {
		$items[] = $hint($hint_text);
	}

	return new CFormField($items);
};

$check = static function (string $name, bool $checked): CCheckBox {
	return (new CCheckBox($name, '1'))->setId('hf_td_'.$name)->setChecked($checked)->setUncheckedValue('0');
};

$grid = (new CFormGrid())
	->addItem([new CLabel(_('Ativar integração'), 'hf_td_ativo'), new CFormField($check('ativo', (bool) $s['ativo']))])

	->addItem(new CFormField((new CTag('h3', true, _('Conexão')))->addClass('hf-section-title')))
	->addItem([
		(new CLabel(_('Endereço'), 'hf_td_url'))->setAsteriskMark(),
		$text('url', $s['url'], 'Ex.: https://empresa.topdesk.net (sem /tas/api).')
	])
	->addItem([
		(new CLabel(_('Usuário da API'), 'hf_td_usuario'))->setAsteriskMark(),
		$text('usuario', $s['usuario'], 'Login do operador usado pela integração.')
	])
	->addItem([
		(new CLabel(_('Application password'), 'hf_td_senha'))->setAsteriskMark(),
		new CFormField([
			(new CPassBox('senha', '', 255))->setId('hf_td_senha')->setWidth(ZBX_TEXTAREA_STANDARD_WIDTH)
				->setAttribute('autocomplete', 'new-password')
				->setAttribute('placeholder', $data['has_password'] ? '•••••• (gravada, deixe vazio para manter)' : ''),
			$data['has_password'] ? new CLabel([$check('limpar_senha', false), ' Apagar a senha gravada'],
				'hf_td_limpar_senha'
			) : null,
			$hint('Gerada no TOPdesk em Configurações do usuário › Application passwords. Não é a senha de login.')
		])
	])
	->addItem([new CLabel(_('Verificar certificado SSL'), 'hf_td_verificar_ssl'),
		new CFormField($check('verificar_ssl', (bool) $s['verificar_ssl']))
	])

	->addItem(new CFormField((new CTag('h3', true, _('Chamado')))->addClass('hf-section-title')))
	->addItem([
		(new CLabel(_('Cliente'), 'hf_td_cliente'))->setAsteriskMark(),
		$text('cliente', $s['cliente'], 'Vai no título: [CLIENTE] - Nova solicitação - Nome do formulário. '.
			'O TOPdesk limita o título a 80 caracteres; o excedente é cortado.'
		)
	])
	->addItem([
		new CLabel(_('Solicitante padrão (e-mail)'), 'hf_td_solicitante_padrao'),
		$text('solicitante_padrao', $s['solicitante_padrao'],
			'Usado só quando o usuário do Zabbix não tem e-mail nas mídias e o username não é um e-mail.'
		)
	]);

foreach (TopdeskSettings::LOOKUPS as $key => [$label, , $extra_hint]) {
	$grid->addItem([
		new CLabel($label, 'hf_td_'.$key),
		$text($key, $s[$key], trim('ID (UUID) ou nome exato no TOPdesk. Vazio = não enviar. '.$extra_hint))
	]);
}

$grid
	->addItem([
		new CLabel(_('Campos extras (JSON)'), 'hf_td_campos_extras'),
		new CFormField([
			(new CTextArea('campos_extras', $s['campos_extras']))
				->setId('hf_td_campos_extras')
				->setRows(4)
				->addClass('hf-mono')
				->setWidth(ZBX_TEXTAREA_STANDARD_WIDTH),
			$hint('Mesclado no corpo do POST /tas/api/incidents. Ex.: {"entryType": {"name": "Zabbix"}}')
		])
	])
	->addItem([
		new CLabel(_('Enviar segredos SNMP'), 'hf_td_enviar_segredos'),
		new CFormField([
			$check('enviar_segredos', (bool) $s['enviar_segredos']),
			$hint('Desmarcado: community e passphrases digitadas vão como ****** no JSON e no arquivo do Zabbix '.
				'(macros {$...} são mantidas).'
			)
		])
	])
	->addItem(new CFormActions(new CSubmit('save', _('Salvar')), [
		(new CSubmit('testar', _('Salvar e testar conexão')))->addClass(ZBX_STYLE_BTN_ALT)
	]));

$form = (new CForm('post', (new CUrl('zabbix.php'))->setArgument('action', 'hostflow.topdesk.save')->getUrl()))
	->setName('hf_topdesk_form')
	->setAttribute('autocomplete', 'off')
	->addItem((new CVar(CSRF_TOKEN_NAME, CCsrfTokenHelper::get('hostflow.topdesk.save')))->removeId())
	->addItem($grid);

$page->addItem($form)->show();
