<?php declare(strict_types = 0);
/**
 * Modos:
 *  - picker: lista de formulários ativos;
 *  - form:   formulário renderizado a partir da definição (também volta aqui com erros);
 *  - done:   confirmação após envio válido.
 *
 * @var CView $this
 * @var array $data
 */

use Modules\HostFlow\Lib\Form\FormSchema;
use Modules\HostFlow\Lib\Form\Options;
use Modules\HostFlow\Lib\Ui;

$new_url = (new CUrl('zabbix.php'))->setArgument('action', 'hostflow.request.new');

/* ---------------------------------------------------------------- picker */

if ($data['mode'] === 'picker') {
	$page = (new CHtmlPage())->setTitle(_('Nova solicitação'));

	if (!$data['forms']) {
		$page->addItem(Ui::notice($data['is_super_admin']
			? 'Nenhum formulário ativo. Crie um em Solicitações › Formulários.'
			: 'Nenhum formulário disponível no momento.'
		));
		$page->show();

		return;
	}

	$by_type = [];

	foreach ($data['forms'] as $form) {
		$by_type[$form['tipo']][] = $form;
	}

	foreach (FormSchema::FORM_TYPES as $type => $type_label) {
		if (!array_key_exists($type, $by_type)) {
			continue;
		}

		$cards = (new CDiv())->addClass('hf-cards');

		foreach ($by_type[$type] as $form) {
			$cards->addItem(
				(new CLink([
					(new CTag('strong', true, $form['nome'])),
					($form['descricao'] ?? '') !== '' ? (new CDiv($form['descricao']))->addClass('hf-card-desc') : null
				], (new CUrl('zabbix.php'))
					->setArgument('action', 'hostflow.request.new')
					->setArgument('formid', $form['id'])
				))->addClass('hf-card hf-card-'.$type)
			);
		}

		$page->addItem([(new CTag('h3', true, $type_label))->addClass('hf-section-title'), $cards]);
	}

	$page->show();

	return;
}

/* ---------------------------------------------------------------- done */

if ($data['mode'] === 'done') {
	$s = $data['submission'];
	$page = (new CHtmlPage())->setTitle($data['form']['nome']);

	$page->addItem(Ui::notice(
		$data['result']['mensagem'].($data['result']['referencia'] ? ' Referência: '.$data['result']['referencia'] : ''),
		$data['result']['ok'] ? 'good' : 'bad'
	));

	$summary = (new CTableInfo())->setHeader([_('Campo'), _('Valor')]);

	foreach ($s['resumo'] as $row) {
		$summary->addRow([$row['rotulo'], $row['valor']]);
	}

	$summary->addRow([_('Justificativa'), (new CDiv($s['justificativa']))->addClass('hf-pre-wrap')]);

	$diff = (new CTableInfo())
		->setHeader([_('Atributo'), _('Atual'), _('Proposto')])
		->setNoDataMessage(_('Nenhuma alteração em relação ao estado atual do host.'));

	foreach ($s['diff'] as $row) {
		$diff->addRow([
			FormSchema::TARGETS[$row['atributo']] ?? $row['atributo'],
			(new CDiv($row['atual'] !== '' ? $row['atual'] : '—'))->addClass('hf-pre-wrap hf-old'),
			(new CDiv($row['proposto'] !== '' ? $row['proposto'] : '—'))->addClass('hf-pre-wrap hf-new')
		]);
	}

	$page->addItem([
		(new CTag('h3', true, _('Dados informados')))->addClass('hf-section-title'),
		$summary,
		(new CTag('h3', true, $data['form']['tipo'] === 'create' ? _('Host a ser criado') : _('Alterações propostas')))
			->addClass('hf-section-title'),
		$diff,
		(new CTag('details', true, [
			new CTag('summary', true, _('Payload técnico (JSON)')),
			(new CTag('pre', true, json_encode($s['payload'],
				JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
			)))->addClass('hf-mono hf-json')
		]))->addClass('hf-details'),
		(new CDiv([
			new CRedirectButton(_('Nova solicitação'), $new_url),
			(new CRedirectButton(_('Outra com este formulário'), (new CUrl('zabbix.php'))
				->setArgument('action', 'hostflow.request.new')
				->setArgument('formid', $data['form']['id'])
			))->addClass(ZBX_STYLE_BTN_ALT)
		]))->addClass('hf-builder-actions')
	]);

	$page->show();

	return;
}

/* ---------------------------------------------------------------- form */

$form_def = $data['form'];
$values = $data['values'];

$page = (new CHtmlPage())->setTitle($form_def['nome']);

if (($form_def['descricao'] ?? '') !== '') {
	$page->addItem((new CDiv($form_def['descricao']))->addClass('hf-intro'));
}

if ($data['notice'] !== null) {
	$page->addItem(Ui::notice($data['notice']));
}

if ($data['errors'] || $data['field_errors']) {
	$page->addItem(Ui::errorBox('Corrija os itens abaixo antes de enviar', $data['errors']
		?: ['Há campos com erro.']
	));
}

$form = (new CForm('post', (new CUrl('zabbix.php'))->setArgument('action', 'hostflow.request.submit')->getUrl()))
	->setId('hf-request-form')
	->setName('hf_request')
	->addItem((new CVar(CSRF_TOKEN_NAME, CCsrfTokenHelper::get('hostflow.request.submit')))->removeId())
	->addItem((new CVar('formid', $form_def['id']))->removeId());

$grid = new CFormGrid();
$host_field = $data['host_field'];
$host_selected = ($host_field !== null && !empty($values[$host_field]));

foreach ($form_def['campos'] as $field) {
	$id = $field['id'];
	$name = 'campos['.$id.']';
	$dom_id = 'hf_'.$id;
	$value = $values[$id] ?? (Options::isMulti($field) ? [] : '');
	$options = $data['field_options'][$id];

	switch ($field['tipo']) {
		case 'textarea':
			$control = (new CTextArea($name, (string) $value))
				->setId($dom_id)
				->setRows(4)
				->setWidth(ZBX_TEXTAREA_STANDARD_WIDTH);
			break;

		case 'checkbox':
			$control = (new CCheckBox($name, '1'))
				->setId($dom_id)
				->setChecked($value === '1')
				->setUncheckedValue('0');
			break;

		case 'zbx_host':
			$control = (new CMultiSelect([
				'name' => $name,
				'object_name' => 'hosts',
				'multiple' => false,
				'data' => $data['host_data'][$id] ?? [],
				'popup' => [
					'parameters' => [
						'srctbl' => 'hosts',
						'srcfld1' => 'hostid',
						'dstfrm' => 'hf_request',
						'dstfld1' => zbx_formatDomId($name)
					]
				]
			]))->setWidth(ZBX_TEXTAREA_STANDARD_WIDTH);

			if ($id === $host_field) {
				$control
					->setAttribute('data-hf-reload', (new CUrl('zabbix.php'))
						->setArgument('action', 'hostflow.request.new')
						->setArgument('formid', $form_def['id'])
						->getUrl()
					)
					->setAttribute('data-hf-current', (string) $value);
			}
			break;

		default:
			if ($options === null) {
				$control = (new CTextBox($name, (string) $value))
					->setId($dom_id)
					->setWidth(ZBX_TEXTAREA_STANDARD_WIDTH);

				if ($field['tipo'] === 'ip') {
					$control->setAttribute('placeholder', '192.0.2.10');
				}
			}
			elseif (Options::isMulti($field)) {
				$checkboxes = [];

				foreach ($options as $i => $option) {
					$checkboxes[] = [
						'name' => $name.'[]',
						'id' => $dom_id.'_'.$i,
						'label' => $option['rotulo'],
						'value' => $option['valor'],
						'checked' => in_array($option['valor'], (array) $value, true)
					];
				}

				$control = $checkboxes
					? (new CDiv((new CCheckBoxList())->setOptions($checkboxes)->setVertical()))->addClass('hf-checklist')
					: (new CDiv('Nenhuma opção disponível para o seu usuário.'))->addClass(ZBX_STYLE_RED);
			}
			else {
				$control = (new CSelect($name))
					->setId($dom_id)
					->setFocusableElementId($dom_id.'_btn')
					->setWidth(ZBX_TEXTAREA_STANDARD_WIDTH)
					->addOption(new CSelectOption('', '— selecione —'));

				foreach ($options as $option) {
					$control->addOption(new CSelectOption($option['valor'], $option['rotulo']));
				}

				$control->setValue((string) $value);

				if (!$options) {
					$control->setDisabled();
				}
			}
	}

	$field_items = [$control];

	if (($field['ajuda'] ?? '') !== '') {
		$field_items[] = (new CDiv($field['ajuda']))->addClass(ZBX_STYLE_FORM_FIELDS_HINT);
	}

	foreach ($data['field_errors'][$id] ?? [] as $error) {
		$field_items[] = (new CDiv($error))->addClass('hf-field-error');
	}

	$label_for = ($control instanceof CSelect) ? $dom_id.'_btn' : $dom_id;
	$label = (new CLabel($field['rotulo'], $label_for))->setAsteriskMark($field['obrigatorio']);

	$field_el = new CFormField($field_items);

	foreach ([$label, $field_el] as $el) {
		$el->setAttribute('data-hf-field', $id);

		if (!empty($field['quando']['regras'])) {
			$el->setAttribute('data-hf-when', $field['quando']);
		}

		// Em update/move/delete, os demais campos só aparecem depois de escolher o host.
		if ($host_field !== null && $id !== $host_field && !$host_selected) {
			$el->addClass('hf-needs-host');
		}

		if (!empty($data['field_errors'][$id])) {
			$el->addClass('hf-has-error');
		}
	}

	$grid->addItem([$label, $field_el]);
}

$grid->addItem([
	(new CLabel(_('Justificativa'), 'hf_justificativa'))->setAsteriskMark(),
	new CFormField([
		(new CTextArea('justificativa', $data['justificativa']))
			->setId('hf_justificativa')
			->setRows(3)
			->setWidth(ZBX_TEXTAREA_STANDARD_WIDTH)
			->setAttribute('maxlength', 4000),
		(new CDiv('Por que esta solicitação é necessária? Vai junto com o pedido para a equipe responsável.'))
			->addClass(ZBX_STYLE_FORM_FIELDS_HINT)
	])
]);

$grid->addItem(new CFormActions(new CSubmit('enviar', _('Enviar solicitação')), [
	new CRedirectButton(_('Cancelar'), $new_url)
]));

if ($host_field !== null && !$host_selected) {
	$form->addClass('hf-waiting-host');
}

$form->addItem($grid);
$page->addItem($form)->show();
