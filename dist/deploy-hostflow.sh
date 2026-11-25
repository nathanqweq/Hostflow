#!/usr/bin/env bash
# HostFlow: deploy. Cada bloco "cat > ..." regrava um arquivo inteiro.
# Rode como root no servidor do FRONTEND. Ajuste ZBX_UI se o frontend estiver em outro caminho
# (é o diretório onde fica o zabbix.php).
set -euo pipefail

ZBX_UI="${ZBX_UI:-/usr/share/zabbix}"
MOD="$ZBX_UI/modules/hostflow"

if [ ! -f "$ZBX_UI/zabbix.php" ]; then
	echo "zabbix.php não encontrado em $ZBX_UI. Rode: ZBX_UI=/caminho/do/frontend bash $0" >&2
	exit 1
fi

mkdir -p "$MOD"
mkdir -p "$MOD/actions"
mkdir -p "$MOD/assets"
mkdir -p "$MOD/assets/css"
mkdir -p "$MOD/assets/js"
mkdir -p "$MOD/lib"
mkdir -p "$MOD/lib/form"
mkdir -p "$MOD/lib/storage"
mkdir -p "$MOD/lib/submit"
mkdir -p "$MOD/views"

# ---- Module.php
cat > "$MOD/Module.php" <<'HOSTFLOW_EOF'
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
		}

		APP::Component()->get('menu.main')->add(
			(new CMenuItem(_('Solicitações')))
				->setIcon(ZBX_ICON_TEXT)
				->setSubMenu(new CMenu($items))
		);
	}
}
HOSTFLOW_EOF

# ---- actions/BaseAction.php
cat > "$MOD/actions/BaseAction.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CController;
use CControllerResponseRedirect;
use CMessageHelper;
use CUrl;
use Modules\HostFlow\Lib\Form\FormSchema;
use Modules\HostFlow\Lib\Form\Repository;

abstract class BaseAction extends CController {

	private ?Repository $repository = null;

	protected function repo(): Repository {
		if ($this->repository === null) {
			$this->repository = new Repository();
		}

		return $this->repository;
	}

	protected function isSuperAdmin(): bool {
		return $this->getUserType() == USER_TYPE_SUPER_ADMIN;
	}

	protected function redirectTo(string $action, ?string $success = null, ?string $error = null): void {
		if ($success !== null) {
			CMessageHelper::setSuccessTitle($success);
		}

		if ($error !== null) {
			CMessageHelper::setErrorTitle($error);
		}

		$this->setResponse(new CControllerResponseRedirect((new CUrl('zabbix.php'))->setArgument('action', $action)));
	}

	/**
	 * Dados de apoio para o construtor de formulários (renderizado em JS).
	 */
	protected function builderConfig(): array {
		$lists = [];

		foreach ($this->repo()->lists() as $id => $list) {
			$lists[] = ['id' => $id, 'nome' => $list['nome'] ?? $id];
		}

		return [
			'form_types' => FormSchema::FORM_TYPES,
			'field_types' => FormSchema::FIELD_TYPES,
			'option_types' => FormSchema::OPTION_TYPES,
			'text_types' => FormSchema::TEXT_TYPES,
			'allowed_types' => FormSchema::ALLOWED_TYPES,
			'multi_capable' => FormSchema::MULTI_CAPABLE,
			'targets' => FormSchema::TARGETS,
			'target_prefixes' => FormSchema::TARGET_PREFIXES,
			'group_modes' => FormSchema::GROUP_MODES,
			'template_modes' => FormSchema::TEMPLATE_MODES,
			'inventory_fields' => FormSchema::inventoryFields() ?? [],
			'lists' => $lists
		];
	}
}
HOSTFLOW_EOF

# ---- actions/FormDelete.php
cat > "$MOD/actions/FormDelete.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseFatal;
use Throwable;

class FormDelete extends BaseAction {

	protected function checkInput(): bool {
		$ret = $this->validateInput(['formid' => 'required|string']);

		if (!$ret) {
			$this->setResponse(new CControllerResponseFatal());
		}

		return $ret;
	}

	protected function checkPermissions(): bool {
		return $this->isSuperAdmin();
	}

	protected function doAction(): void {
		$id = $this->getInput('formid');

		try {
			$this->repo()->deleteForm($id);
			$this->redirectTo('hostflow.form.list', sprintf('Formulário "%s" excluído.', $id));
		}
		catch (Throwable $e) {
			$this->redirectTo('hostflow.form.list', null, $e->getMessage());
		}
	}
}
HOSTFLOW_EOF

# ---- actions/FormEdit.php
cat > "$MOD/actions/FormEdit.php" <<'HOSTFLOW_EOF'
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
HOSTFLOW_EOF

# ---- actions/FormList.php
cat > "$MOD/actions/FormList.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;

class FormList extends BaseAction {

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
		$store = $this->repo()->formsStore();

		$response = new CControllerResponseData([
			'forms' => $this->repo()->forms(),
			'data_dir' => dirname($store->getDir()),
			'writable' => $store->isWritable()
		]);
		$response->setTitle(_('Formulários de solicitação'));
		$this->setResponse($response);
	}
}
HOSTFLOW_EOF

# ---- actions/FormSave.php
cat > "$MOD/actions/FormSave.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;
use CControllerResponseFatal;
use Modules\HostFlow\Lib\Form\FormSchema;
use Throwable;

class FormSave extends BaseAction {

	protected function checkInput(): bool {
		$ret = $this->validateInput([
			'definition' => 'required|string',
			'original_id' => 'string'
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
		$raw = $this->getInput('definition');
		$original_id = $this->getInput('original_id', '');
		$definition = json_decode($raw, true);

		if (!is_array($definition)) {
			$this->showErrors(null, $raw, $original_id, ['JSON inválido: '.json_last_error_msg().'.']);

			return;
		}

		$schema = new FormSchema();
		$form = $schema->validate($definition, $this->repo()->lists());

		if ($form === null) {
			$this->showErrors($definition, null, $original_id, $schema->getErrors());

			return;
		}

		$existing = $this->repo()->form($form['id']);

		if ($existing !== null && $form['id'] !== $original_id) {
			$this->showErrors($definition, null, $original_id,
				[sprintf('Já existe um formulário com o ID "%s".', $form['id'])]
			);

			return;
		}

		if ($original_id !== '' && ($previous = $this->repo()->form($original_id)) !== null) {
			$form['versao'] = (int) ($previous['versao'] ?? 1) + 1;
		}

		try {
			$this->repo()->saveForm($form);

			if ($original_id !== '' && $original_id !== $form['id']) {
				$this->repo()->deleteForm($original_id);
			}
		}
		catch (Throwable $e) {
			$this->showErrors($definition, null, $original_id, [$e->getMessage()]);

			return;
		}

		$this->redirectTo('hostflow.form.list', sprintf('Formulário "%s" salvo (versão %d).', $form['nome'],
			$form['versao']
		));
	}

	private function showErrors(?array $definition, ?string $raw, string $original_id, array $errors): void {
		$response = new CControllerResponseData([
			'definition' => $definition ?? FormEdit::newDefinition(),
			'definition_raw' => $raw,
			'original_id' => $original_id,
			'errors' => $errors,
			'builder' => $this->builderConfig()
		]);
		$response->setTitle(_('Editar formulário'));
		$this->setResponse($response);
	}
}
HOSTFLOW_EOF

# ---- actions/ListDelete.php
cat > "$MOD/actions/ListDelete.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseFatal;
use Throwable;

class ListDelete extends BaseAction {

	protected function checkInput(): bool {
		$ret = $this->validateInput(['listid' => 'required|string']);

		if (!$ret) {
			$this->setResponse(new CControllerResponseFatal());
		}

		return $ret;
	}

	protected function checkPermissions(): bool {
		return $this->isSuperAdmin();
	}

	protected function doAction(): void {
		$id = $this->getInput('listid');
		$used_by = $this->repo()->formsUsingList($id);

		if ($used_by) {
			$this->redirectTo('hostflow.list.list', null,
				sprintf('A lista "%s" é usada por: %s. Remova-a desses formulários antes.', $id, implode(', ', $used_by))
			);

			return;
		}

		try {
			$this->repo()->deleteList($id);
			$this->redirectTo('hostflow.list.list', sprintf('Lista "%s" excluída.', $id));
		}
		catch (Throwable $e) {
			$this->redirectTo('hostflow.list.list', null, $e->getMessage());
		}
	}
}
HOSTFLOW_EOF

# ---- actions/ListEdit.php
cat > "$MOD/actions/ListEdit.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;
use CControllerResponseFatal;
use Modules\HostFlow\Lib\Form\ListSchema;

class ListEdit extends BaseAction {

	protected function init(): void {
		$this->disableCsrfValidation();
	}

	protected function checkInput(): bool {
		$ret = $this->validateInput(['listid' => 'string']);

		if (!$ret) {
			$this->setResponse(new CControllerResponseFatal());
		}

		return $ret;
	}

	protected function checkPermissions(): bool {
		return $this->isSuperAdmin();
	}

	protected function doAction(): void {
		$data = ['original_id' => '', 'id' => '', 'nome' => '', 'itens_text' => '', 'errors' => []];

		if ($this->hasInput('listid')) {
			$list = $this->repo()->list($this->getInput('listid'));

			if ($list === null) {
				$this->setResponse(new CControllerResponseFatal());

				return;
			}

			$data['original_id'] = $list['id'];
			$data['id'] = $list['id'];
			$data['nome'] = $list['nome'] ?? '';
			$data['itens_text'] = ListSchema::toText($list['itens'] ?? []);
		}

		$response = new CControllerResponseData($data);
		$response->setTitle(_('Editar lista de valores'));
		$this->setResponse($response);
	}
}
HOSTFLOW_EOF

# ---- actions/ListList.php
cat > "$MOD/actions/ListList.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;

class ListList extends BaseAction {

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
		$lists = $this->repo()->lists();
		$usage = [];

		foreach (array_keys($lists) as $id) {
			$usage[$id] = $this->repo()->formsUsingList($id);
		}

		$response = new CControllerResponseData([
			'lists' => $lists,
			'usage' => $usage,
			'writable' => $this->repo()->listsStore()->isWritable(),
			'data_dir' => dirname($this->repo()->listsStore()->getDir())
		]);
		$response->setTitle(_('Listas de valores'));
		$this->setResponse($response);
	}
}
HOSTFLOW_EOF

# ---- actions/ListSave.php
cat > "$MOD/actions/ListSave.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;
use CControllerResponseFatal;
use Modules\HostFlow\Lib\Form\ListSchema;
use Throwable;

class ListSave extends BaseAction {

	protected function checkInput(): bool {
		$ret = $this->validateInput([
			'original_id' => 'string',
			'id' => 'required|string',
			'nome' => 'required|string',
			'itens_text' => 'required|string'
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
		$original_id = $this->getInput('original_id', '');
		$schema = new ListSchema();

		$list = $schema->validate([
			'id' => $this->getInput('id'),
			'nome' => $this->getInput('nome'),
			'itens' => ListSchema::parseText($this->getInput('itens_text'))
		]);

		$errors = $schema->getErrors();

		if ($list !== null) {
			if ($list['id'] !== $original_id && $this->repo()->list($list['id']) !== null) {
				$errors[] = sprintf('Já existe uma lista com o ID "%s".', $list['id']);
			}
			elseif ($original_id !== '' && $list['id'] !== $original_id
					&& ($used_by = $this->repo()->formsUsingList($original_id))) {
				$errors[] = sprintf('O ID não pode mudar: a lista é usada por %s.', implode(', ', $used_by));
			}
		}

		if (!$errors) {
			try {
				$this->repo()->saveList($list);

				if ($original_id !== '' && $original_id !== $list['id']) {
					$this->repo()->deleteList($original_id);
				}

				$this->redirectTo('hostflow.list.list', sprintf('Lista "%s" salva com %d itens.', $list['nome'],
					count($list['itens'])
				));

				return;
			}
			catch (Throwable $e) {
				$errors[] = $e->getMessage();
			}
		}

		$response = new CControllerResponseData([
			'original_id' => $original_id,
			'id' => $this->getInput('id'),
			'nome' => $this->getInput('nome'),
			'itens_text' => $this->getInput('itens_text'),
			'errors' => $errors
		]);
		$response->setTitle(_('Editar lista de valores'));
		$this->setResponse($response);
	}
}
HOSTFLOW_EOF

# ---- actions/RequestNew.php
cat > "$MOD/actions/RequestNew.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;
use CControllerResponseFatal;
use Modules\HostFlow\Lib\Form\HostState;
use Modules\HostFlow\Lib\Form\Options;
use Modules\HostFlow\Lib\Form\ZabbixLookup;

/**
 * Sem formid: lista os formulários ativos. Com formid: renderiza o formulário.
 * Em update/move/delete, escolher o host recarrega a página com &hostid=..., e os campos
 * vêm preenchidos com os valores atuais do host.
 */
class RequestNew extends BaseAction {

	protected function init(): void {
		$this->disableCsrfValidation();
	}

	protected function checkInput(): bool {
		$ret = $this->validateInput([
			'formid' => 'string',
			'hostid' => 'id'
		]);

		if (!$ret) {
			$this->setResponse(new CControllerResponseFatal());
		}

		return $ret;
	}

	protected function checkPermissions(): bool {
		// Quem chegou aqui já tem acesso ao módulo pelo User role (o frontend não carrega o módulo sem isso).
		return true;
	}

	protected function doAction(): void {
		if (!$this->hasInput('formid')) {
			$response = new CControllerResponseData([
				'mode' => 'picker',
				'forms' => $this->repo()->forms(true),
				'is_super_admin' => $this->isSuperAdmin()
			]);
			$response->setTitle(_('Nova solicitação'));
			$this->setResponse($response);

			return;
		}

		$form = $this->repo()->form($this->getInput('formid'));

		// Formulário inativo: só o Super admin abre (para testar antes de publicar).
		if ($form === null || (empty($form['ativo']) && !$this->isSuperAdmin())) {
			$this->setResponse(new CControllerResponseFatal());

			return;
		}

		$options = new Options($this->repo()->lists());
		$values = [];
		$notice = null;

		foreach ($form['campos'] as $field) {
			if (($field['valor_padrao'] ?? '') !== '') {
				$values[$field['id']] = Options::isMulti($field) ? [$field['valor_padrao']] : $field['valor_padrao'];
			}
		}

		if ($this->hasInput('hostid') && $form['tipo'] !== 'create') {
			$state = HostState::read($this->getInput('hostid'));

			if ($state !== null) {
				$values = array_replace($values, HostState::prefill($form, $state, $options));
				$values[self::hostFieldId($form)] = $state['hostid'];
				$notice = sprintf('Valores atuais de "%s" carregados. Altere apenas o necessário.',
					$state['host']['name']
				);
			}
			else {
				$notice = 'Host não encontrado ou sem permissão de leitura.';
			}
		}

		$response = new CControllerResponseData(self::formViewData($form, $options, $values, [], [], '', $notice));
		$response->setTitle($form['nome']);
		$this->setResponse($response);
	}

	public static function hostFieldId(array $form): ?string {
		foreach ($form['campos'] as $field) {
			if ($field['tipo'] === 'zbx_host' && in_array('hostid', array_column($field['mapeamento'], 'alvo'), true)) {
				return $field['id'];
			}
		}

		return null;
	}

	/**
	 * Dados da view no modo "form" (também usado quando o envio volta com erros).
	 */
	public static function formViewData(array $form, Options $options, array $values, array $field_errors,
			array $errors, string $justificativa, ?string $notice): array {
		$field_options = [];
		$host_data = [];

		foreach ($form['campos'] as $field) {
			$field_options[$field['id']] = $options->forField($field);

			if ($field['tipo'] === 'zbx_host' && !empty($values[$field['id']])) {
				$host = ZabbixLookup::host((string) $values[$field['id']]);

				if ($host !== null) {
					$host_data[$field['id']] = [['id' => $host['hostid'], 'name' => $host['name']]];
				}
			}
		}

		return [
			'mode' => 'form',
			'form' => $form,
			'field_options' => $field_options,
			'host_data' => $host_data,
			'host_field' => self::hostFieldId($form),
			'values' => $values,
			'field_errors' => $field_errors,
			'errors' => $errors,
			'justificativa' => $justificativa,
			'notice' => $notice
		];
	}
}
HOSTFLOW_EOF

# ---- actions/RequestSubmit.php
cat > "$MOD/actions/RequestSubmit.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Actions;

use CControllerResponseData;
use CControllerResponseFatal;
use CWebUser;
use Modules\HostFlow\Lib\Config;
use Modules\HostFlow\Lib\Form\HostState;
use Modules\HostFlow\Lib\Form\Options;
use Modules\HostFlow\Lib\Form\Submission;
use Modules\HostFlow\Lib\Submit\NullSubmitHandler;
use Modules\HostFlow\Lib\Submit\SubmitHandler;
use Throwable;

class RequestSubmit extends BaseAction {

	protected function checkInput(): bool {
		$ret = $this->validateInput([
			'formid' => 'required|string',
			'campos' => 'array',
			'justificativa' => 'string'
		]);

		if (!$ret) {
			$this->setResponse(new CControllerResponseFatal());
		}

		return $ret;
	}

	protected function checkPermissions(): bool {
		return true;
	}

	protected function doAction(): void {
		$form = $this->repo()->form($this->getInput('formid'));

		if ($form === null || (empty($form['ativo']) && !$this->isSuperAdmin())) {
			$this->setResponse(new CControllerResponseFatal());

			return;
		}

		$options = new Options($this->repo()->lists());
		$submission = new Submission($form, $options);
		$raw = $this->getInput('campos', []);
		$justificativa = trim($this->getInput('justificativa', ''));

		$submission->validateFields($raw);

		$errors = [];

		if ($justificativa === '') {
			$errors[] = 'Informe a justificativa.';
		}
		elseif (mb_strlen($justificativa) > 4000) {
			$errors[] = 'A justificativa deve ter no máximo 4000 caracteres.';
		}

		$payload = null;
		$current = null;

		if (!$submission->hasErrors()) {
			$payload = $submission->buildPayload();

			if ($form['tipo'] !== 'create') {
				$current = HostState::read((string) ($payload['hostid'] ?? ''));
			}

			$submission->validatePayload($payload, $current);
		}

		if ($submission->hasErrors() || $errors) {
			$values = $submission->getValues();

			// Mantém o que o usuário digitou, inclusive campos ocultos.
			foreach ($form['campos'] as $field) {
				if ($values[$field['id']] === null && array_key_exists($field['id'], $raw)) {
					$values[$field['id']] = Submission::normalize($field, $raw[$field['id']]);
				}
			}

			$response = new CControllerResponseData(RequestNew::formViewData($form, $options, $values,
				$submission->getFieldErrors(), array_merge($submission->getErrors(), $errors), $justificativa, null
			));
			$response->setTitle($form['nome']);
			$this->setResponse($response);

			return;
		}

		$before = $current ?? HostState::emptyState();
		$after = HostState::apply($before, $payload);

		$data = [
			'formulario' => $form,
			'valores' => $submission->getValues(),
			'resumo' => self::summary($form, $submission->getValues(), $options),
			'payload' => $payload,
			'host_atual' => $current,
			'diff' => HostState::diff($before, $after),
			'justificativa' => $justificativa,
			'solicitante' => [
				'userid' => CWebUser::$data['userid'] ?? null,
				'username' => CWebUser::$data['username'] ?? null,
				'name' => CWebUser::$data['name'] ?? '',
				'surname' => CWebUser::$data['surname'] ?? ''
			],
			'enviado_em' => time()
		];

		try {
			$result = self::handler()->handle($data);
		}
		catch (Throwable $e) {
			$result = ['ok' => false, 'mensagem' => 'Falha no envio: '.$e->getMessage(), 'referencia' => null];
		}

		$response = new CControllerResponseData([
			'mode' => 'done',
			'form' => $form,
			'submission' => $data,
			'result' => $result + ['ok' => false, 'mensagem' => '', 'referencia' => null]
		]);
		$response->setTitle($form['nome']);
		$this->setResponse($response);
	}

	private static function handler(): SubmitHandler {
		$class = Config::get('submit_handler');

		if (is_string($class) && $class !== '' && class_exists($class)
				&& is_subclass_of($class, SubmitHandler::class)) {
			return new $class();
		}

		return new NullSubmitHandler();
	}

	/**
	 * Resumo legível: rótulo do campo => rótulo do valor escolhido.
	 */
	private static function summary(array $form, array $values, Options $options): array {
		$rows = [];

		foreach ($form['campos'] as $field) {
			$value = $values[$field['id']] ?? null;

			if ($value === null || $value === '' || $value === []) {
				continue;
			}

			if ($field['tipo'] === 'checkbox') {
				$text = ($value === '1') ? 'Sim' : 'Não';
			}
			elseif ($field['tipo'] === 'zbx_host') {
				$state = HostState::read((string) $value);
				$text = ($state !== null) ? $state['host']['name'].' ('.$state['host']['host'].')' : (string) $value;
			}
			else {
				$labels = [];
				$field_options = $options->forField($field);

				foreach ((array) $value as $v) {
					$label = $v;

					foreach ($field_options ?? [] as $option) {
						if ($option['valor'] === $v) {
							$label = $option['rotulo'];
							break;
						}
					}

					$labels[] = $label;
				}

				$text = implode(', ', $labels);
			}

			$rows[] = ['campo' => $field['id'], 'rotulo' => $field['rotulo'], 'valor' => $text];
		}

		return $rows;
	}
}
HOSTFLOW_EOF

# ---- assets/css/hostflow.css
cat > "$MOD/assets/css/hostflow.css" <<'HOSTFLOW_EOF'
/* HostFlow: estilos do módulo. Cores neutras, com transparência, para funcionar em todos os temas do Zabbix. */

.hf-intro {
	margin: 0 0 12px;
	opacity: .8;
	max-width: 900px;
}

.hf-alert {
	margin: 0 0 12px;
	padding: 10px 14px;
	border-left: 4px solid #0275b8;
	background: rgba(2, 117, 184, .08);
	border-radius: 2px;
}

.hf-alert ul {
	margin: 6px 0 0 18px;
	list-style: disc;
}

.hf-alert-bad {
	border-left-color: #e45959;
	background: rgba(228, 89, 89, .1);
}

.hf-alert-good {
	border-left-color: #59db8f;
	background: rgba(89, 219, 143, .12);
}

.hf-field-error {
	color: #e45959;
	margin-top: 4px;
}

.hf-hidden,
.hf-waiting-host .hf-needs-host {
	display: none !important;
}

.hf-loading {
	opacity: .5;
	pointer-events: none;
}

.hf-mono {
	font-family: "DejaVu Sans Mono", Consolas, monospace;
}

.hf-pre-wrap {
	white-space: pre-wrap;
	word-break: break-word;
}

.hf-old {
	opacity: .7;
}

.hf-new {
	font-weight: bold;
}

.hf-checklist {
	max-height: 260px;
	overflow: auto;
	padding: 4px 0;
}

.hf-section-title {
	margin: 18px 0 8px;
	font-size: 14px;
}

.hf-details {
	margin-top: 16px;
}

.hf-details summary {
	cursor: pointer;
}

.hf-json {
	max-height: 420px;
	overflow: auto;
	padding: 10px;
	background: rgba(127, 127, 127, .08);
	white-space: pre;
}

.hf-row-actions {
	display: flex;
	gap: 12px;
	align-items: center;
}

.hf-inline-form {
	display: inline;
}

.hf-builder-actions {
	display: flex;
	gap: 8px;
	margin: 16px 0;
}

/* cartões de escolha de formulário */

.hf-cards {
	display: grid;
	grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
	gap: 10px;
	max-width: 1200px;
}

.hf-card {
	display: block;
	padding: 12px 14px;
	border: 1px solid rgba(127, 127, 127, .35);
	border-left: 4px solid #0275b8;
	border-radius: 2px;
	text-decoration: none;
}

.hf-card:hover,
.hf-card:focus {
	background: rgba(127, 127, 127, .08);
}

.hf-card-update { border-left-color: #f0a14a; }
.hf-card-move { border-left-color: #a07ae0; }
.hf-card-delete { border-left-color: #e45959; }

.hf-card-desc {
	margin-top: 4px;
	opacity: .75;
}

/* construtor */

#hf-builder {
	max-width: 1280px;
}

.hf-b-tabs {
	display: flex;
	gap: 6px;
	margin-bottom: 12px;
}

.hf-b-section {
	margin: 0 0 18px;
}

.hf-b-section h4 {
	font-size: 14px;
	margin: 0 0 8px;
}

.hf-b-row {
	display: flex;
	flex-wrap: wrap;
	gap: 10px 16px;
	margin-bottom: 8px;
	align-items: flex-end;
}

.hf-b-prop {
	display: flex;
	flex-direction: column;
	min-width: 180px;
}

.hf-b-grow {
	flex: 1 1 280px;
}

.hf-b-prop input[type="text"],
.hf-b-prop select,
.hf-b-prop textarea {
	width: 100%;
	box-sizing: border-box;
}

.hf-b-label {
	font-weight: bold;
	margin-bottom: 3px;
}

.hf-b-hint {
	opacity: .7;
	margin-top: 3px;
	font-size: 11px;
}

.hf-b-muted {
	opacity: .6;
}

.hf-b-check {
	display: inline-flex;
	align-items: center;
	gap: 4px;
	white-space: nowrap;
	padding-bottom: 4px;
}

.hf-b-card {
	border: 1px solid rgba(127, 127, 127, .35);
	border-radius: 2px;
	margin-bottom: 10px;
}

.hf-b-card-head {
	display: flex;
	align-items: center;
	gap: 6px;
	padding: 6px 10px;
	background: rgba(127, 127, 127, .08);
	border-bottom: 1px solid rgba(127, 127, 127, .25);
}

.hf-b-card-num {
	opacity: .6;
	min-width: 28px;
}

.hf-b-spacer {
	flex: 1;
}

.hf-b-card-body {
	padding: 10px;
}

.hf-b-icon {
	min-width: 28px;
	padding: 0 6px;
}

.hf-b-danger {
	color: #e45959;
}

.hf-b-tab-on {
	pointer-events: none;
}

.hf-b-maps {
	margin-top: 6px;
}

.hf-b-table {
	width: 100%;
	border-collapse: collapse;
	margin: 4px 0 6px;
}

.hf-b-table th {
	text-align: left;
	font-weight: bold;
	padding: 4px 6px;
	border-bottom: 1px solid rgba(127, 127, 127, .3);
}

.hf-b-table td {
	padding: 4px 6px;
	vertical-align: top;
	border-bottom: 1px solid rgba(127, 127, 127, .15);
}

.hf-b-table input[type="text"],
.hf-b-table select {
	width: 100%;
	box-sizing: border-box;
}

.hf-b-target,
.hf-b-mode,
.hf-b-cond {
	display: flex;
	gap: 6px;
	align-items: center;
}

.hf-b-target-base {
	min-width: 220px;
}

.hf-b-target-name {
	min-width: 140px;
}

.hf-b-json {
	width: 100%;
	min-height: 520px;
	box-sizing: border-box;
}

.hf-b-help {
	margin: 8px 0 0;
	max-width: 900px;
}

.hf-b-help summary {
	cursor: pointer;
	font-weight: bold;
}

.hf-b-help ul {
	margin: 6px 0 0 18px;
	list-style: disc;
}
HOSTFLOW_EOF

# ---- assets/js/hostflow.builder.js
cat > "$MOD/assets/js/hostflow.builder.js" <<'HOSTFLOW_EOF'
/*
 * HostFlow: construtor visual de formulários.
 *
 * Mantém a definição em memória (state), redesenha a tela em mudanças estruturais e,
 * ao salvar, serializa tudo no campo oculto "definition". A aba JSON edita a mesma definição.
 * Toda validação definitiva acontece no servidor (FormSchema).
 */
(function () {
	'use strict';

	var root, cfg, state, tab = 'visual', jsonText = '';

	/* ------------------------------------------------------------ helpers */

	function h(tag, props) {
		var el = document.createElement(tag);
		var children = Array.prototype.slice.call(arguments, 2);

		props = props || {};

		Object.keys(props).forEach(function (key) {
			var v = props[key];

			if (v === undefined || v === null) {
				return;
			}

			if (key === 'class') {
				el.className = v;
			}
			else if (key === 'text') {
				el.textContent = v;
			}
			else if (key === 'on') {
				Object.keys(v).forEach(function (ev) {
					el.addEventListener(ev, v[ev]);
				});
			}
			else if (key === 'value') {
				el.value = v;
			}
			else if (key === 'checked' || key === 'disabled' || key === 'selected') {
				el[key] = !!v;
			}
			else {
				el.setAttribute(key, v);
			}
		});

		append(el, children);

		return el;
	}

	function append(el, children) {
		children.forEach(function (child) {
			if (child === null || child === undefined || child === false) {
				return;
			}

			if (Array.isArray(child)) {
				append(el, child);
			}
			else {
				el.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
			}
		});
	}

	function textInput(value, onInput, attrs) {
		return h('input', Object.assign({type: 'text', value: value || '', on: {input: function (e) {
			onInput(e.target.value);
		}}}, attrs || {}));
	}

	function textArea(value, onInput, attrs) {
		return h('textarea', Object.assign({value: value || '', rows: 4, on: {input: function (e) {
			onInput(e.target.value);
		}}}, attrs || {}));
	}

	function checkbox(checked, onChange, label) {
		return h('label', {class: 'hf-b-check'},
			h('input', {type: 'checkbox', checked: checked, on: {change: function (e) {
				onChange(e.target.checked);
			}}}),
			' ' + label
		);
	}

	/* options: [[value, label], ...] */
	function select(value, options, onChange, attrs) {
		var el = h('select', Object.assign({on: {change: function (e) {
			onChange(e.target.value);
		}}}, attrs || {}));

		options.forEach(function (opt) {
			el.appendChild(h('option', {value: opt[0], text: opt[1], selected: String(opt[0]) === String(value)}));
		});

		return el;
	}

	function prop(label, control, hint, cls) {
		return h('div', {class: 'hf-b-prop' + (cls ? ' ' + cls : '')},
			h('label', {class: 'hf-b-label', text: label}),
			control,
			hint ? h('div', {class: 'hf-b-hint', text: hint}) : null
		);
	}

	function button(text, onClick, cls, title) {
		return h('button', {type: 'button', class: cls || 'btn-alt', text: text, title: title || null,
			on: {click: function (e) {
				e.preventDefault();
				onClick();
			}}
		});
	}

	function entries(obj) {
		return Object.keys(obj).map(function (k) {
			return [k, obj[k]];
		});
	}

	function inArray(v, arr) {
		return arr.indexOf(v) !== -1;
	}

	function move(arr, i, delta) {
		var j = i + delta;

		if (j < 0 || j >= arr.length) {
			return;
		}

		var tmp = arr[i];
		arr[i] = arr[j];
		arr[j] = tmp;
	}

	/* ------------------------------------------------------------ conversões */

	function optionsToText(opcoes) {
		return (opcoes || []).map(function (o) {
			return (o.rotulo && o.rotulo !== o.valor) ? o.valor + ' | ' + o.rotulo : o.valor;
		}).join('\n');
	}

	function textToOptions(text) {
		return text.split(/\r?\n/).map(function (line) {
			var parts = line.split('|');
			var valor = (parts[0] || '').trim();
			var rotulo = parts.slice(1).join('|').trim();

			return {valor: valor, rotulo: rotulo || valor};
		}).filter(function (o) {
			return o.valor !== '';
		});
	}

	function linesToList(text) {
		return text.split(/\r?\n/).map(function (s) {
			return s.trim();
		}).filter(Boolean);
	}

	function splitTarget(alvo) {
		alvo = alvo || '';

		var prefixes = Object.keys(cfg.target_prefixes);

		for (var i = 0; i < prefixes.length; i++) {
			if (alvo.indexOf(prefixes[i]) === 0) {
				return {base: prefixes[i], name: alvo.substring(prefixes[i].length)};
			}
		}

		return {base: alvo, name: ''};
	}

	/* ------------------------------------------------------------ editores reutilizáveis */

	/* Alvo do mapeamento: alvo fixo, ou prefixo + nome (tag:, macro:, inventory.). */
	function targetEditor(map) {
		var t = splitTarget(map.alvo);
		var opts = [['', '— alvo —']];

		entries(cfg.targets).forEach(function (e) {
			opts.push([e[0], e[0] + '  ·  ' + e[1]]);
		});

		entries(cfg.target_prefixes).forEach(function (e) {
			opts.push([e[0], e[0] + '<nome>  ·  ' + e[1]]);
		});

		var wrap = h('div', {class: 'hf-b-target'});

		wrap.appendChild(select(t.base, opts, function (v) {
			map.alvo = (v in cfg.target_prefixes) ? v + (splitTarget(map.alvo).base === v ? t.name : '') : v;

			if (v !== 'groups[]' && v !== 'templates[]') {
				delete map.modo;
				delete map.prefixo;
			}

			render();
		}, {class: 'hf-b-target-base'}));

		if (t.base in cfg.target_prefixes) {
			if (t.base === 'inventory.' && cfg.inventory_fields.length) {
				wrap.appendChild(select(t.name, [['', '— campo —']].concat(cfg.inventory_fields.map(function (f) {
					return [f, f];
				})), function (v) {
					map.alvo = t.base + v;
				}));
			}
			else {
				wrap.appendChild(textInput(t.name, function (v) {
					map.alvo = t.base + v;
				}, {placeholder: t.base === 'macro:' ? '{$NOME}' : 'NOME', class: 'hf-b-target-name'}));
			}
		}

		return wrap;
	}

	function modeEditor(map) {
		var base = splitTarget(map.alvo).base;

		if (base === 'groups[]') {
			return h('div', {class: 'hf-b-mode'},
				select(map.modo || 'adicionar', cfg.group_modes.map(function (m) {
					return [m, m === 'adicionar' ? 'adicionar ao host' : 'substituir grupos com prefixo'];
				}), function (v) {
					map.modo = v;
					render();
				}),
				(map.modo === 'substituir_prefixo')
					? textInput(map.prefixo, function (v) {
						map.prefixo = v;
					}, {placeholder: 'Sites/'})
					: null
			);
		}

		if (base === 'templates[]') {
			return h('div', {class: 'hf-b-mode'},
				select(map.modo || 'vincular', cfg.template_modes.map(function (m) {
					return [m, m];
				}), function (v) {
					map.modo = v;
				})
			);
		}

		return h('div', {class: 'hf-b-mode hf-b-muted', text: '—'});
	}

	function conditionEditor(owner, selfId) {
		var others = [['', '— sempre exibir —']].concat(state.campos.filter(function (f) {
			return f.id && f.id !== selfId;
		}).map(function (f) {
			return [f.id, f.id + (f.rotulo ? ' (' + f.rotulo + ')' : '')];
		}));

		var cond = owner.quando || {campo: '', igual: ''};

		return h('div', {class: 'hf-b-cond'},
			select(cond.campo, others, function (v) {
				owner.quando = v ? {campo: v, igual: cond.igual || ''} : null;
				render();
			}),
			cond.campo ? h('span', {class: 'hf-b-muted', text: ' for igual a '}) : null,
			cond.campo ? textInput(cond.igual, function (v) {
				owner.quando.igual = v;
			}, {placeholder: 'valor (checkbox: 1)'}) : null
		);
	}

	/* ------------------------------------------------------------ campo */

	function fieldCard(field, i) {
		var type = field.tipo;
		var isText = inArray(type, cfg.text_types);
		var isOption = inArray(type, cfg.option_types);
		var isAllowed = inArray(type, cfg.allowed_types);
		var isMultiCap = inArray(type, cfg.multi_capable);

		field.mapeamento = field.mapeamento || [];

		var typeOpts = entries(cfg.field_types);
		var listOpts = [['', '— opções próprias (abaixo) —']].concat(cfg.lists.map(function (l) {
			return [l.id, l.nome + ' (' + l.id + ')'];
		}));

		var header = h('div', {class: 'hf-b-card-head'},
			h('span', {class: 'hf-b-card-num', text: '#' + (i + 1)}),
			h('strong', {text: field.rotulo || '(sem rótulo)'}),
			h('span', {class: 'hf-b-muted', text: ' · ' + (cfg.field_types[type] || type) + (field.id ? ' · ' + field.id : '')}),
			h('span', {class: 'hf-b-spacer'}),
			button('↑', function () { move(state.campos, i, -1); render(); }, 'btn-alt hf-b-icon', 'Subir'),
			button('↓', function () { move(state.campos, i, 1); render(); }, 'btn-alt hf-b-icon', 'Descer'),
			button('Duplicar', function () {
				var copy = JSON.parse(JSON.stringify(field));
				copy.id = (copy.id || 'campo') + '_2';
				state.campos.splice(i + 1, 0, copy);
				render();
			}, 'btn-alt'),
			button('Remover', function () {
				if (window.confirm('Remover o campo "' + (field.rotulo || field.id) + '"?')) {
					state.campos.splice(i, 1);
					render();
				}
			}, 'btn-alt hf-b-danger')
		);

		var body = h('div', {class: 'hf-b-card-body'},
			h('div', {class: 'hf-b-row'},
				prop('ID', textInput(field.id, function (v) { field.id = v; }, {placeholder: 'ex.: site'}),
					'a-z, 0-9 e _. Usado em padrões: {id}'),
				prop('Rótulo', textInput(field.rotulo, function (v) { field.rotulo = v; })),
				prop('Tipo', select(type, typeOpts, function (v) {
					field.tipo = v;

					if (v === 'zbx_host' && !field.mapeamento.length) {
						field.mapeamento.push({alvo: 'hostid', padrao: ''});
					}

					if (v === 'tag_value' && !field.tag) {
						field.tag = '';
					}

					render();
				}))
			),
			h('div', {class: 'hf-b-row'},
				prop('', checkbox(field.obrigatorio, function (v) { field.obrigatorio = v; }, 'Obrigatório')),
				prop('Ajuda', textInput(field.ajuda, function (v) { field.ajuda = v; }), null, 'hf-b-grow'),
				(type !== 'zbx_host')
					? prop('Valor padrão', textInput(field.valor_padrao, function (v) { field.valor_padrao = v; }))
					: null
			),
			isText ? h('div', {class: 'hf-b-row'},
				prop('Regex (opcional)', textInput(field.regex, function (v) { field.regex = v; },
					{placeholder: '^SW-[A-Z0-9_-]+$', class: 'hf-mono'}), 'Sem delimitadores. Aplicada no servidor.', 'hf-b-grow')
			) : null,
			(type === 'tag_value') ? h('div', {class: 'hf-b-row'},
				prop('Nome da tag', textInput(field.tag, function (v) { field.tag = v; }, {placeholder: 'ex.: ambiente'}),
					'Sem mapeamento explícito, o valor vai para tag:<nome>.')
			) : null,
			isOption ? h('div', {class: 'hf-b-row'},
				prop('Lista compartilhada', select(field.lista || '', listOpts, function (v) {
					field.lista = v;
					render();
				}), 'Listas permitem usar atributos: {' + (field.id || 'campo') + '.atributo}'),
				!field.lista ? prop('Opções', textArea(optionsToText(field.opcoes), function (v) {
					field.opcoes = textToOptions(v);
				}, {class: 'hf-mono', rows: 5, placeholder: 'VALOR | Rótulo'}), 'Uma por linha: VALOR | Rótulo', 'hf-b-grow') : null
			) : null,
			(type === 'zbx_hostgroup') ? h('div', {class: 'hf-b-row'},
				prop('Prefixo dos grupos', textInput(field.prefixo, function (v) { field.prefixo = v; },
					{placeholder: 'ex.: Sites/'}), 'Só grupos com este prefixo, que o usuário enxerga.', 'hf-b-grow')
			) : null,
			isAllowed ? h('div', {class: 'hf-b-row'},
				prop('Permitidos', textArea((field.permitidos || []).join('\n'), function (v) {
					field.permitidos = linesToList(v);
				}, {class: 'hf-mono', rows: 4}),
				'Um nome por linha. Recomendado: usuários comuns podem não enxergar templates/proxies.'
					+ (type === 'zbx_proxy' || type === 'zbx_proxy_group' ? ' Vazio = todos.' : ''), 'hf-b-grow'),
				(type === 'zbx_template') ? prop('ou grupo de templates', textInput(field.grupo_templates, function (v) {
					field.grupo_templates = v;
				}, {placeholder: 'Templates/Network devices'}), 'Usado se "Permitidos" estiver vazio.') : null
			) : null,
			isMultiCap ? h('div', {class: 'hf-b-row'},
				prop('', checkbox(field.multiplo, function (v) { field.multiplo = v; }, 'Permitir vários valores'))
			) : null,
			h('div', {class: 'hf-b-row'},
				prop('Exibir quando', conditionEditor(field, field.id), null, 'hf-b-grow')
			),
			mappingTable(field)
		);

		return h('div', {class: 'hf-b-card'}, header, body);
	}

	function mappingTable(field) {
		var rows = field.mapeamento.map(function (map, j) {
			return h('tr', null,
				h('td', null, targetEditor(map)),
				h('td', null, textInput(map.padrao, function (v) { map.padrao = v; },
					{placeholder: 'vazio = o próprio valor', class: 'hf-mono'})),
				h('td', null, modeEditor(map)),
				h('td', null, button('✕', function () {
					field.mapeamento.splice(j, 1);
					render();
				}, 'btn-alt hf-b-icon', 'Remover mapeamento'))
			);
		});

		return h('div', {class: 'hf-b-maps'},
			h('div', {class: 'hf-b-label', text: 'Mapeamento: em que atributo(s) do host este valor vira'}),
			h('table', {class: 'hf-b-table'},
				h('thead', null, h('tr', null,
					h('th', {text: 'Alvo'}), h('th', {text: 'Padrão (opcional)'}), h('th', {text: 'Modo'}), h('th')
				)),
				h('tbody', null, rows.length ? rows : h('tr', null, h('td', {colspan: 4, class: 'hf-b-muted',
					text: 'Sem mapeamento: o valor só aparece no resumo da solicitação.'})))
			),
			button('+ mapeamento', function () {
				field.mapeamento.push({alvo: '', padrao: ''});
				render();
			})
		);
	}

	/* ------------------------------------------------------------ valores fixos */

	function fixedSection() {
		state.valores_fixos = state.valores_fixos || [];

		var rows = state.valores_fixos.map(function (fixed, j) {
			return h('tr', null,
				h('td', null, targetEditor(fixed)),
				h('td', null, textInput(fixed.valor, function (v) { fixed.valor = v; },
					{placeholder: 'ex.: producao ou {site}', class: 'hf-mono'})),
				h('td', null, modeEditor(fixed)),
				h('td', null, conditionEditor(fixed, null)),
				h('td', null, button('✕', function () {
					state.valores_fixos.splice(j, 1);
					render();
				}, 'btn-alt hf-b-icon', 'Remover'))
			);
		});

		return h('section', {class: 'hf-b-section'},
			h('h4', {text: 'Valores fixos'}),
			h('div', {class: 'hf-b-hint', text: 'Aplicados sem perguntar ao usuário (ex.: proxy, template ou tag '
				+ 'sempre iguais para este formulário). Aceitam {campo} e condição.'}),
			h('table', {class: 'hf-b-table'},
				h('thead', null, h('tr', null,
					h('th', {text: 'Alvo'}), h('th', {text: 'Valor'}), h('th', {text: 'Modo'}),
					h('th', {text: 'Aplicar quando'}), h('th')
				)),
				h('tbody', null, rows.length ? rows : h('tr', null, h('td', {colspan: 5, class: 'hf-b-muted',
					text: 'Nenhum valor fixo.'})))
			),
			button('+ valor fixo', function () {
				state.valores_fixos.push({alvo: '', valor: ''});
				render();
			})
		);
	}

	/* ------------------------------------------------------------ tela */

	function ensureHostField() {
		if (state.tipo === 'create') {
			return;
		}

		var has = state.campos.some(function (f) {
			return f.tipo === 'zbx_host';
		});

		if (!has) {
			state.campos.unshift({
				id: 'host', rotulo: 'Host', tipo: 'zbx_host', obrigatorio: true, ajuda: '',
				quando: null, mapeamento: [{alvo: 'hostid', padrao: ''}]
			});
		}
	}

	function metaSection() {
		return h('section', {class: 'hf-b-section'},
			h('div', {class: 'hf-b-row'},
				prop('ID do formulário', textInput(state.id, function (v) { state.id = v; },
					{placeholder: 'novo-switch'}), 'Minúsculas, números, - e _'),
				prop('Nome', textInput(state.nome, function (v) { state.nome = v; }), null, 'hf-b-grow'),
				prop('Tipo', select(state.tipo, entries(cfg.form_types), function (v) {
					state.tipo = v;
					ensureHostField();
					render();
				}))
			),
			h('div', {class: 'hf-b-row'},
				prop('Descrição', textInput(state.descricao, function (v) { state.descricao = v; }), null, 'hf-b-grow'),
				prop('Equipe responsável', textInput(state.equipe_responsavel, function (v) {
					state.equipe_responsavel = v;
				}, {placeholder: 'ex.: Equipe de redes'}), 'Destino do chamado na integração com o sistema de chamados.'),
				prop('', checkbox(state.ativo !== false, function (v) { state.ativo = v; }, 'Ativo (visível aos usuários)'))
			)
		);
	}

	function helpSection() {
		return h('details', {class: 'hf-b-help'},
			h('summary', {text: 'Como funcionam padrões e mapeamentos'}),
			h('ul', null,
				h('li', {text: 'Padrão vazio: o valor do campo vai direto para o alvo.'}),
				h('li', {text: 'Padrão com {campo}: monta o valor com outros campos. Ex.: Sites/{site.regiao}/{site}/{funcao}.'}),
				h('li', {text: '{campo.atributo} lê um atributo do item escolhido numa lista compartilhada.'}),
				h('li', {text: 'Se algum placeholder ficar vazio, aquele mapeamento é ignorado (nunca gera "A//B").'}),
				h('li', {text: 'Um campo pode ter vários mapeamentos: "Site" pode gerar o grupo e a tag site.'}),
				h('li', {text: 'Grupos: "substituir grupos com prefixo" troca só os grupos daquele ramo (movimentação).'}),
				h('li', {text: 'Em alteração, campos deixados vazios não mudam nada no host.'})
			)
		);
	}

	function render() {
		root.textContent = '';

		var tabs = h('div', {class: 'hf-b-tabs'},
			button('Construtor visual', function () { switchTab('visual'); },
				tab === 'visual' ? 'btn hf-b-tab-on' : 'btn-alt'),
			button('JSON', function () { switchTab('json'); }, tab === 'json' ? 'btn hf-b-tab-on' : 'btn-alt')
		);

		root.appendChild(tabs);

		if (tab === 'json') {
			root.appendChild(h('div', {class: 'hf-b-hint', text: 'Edite ou cole uma definição. Ela passa pela mesma '
				+ 'validação do construtor ao salvar.'}));
			root.appendChild(h('textarea', {id: 'hf-b-json', class: 'hf-mono hf-b-json', value: jsonText, spellcheck: 'false',
				on: {input: function (e) { jsonText = e.target.value; }}}));

			return;
		}

		root.appendChild(metaSection());

		var fields = h('section', {class: 'hf-b-section'}, h('h4', {text: 'Campos'}));

		state.campos.forEach(function (field, i) {
			fields.appendChild(fieldCard(field, i));
		});

		fields.appendChild(button('+ campo', function () {
			state.campos.push({id: '', rotulo: '', tipo: 'text', obrigatorio: false, ajuda: '', valor_padrao: '',
				regex: '', quando: null, mapeamento: []});
			render();
		}));

		root.appendChild(fields);
		root.appendChild(fixedSection());
		root.appendChild(helpSection());
	}

	function switchTab(next) {
		if (next === tab) {
			return;
		}

		if (next === 'json') {
			jsonText = JSON.stringify(state, null, 2);
			tab = 'json';
			render();

			return;
		}

		try {
			loadState(JSON.parse(jsonText));
			tab = 'visual';
			render();
		}
		catch (e) {
			window.alert('JSON inválido: ' + e.message);
		}
	}

	function loadState(def) {
		if (!def || typeof def !== 'object' || Array.isArray(def)) {
			throw new Error('a definição deve ser um objeto.');
		}

		def.campos = Array.isArray(def.campos) ? def.campos : [];
		def.valores_fixos = Array.isArray(def.valores_fixos) ? def.valores_fixos : [];
		state = def;
	}

	function init() {
		root = document.getElementById('hf-builder');

		if (!root) {
			return;
		}

		cfg = JSON.parse(root.getAttribute('data-config'));
		loadState(JSON.parse(root.getAttribute('data-definition')));

		var raw = root.getAttribute('data-raw');

		if (raw) {
			tab = 'json';
			jsonText = raw;
		}

		// Na aba JSON envia o texto como está: se for inválido, o servidor devolve o erro e preserva o texto.
		document.getElementById('hf-builder-form').addEventListener('submit', function () {
			document.getElementById('hf-definition').value = (tab === 'json') ? jsonText : JSON.stringify(state);
		});

		render();
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', init);
	}
	else {
		init();
	}
})();
HOSTFLOW_EOF

# ---- assets/js/hostflow.common.js
cat > "$MOD/assets/js/hostflow.common.js" <<'HOSTFLOW_EOF'
/* HostFlow: comportamento comum. */
(function () {
	'use strict';

	document.addEventListener('click', function (e) {
		var btn = e.target.closest ? e.target.closest('.js-hf-confirm') : null;

		if (btn && !window.confirm(btn.getAttribute('data-confirm') || 'Confirmar?')) {
			e.preventDefault();
			e.stopPropagation();
		}
	}, true);
})();
HOSTFLOW_EOF

# ---- assets/js/hostflow.request.js
cat > "$MOD/assets/js/hostflow.request.js" <<'HOSTFLOW_EOF'
/* HostFlow: formulário de solicitação (campos condicionais e escolha do host alvo). */
(function () {
	'use strict';

	function init() {
		var form = document.getElementById('hf-request-form');

		if (!form) {
			return;
		}

		initConditions(form);
		initHostReload(form);
	}

	/* Valores atuais de um campo, como lista de strings. */
	function valuesOf(form, id) {
		var single = 'campos[' + id + ']';
		var multi = single + '[]';
		var result = [];

		var checkbox = form.querySelector('input[type="checkbox"][name="' + cssEscape(single) + '"]');

		if (checkbox) {
			return [checkbox.checked ? '1' : '0'];
		}

		form.querySelectorAll('[name="' + cssEscape(single) + '"], [name="' + cssEscape(multi) + '"]')
			.forEach(function (el) {
				var zselect = el.closest('z-select');

				if (zselect && el !== zselect) {
					return; // input interno do z-select; o valor vem do próprio z-select.
				}

				if (el.type === 'checkbox') {
					if (el.checked) {
						result.push(el.value);
					}
				}
				else if (el.value !== undefined && el.value !== null) {
					result.push(String(el.value));
				}
			});

		return result;
	}

	function initConditions(form) {
		var conditional = form.querySelectorAll('[data-hf-when-field]');

		if (!conditional.length) {
			return;
		}

		var rules = {};

		conditional.forEach(function (el) {
			rules[el.getAttribute('data-hf-field')] = {
				field: el.getAttribute('data-hf-when-field'),
				value: el.getAttribute('data-hf-when-value')
			};
		});

		function isVisible(id, seen) {
			var rule = rules[id];

			if (!rule) {
				return true;
			}

			if (seen[id]) {
				return false; // ciclo: o servidor já impede, mas por segurança.
			}

			seen[id] = true;

			return isVisible(rule.field, seen) && valuesOf(form, rule.field).indexOf(rule.value) !== -1;
		}

		function apply() {
			conditional.forEach(function (el) {
				el.classList.toggle('hf-hidden', !isVisible(el.getAttribute('data-hf-field'), {}));
			});
		}

		form.addEventListener('change', apply);
		form.addEventListener('input', apply);
		apply();
	}

	function initHostReload(form) {
		var ms = form.querySelector('[data-hf-reload]');

		if (!ms || typeof jQuery === 'undefined') {
			return;
		}

		var url = ms.getAttribute('data-hf-reload');
		var current = ms.getAttribute('data-hf-current') || '';

		jQuery(ms).on('change', function () {
			var data = jQuery(ms).multiSelect('getData') || [];
			var hostid = data.length ? String(data[0].id) : '';

			if (hostid === current) {
				return;
			}

			current = hostid;
			form.classList.add('hf-loading');
			window.location.href = hostid !== '' ? url + '&hostid=' + encodeURIComponent(hostid) : url;
		});
	}

	function cssEscape(value) {
		return (window.CSS && CSS.escape) ? CSS.escape(value) : value.replace(/["\\]/g, '\\$&');
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', init);
	}
	else {
		init();
	}
})();
HOSTFLOW_EOF

# ---- lib/Config.php
cat > "$MOD/lib/Config.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib;

/**
 * Configuração lida de um arquivo PHP fora do webroot.
 * Exemplo em config/hostflow.conf.php.example.
 */
final class Config {

	public const FILE = '/etc/zabbix/hostflow.conf.php';

	private static ?array $config = null;

	public static function get(string $key, $default = null) {
		if (self::$config === null) {
			self::$config = [
				'data_dir' => '/var/lib/zabbix-hostflow',
				// Classe que implementa Lib\Submit\SubmitHandler. null = nada é enviado (padrão do MVP).
				'submit_handler' => null
			];

			if (is_file(self::FILE) && is_readable(self::FILE)) {
				$file_config = include self::FILE;

				if (is_array($file_config)) {
					self::$config = array_replace(self::$config, $file_config);
				}
			}
		}

		return array_key_exists($key, self::$config) ? self::$config[$key] : $default;
	}

	public static function dataDir(): string {
		return rtrim((string) self::get('data_dir'), '/');
	}
}
HOSTFLOW_EOF

# ---- lib/Ui.php
cat > "$MOD/lib/Ui.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib;

use CDiv;
use CList;
use CTag;

/**
 * Pequenos componentes de interface reutilizados pelas views. Todo texto passa por CTag, que escapa HTML.
 */
final class Ui {

	public static function errorBox(string $title, array $errors): CDiv {
		$list = new CList();

		foreach ($errors as $error) {
			$list->addItem((string) $error);
		}

		return (new CDiv([new CTag('strong', true, $title), $list]))->addClass('hf-alert hf-alert-bad');
	}

	public static function notice(string $text, string $kind = 'info'): CDiv {
		return (new CDiv($text))->addClass('hf-alert hf-alert-'.$kind);
	}
}
HOSTFLOW_EOF

# ---- lib/form/FormSchema.php
cat > "$MOD/lib/form/FormSchema.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

use API;
use Modules\HostFlow\Lib\Storage\JsonStore;

/**
 * Define e valida a ESTRUTURA de um formulário (o que o admin monta no construtor).
 * O formato é o mesmo gravado em disco, então construtor visual e edição de JSON passam pela mesma validação.
 */
final class FormSchema {

	public const SCHEMA_VERSION = 1;

	public const FORM_TYPES = [
		'create' => 'Criação de host',
		'update' => 'Alteração de host',
		'move' => 'Movimentação de host',
		'delete' => 'Desativação/exclusão de host'
	];

	public const FIELD_TYPES = [
		'text' => 'Texto',
		'textarea' => 'Texto longo',
		'ip' => 'Endereço IP',
		'dns' => 'Nome DNS / hostname',
		'checkbox' => 'Caixa de seleção',
		'select' => 'Lista (um valor)',
		'multiselect' => 'Lista (vários valores)',
		'tag_value' => 'Valor de tag (lista fechada)',
		'zbx_hostgroup' => 'Zabbix: grupo de hosts',
		'zbx_template' => 'Zabbix: template',
		'zbx_proxy' => 'Zabbix: proxy',
		'zbx_proxy_group' => 'Zabbix: grupo de proxies',
		'zbx_host' => 'Zabbix: host existente'
	];

	/** Tipos que aceitam lista de opções (estática ou lista compartilhada). */
	public const OPTION_TYPES = ['select', 'multiselect', 'tag_value'];

	/** Tipos de texto livre, que aceitam regex. */
	public const TEXT_TYPES = ['text', 'textarea', 'ip', 'dns'];

	/** Tipos que aceitam "permitidos" (lista fechada de nomes de objetos do Zabbix). */
	public const ALLOWED_TYPES = ['zbx_template', 'zbx_proxy', 'zbx_proxy_group'];

	/** Tipos que podem ter "multiplo". */
	public const MULTI_CAPABLE = ['zbx_hostgroup', 'zbx_template'];

	/** Alvos fixos de mapeamento. Prefixados: tag:<NOME>, macro:{$NOME}, inventory.<campo>. */
	public const TARGETS = [
		'host.host' => 'Host: nome técnico',
		'host.name' => 'Host: nome visível',
		'host.description' => 'Host: descrição',
		'host.status' => 'Host: status (0 ativo, 1 desativado)',
		'interface.type' => 'Interface: tipo (agent, snmp, ipmi, jmx)',
		'interface.ip' => 'Interface: IP',
		'interface.dns' => 'Interface: DNS',
		'interface.port' => 'Interface: porta',
		'interface.useip' => 'Interface: conectar por (1 IP, 0 DNS)',
		'interface.snmp.version' => 'SNMP: versão (1, 2, 3)',
		'interface.snmp.community' => 'SNMP: community',
		'interface.snmp.bulk' => 'SNMP: bulk (0, 1)',
		'interface.snmp.securityname' => 'SNMPv3: security name',
		'interface.snmp.securitylevel' => 'SNMPv3: security level (0, 1, 2)',
		'interface.snmp.authprotocol' => 'SNMPv3: auth protocol',
		'interface.snmp.authpassphrase' => 'SNMPv3: auth passphrase',
		'interface.snmp.privprotocol' => 'SNMPv3: priv protocol',
		'interface.snmp.privpassphrase' => 'SNMPv3: priv passphrase',
		'interface.snmp.contextname' => 'SNMPv3: context name',
		'groups[]' => 'Grupos de hosts',
		'templates[]' => 'Templates',
		'proxy' => 'Monitorado por proxy',
		'proxy_group' => 'Monitorado por grupo de proxies',
		'hostid' => 'Host alvo (somente campo Zabbix: host existente)',
		'operacao' => 'Operação de exclusão (desativar, excluir)'
	];

	public const TARGET_PREFIXES = [
		'tag:' => 'Tag',
		'macro:' => 'Macro de usuário',
		'inventory.' => 'Inventário'
	];

	public const GROUP_MODES = ['adicionar', 'substituir_prefixo'];
	public const TEMPLATE_MODES = ['vincular', 'desvincular'];

	public const INTERFACE_TYPES = ['agent', 'snmp', 'ipmi', 'jmx'];
	public const OPERATIONS = ['desativar', 'excluir'];

	public const FIELD_ID_PATTERN = '/^[a-z][a-z0-9_]{0,31}$/';
	public const PLACEHOLDER_PATTERN = '/\{([a-z][a-z0-9_]{0,31})(?:\.([a-zA-Z0-9_]{1,64}))?\}/';
	public const MACRO_PATTERN = '/^\{\$[A-Z0-9_.]+\}$/';

	private array $errors = [];

	/**
	 * Valida e normaliza uma definição de formulário.
	 *
	 * @param array $def          Definição vinda do construtor ou do JSON.
	 * @param array $lists        Listas compartilhadas existentes, indexadas por id.
	 * @param bool  $check_zabbix Confere se templates, proxies e grupos fixos existem (com a sessão atual).
	 *
	 * @return array|null  Definição normalizada ou null se houver erros (ver getErrors()).
	 */
	public function validate(array $def, array $lists, bool $check_zabbix = true): ?array {
		$this->errors = [];

		$form = [
			'schema_version' => self::SCHEMA_VERSION,
			'id' => self::str($def, 'id'),
			'versao' => max(1, (int) ($def['versao'] ?? 1)),
			'nome' => self::str($def, 'nome'),
			'descricao' => self::str($def, 'descricao'),
			'tipo' => self::str($def, 'tipo'),
			'ativo' => self::bool($def, 'ativo', true),
			'equipe_responsavel' => self::str($def, 'equipe_responsavel'),
			'campos' => [],
			'valores_fixos' => []
		];

		if (!JsonStore::isValidId($form['id'])) {
			$this->error('ID do formulário', 'use de 1 a 64 caracteres: letras minúsculas, números, "-" e "_".');
		}

		if ($form['nome'] === '') {
			$this->error('Nome', 'obrigatório.');
		}

		if (!array_key_exists($form['tipo'], self::FORM_TYPES)) {
			$this->error('Tipo', 'deve ser create, update, move ou delete.');
		}

		$raw_fields = (isset($def['campos']) && is_array($def['campos'])) ? array_values($def['campos']) : [];

		if (!$raw_fields) {
			$this->error('Campos', 'o formulário precisa de pelo menos um campo.');
		}

		$field_ids = [];

		foreach ($raw_fields as $i => $raw) {
			$id = is_array($raw) ? self::str($raw, 'id') : '';

			if ($id !== '') {
				if (in_array($id, $field_ids, true)) {
					$this->error(sprintf('Campo #%d', $i + 1), sprintf('ID "%s" repetido.', $id));
				}

				$field_ids[] = $id;
			}
		}

		foreach ($raw_fields as $i => $raw) {
			$field = $this->validateField(is_array($raw) ? $raw : [], $i, $field_ids, $lists, $form['tipo']);

			if ($field !== null) {
				$form['campos'][] = $field;
			}
		}

		$raw_fixed = (isset($def['valores_fixos']) && is_array($def['valores_fixos']))
			? array_values($def['valores_fixos'])
			: [];

		foreach ($raw_fixed as $i => $raw) {
			$fixed = $this->validateFixed(is_array($raw) ? $raw : [], $i, $field_ids);

			if ($fixed !== null) {
				$form['valores_fixos'][] = $fixed;
			}
		}

		$this->validateTypeRules($form);

		if ($check_zabbix && !$this->errors) {
			$this->validateZabbixObjects($form);
		}

		return $this->errors ? null : $form;
	}

	public function getErrors(): array {
		return $this->errors;
	}

	private function validateField(array $raw, int $i, array $field_ids, array $lists, string $form_type): ?array {
		$label = sprintf('Campo #%d', $i + 1);

		$field = [
			'id' => self::str($raw, 'id'),
			'rotulo' => self::str($raw, 'rotulo'),
			'tipo' => self::str($raw, 'tipo'),
			'obrigatorio' => self::bool($raw, 'obrigatorio', false),
			'ajuda' => self::str($raw, 'ajuda'),
			'valor_padrao' => self::str($raw, 'valor_padrao')
		];

		if ($field['rotulo'] !== '') {
			$label .= ' ('.$field['rotulo'].')';
		}

		if (!preg_match(self::FIELD_ID_PATTERN, $field['id'])) {
			$this->error($label, 'ID deve começar com letra minúscula e ter só a-z, 0-9 e "_" (máx. 32).');
		}

		if ($field['rotulo'] === '') {
			$this->error($label, 'rótulo obrigatório.');
		}

		if (!array_key_exists($field['tipo'], self::FIELD_TYPES)) {
			$this->error($label, 'tipo de campo inválido.');

			return null;
		}

		$type = $field['tipo'];

		if (in_array($type, self::TEXT_TYPES, true)) {
			$field['regex'] = self::str($raw, 'regex');

			if ($field['regex'] !== '' && !self::isValidRegex($field['regex'])) {
				$this->error($label, 'regex inválida.');
			}
		}

		if (in_array($type, self::OPTION_TYPES, true)) {
			$field['lista'] = self::str($raw, 'lista');
			$field['opcoes'] = self::normalizeOptions($raw['opcoes'] ?? []);

			if ($field['lista'] !== '') {
				if (!array_key_exists($field['lista'], $lists)) {
					$this->error($label, sprintf('lista "%s" não existe.', $field['lista']));
				}

				$field['opcoes'] = [];
			}
			elseif (!$field['opcoes']) {
				$this->error($label, 'informe as opções ou escolha uma lista compartilhada.');
			}
		}

		if ($type === 'tag_value') {
			$field['tag'] = self::str($raw, 'tag');

			if ($field['tag'] === '') {
				$this->error($label, 'informe o nome da tag.');
			}
		}

		if ($type === 'zbx_hostgroup') {
			$field['prefixo'] = self::str($raw, 'prefixo');
		}

		if (in_array($type, self::MULTI_CAPABLE, true)) {
			$field['multiplo'] = self::bool($raw, 'multiplo', false);
		}

		if (in_array($type, self::ALLOWED_TYPES, true)) {
			$field['permitidos'] = self::normalizeStringList($raw['permitidos'] ?? []);
		}

		if ($type === 'zbx_template') {
			$field['grupo_templates'] = self::str($raw, 'grupo_templates');
		}

		$field['quando'] = $this->validateCondition($raw['quando'] ?? null, $label, $field_ids, $field['id']);

		$field['mapeamento'] = [];
		$raw_maps = (isset($raw['mapeamento']) && is_array($raw['mapeamento'])) ? array_values($raw['mapeamento']) : [];

		foreach ($raw_maps as $j => $raw_map) {
			$map = $this->validateMapping(is_array($raw_map) ? $raw_map : [], sprintf('%s, mapeamento #%d', $label, $j + 1),
				$field_ids
			);

			if ($map === null) {
				continue;
			}

			if ($map['alvo'] === 'hostid' && $type !== 'zbx_host') {
				$this->error($label, 'só um campo "Zabbix: host existente" pode mapear para "hostid".');
			}

			if ($map['alvo'] === 'operacao' && $form_type !== 'delete') {
				$this->error($label, '"operacao" só existe em formulários de exclusão.');
			}

			$field['mapeamento'][] = $map;
		}

		if ($type === 'tag_value' && !$field['mapeamento'] && $field['tag'] !== '') {
			$field['mapeamento'][] = ['alvo' => 'tag:'.$field['tag'], 'padrao' => ''];
		}

		return $field;
	}

	private function validateFixed(array $raw, int $i, array $field_ids): ?array {
		$label = sprintf('Valor fixo #%d', $i + 1);
		$map = $this->validateMapping($raw, $label, $field_ids, true);

		if ($map === null) {
			return null;
		}

		if ($map['alvo'] === 'hostid') {
			$this->error($label, '"hostid" não pode ser valor fixo.');
		}

		$map['quando'] = $this->validateCondition($raw['quando'] ?? null, $label, $field_ids, null);

		return $map;
	}

	private function validateMapping(array $raw, string $label, array $field_ids, bool $is_fixed = false): ?array {
		$target = self::str($raw, 'alvo');

		if ($target === '') {
			$this->error($label, 'alvo obrigatório.');

			return null;
		}

		if (!self::isValidTarget($target, $reason)) {
			$this->error($label, $reason);

			return null;
		}

		$map = ['alvo' => $target];

		if ($is_fixed) {
			$map['valor'] = self::str($raw, 'valor');
			$template = $map['valor'];

			if ($map['valor'] === '') {
				$this->error($label, 'valor obrigatório.');
			}
		}
		else {
			$map['padrao'] = self::str($raw, 'padrao');
			$template = $map['padrao'];
		}

		if (preg_match_all(self::PLACEHOLDER_PATTERN, $template, $m)) {
			foreach ($m[1] as $ref) {
				if (!in_array($ref, $field_ids, true)) {
					$this->error($label, sprintf('o padrão referencia o campo "{%s}", que não existe.', $ref));
				}
			}
		}

		if ($target === 'groups[]') {
			$map['modo'] = self::str($raw, 'modo') ?: 'adicionar';

			if (!in_array($map['modo'], self::GROUP_MODES, true)) {
				$this->error($label, 'modo de grupo inválido.');
			}

			if ($map['modo'] === 'substituir_prefixo') {
				$map['prefixo'] = self::str($raw, 'prefixo');

				if ($map['prefixo'] === '') {
					$this->error($label, 'o modo "substituir_prefixo" exige um prefixo.');
				}
			}
		}
		elseif ($target === 'templates[]') {
			$map['modo'] = self::str($raw, 'modo') ?: 'vincular';

			if (!in_array($map['modo'], self::TEMPLATE_MODES, true)) {
				$this->error($label, 'modo de template inválido.');
			}
		}

		if ($is_fixed && !preg_match(self::PLACEHOLDER_PATTERN, $map['valor'])) {
			$this->validateLiteralValue($target, $map['valor'], $label);
		}

		return $map;
	}

	private function validateLiteralValue(string $target, string $value, string $label): void {
		$enums = [
			'interface.type' => self::INTERFACE_TYPES,
			'host.status' => ['0', '1'],
			'interface.useip' => ['0', '1'],
			'interface.snmp.version' => ['1', '2', '3'],
			'interface.snmp.bulk' => ['0', '1'],
			'interface.snmp.securitylevel' => ['0', '1', '2'],
			'operacao' => self::OPERATIONS
		];

		if (array_key_exists($target, $enums) && !in_array($value, $enums[$target], true)) {
			$this->error($label, sprintf('valor de "%s" deve ser: %s.', $target, implode(', ', $enums[$target])));
		}

		if ($target === 'interface.ip' && filter_var($value, FILTER_VALIDATE_IP) === false) {
			$this->error($label, 'IP inválido.');
		}
	}

	private function validateCondition($raw, string $label, array $field_ids, ?string $self_id): ?array {
		if (!is_array($raw) || self::str($raw, 'campo') === '') {
			return null;
		}

		$cond = ['campo' => self::str($raw, 'campo'), 'igual' => self::str($raw, 'igual')];

		if (!in_array($cond['campo'], $field_ids, true) || $cond['campo'] === $self_id) {
			$this->error($label, sprintf('condição "exibir quando" referencia campo inválido "%s".', $cond['campo']));
		}

		return $cond;
	}

	private function validateTypeRules(array $form): void {
		$targets = [];

		foreach ($form['campos'] as $field) {
			foreach ($field['mapeamento'] as $map) {
				$targets[] = $map['alvo'];
			}
		}

		foreach ($form['valores_fixos'] as $fixed) {
			$targets[] = $fixed['alvo'];
		}

		$host_fields = array_filter($form['campos'], static function (array $f): bool {
			return $f['tipo'] === 'zbx_host';
		});

		$hostid_fields = array_filter($host_fields, static function (array $f): bool {
			return in_array('hostid', array_column($f['mapeamento'], 'alvo'), true);
		});

		if ($form['tipo'] === 'create') {
			if ($hostid_fields) {
				$this->error('Tipo', 'formulário de criação não pode ter campo mapeado para "hostid".');
			}

			if (!in_array('host.host', $targets, true)) {
				$this->error('Mapeamento', 'formulário de criação precisa mapear "host.host".');
			}

			if (!in_array('groups[]', $targets, true)) {
				$this->error('Mapeamento', 'formulário de criação precisa mapear ao menos um "groups[]".');
			}
		}
		elseif (array_key_exists($form['tipo'], self::FORM_TYPES)) {
			if (count($hostid_fields) !== 1) {
				$this->error('Host alvo', 'este tipo precisa de exatamente um campo "Zabbix: host existente" mapeado para "hostid".');
			}
			else {
				$host_field = reset($hostid_fields);

				if (!$host_field['obrigatorio'] || $host_field['quando'] !== null) {
					$this->error('Host alvo', 'o campo do host alvo deve ser obrigatório e sempre visível.');
				}
			}
		}

		if ($form['tipo'] === 'move' && !in_array('groups[]', $targets, true)) {
			$this->error('Mapeamento', 'formulário de movimentação precisa mapear "groups[]".');
		}
	}

	/**
	 * Confere, com a sessão de quem salva (Super admin), que objetos citados literalmente existem.
	 */
	private function validateZabbixObjects(array $form): void {
		$names = ['template' => [], 'proxy' => [], 'proxy_group' => [], 'group' => []];

		foreach ($form['campos'] as $field) {
			$allowed = $field['permitidos'] ?? [];

			if ($field['tipo'] === 'zbx_template') {
				$names['template'] = array_merge($names['template'], $allowed);
			}
			elseif ($field['tipo'] === 'zbx_proxy') {
				$names['proxy'] = array_merge($names['proxy'], $allowed);
			}
			elseif ($field['tipo'] === 'zbx_proxy_group') {
				$names['proxy_group'] = array_merge($names['proxy_group'], $allowed);
			}
		}

		foreach ($form['valores_fixos'] as $fixed) {
			if (preg_match(self::PLACEHOLDER_PATTERN, $fixed['valor'])) {
				continue;
			}

			$kind = [
				'templates[]' => 'template',
				'proxy' => 'proxy',
				'proxy_group' => 'proxy_group',
				'groups[]' => 'group'
			][$fixed['alvo']] ?? null;

			if ($kind !== null) {
				$names[$kind][] = $fixed['valor'];
			}
		}

		$missing = [
			'template' => ZabbixLookup::missingTemplates(array_unique($names['template'])),
			'proxy' => ZabbixLookup::missingProxies(array_unique($names['proxy'])),
			'proxy_group' => ZabbixLookup::missingProxyGroups(array_unique($names['proxy_group'])),
			'group' => ZabbixLookup::missingHostGroups(array_unique($names['group']))
		];

		$labels = [
			'template' => 'Templates não encontrados',
			'proxy' => 'Proxies não encontrados',
			'proxy_group' => 'Grupos de proxies não encontrados',
			'group' => 'Grupos de hosts não encontrados'
		];

		foreach ($missing as $kind => $list) {
			if ($list) {
				$this->error($labels[$kind], implode(', ', $list));
			}
		}
	}

	public static function isValidTarget(string $target, ?string &$reason = null): bool {
		$reason = null;

		if (array_key_exists($target, self::TARGETS)) {
			return true;
		}

		if (strpos($target, 'tag:') === 0) {
			$name = substr($target, 4);

			if ($name === '' || mb_strlen($name) > 255) {
				$reason = 'nome de tag inválido.';

				return false;
			}

			return true;
		}

		if (strpos($target, 'macro:') === 0) {
			if (!preg_match(self::MACRO_PATTERN, substr($target, 6))) {
				$reason = 'macro deve ter o formato {$NOME} (A-Z, 0-9, "_" e ".").';

				return false;
			}

			return true;
		}

		if (strpos($target, 'inventory.') === 0) {
			$name = substr($target, 10);
			$fields = self::inventoryFields();

			if ($fields !== null ? !in_array($name, $fields, true) : !preg_match('/^[a-z_0-9]+$/', $name)) {
				$reason = sprintf('campo de inventário "%s" não existe.', $name);

				return false;
			}

			return true;
		}

		$reason = sprintf('alvo "%s" desconhecido.', $target);

		return false;
	}

	public static function inventoryFields(): ?array {
		if (!function_exists('getHostInventories')) {
			return null;
		}

		return array_values(array_column(getHostInventories(), 'db_field'));
	}

	public static function isValidRegex(string $regex): bool {
		return @preg_match(self::wrapRegex($regex), '') !== false;
	}

	public static function wrapRegex(string $regex): string {
		return '/'.str_replace('/', '\/', $regex).'/u';
	}

	/**
	 * Aceita [{valor, rotulo}] ou ["valor", ...].
	 */
	public static function normalizeOptions($raw): array {
		if (!is_array($raw)) {
			return [];
		}

		$options = [];
		$seen = [];

		foreach ($raw as $item) {
			if (is_array($item)) {
				$value = trim((string) ($item['valor'] ?? ''));
				$label = trim((string) ($item['rotulo'] ?? ''));
			}
			else {
				$value = trim((string) $item);
				$label = '';
			}

			if ($value === '' || array_key_exists($value, $seen)) {
				continue;
			}

			$seen[$value] = true;
			$options[] = ['valor' => $value, 'rotulo' => ($label !== '') ? $label : $value];
		}

		return $options;
	}

	public static function normalizeStringList($raw): array {
		if (is_string($raw)) {
			$raw = preg_split('/\r\n|\r|\n/', $raw);
		}

		if (!is_array($raw)) {
			return [];
		}

		$list = [];

		foreach ($raw as $item) {
			$item = trim((string) $item);

			if ($item !== '' && !in_array($item, $list, true)) {
				$list[] = $item;
			}
		}

		return $list;
	}

	private static function str(array $a, string $key): string {
		return (array_key_exists($key, $a) && is_scalar($a[$key])) ? trim((string) $a[$key]) : '';
	}

	private static function bool(array $a, string $key, bool $default): bool {
		if (!array_key_exists($key, $a)) {
			return $default;
		}

		return in_array($a[$key], [true, 1, '1', 'true', 'on'], true);
	}

	private function error(string $where, string $message): void {
		$this->errors[] = $where.': '.$message;
	}
}
HOSTFLOW_EOF

# ---- lib/form/HostState.php
cat > "$MOD/lib/form/HostState.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

use API;

/**
 * Estado normalizado de um host, a mesclagem de um payload sobre ele e o diff atual × proposto.
 *
 * A mesclagem segue a semântica que a execução vai precisar respeitar, porque host.update do Zabbix
 * SUBSTITUI groups/tags/templates/macros inteiros: aqui só muda o que o payload pede.
 */
final class HostState {

	private const INTERFACE_TYPES = [1 => 'agent', 2 => 'snmp', 3 => 'ipmi', 4 => 'jmx'];
	private const SNMP_KEYS = ['version', 'bulk', 'community', 'securityname', 'securitylevel', 'authprotocol',
		'authpassphrase', 'privprotocol', 'privpassphrase', 'contextname', 'max_repetitions'
	];
	private const SECRET_SNMP_KEYS = ['community', 'authpassphrase', 'privpassphrase'];

	public static function emptyState(): array {
		return [
			'hostid' => null,
			'host' => ['host' => '', 'name' => '', 'description' => '', 'status' => '0'],
			'interface' => [],
			'groups' => [],
			'templates' => [],
			'proxy' => null,
			'proxy_group' => null,
			'tags' => [],
			'macros' => [],
			'inventory' => [],
			'excluir' => false
		];
	}

	/**
	 * Lê o host com a sessão atual. null se não existe ou o usuário não enxerga.
	 */
	public static function read(string $hostid): ?array {
		if (!ctype_digit($hostid)) {
			return null;
		}

		$hosts = API::Host()->get([
			'output' => ['hostid', 'host', 'name', 'description', 'status', 'monitored_by', 'proxyid',
				'proxy_groupid'
			],
			'selectHostGroups' => ['name'],
			'selectParentTemplates' => ['name'],
			'selectTags' => ['tag', 'value'],
			'selectMacros' => ['macro', 'value', 'type'],
			'selectInterfaces' => ['type', 'main', 'ip', 'dns', 'port', 'useip', 'details'],
			'selectInventory' => 'extend',
			'hostids' => [$hostid]
		]);

		if (!$hosts) {
			return null;
		}

		$db = $hosts[0];
		$state = self::emptyState();

		$state['hostid'] = $db['hostid'];
		$state['host'] = [
			'host' => $db['host'],
			'name' => $db['name'],
			'description' => $db['description'],
			'status' => (string) $db['status']
		];

		$state['groups'] = array_column($db['hostgroups'] ?? [], 'name');
		sort($state['groups']);

		$state['templates'] = array_column($db['parentTemplates'] ?? [], 'name');
		sort($state['templates']);

		foreach ($db['tags'] ?? [] as $tag) {
			$state['tags'][$tag['tag']][] = $tag['value'];
		}

		foreach ($db['macros'] ?? [] as $macro) {
			// Macros secretas (type 1) não têm valor legível.
			$state['macros'][$macro['macro']] = ((int) ($macro['type'] ?? 0) === 1) ? '******' : $macro['value'];
		}

		foreach ((array) ($db['inventory'] ?? []) as $key => $value) {
			if ($key !== 'hostid' && $key !== 'inventory_mode' && $value !== '') {
				$state['inventory'][$key] = $value;
			}
		}

		$state['interface'] = self::mainInterface($db['interfaces'] ?? []);

		$monitored_by = (int) ($db['monitored_by'] ?? 0);

		if ($monitored_by === 1 && $db['proxyid'] != 0) {
			$rows = API::Proxy()->get(['output' => ['name'], 'proxyids' => [$db['proxyid']]]);
			$state['proxy'] = $rows ? $rows[0]['name'] : '#'.$db['proxyid'];
		}
		elseif ($monitored_by === 2 && $db['proxy_groupid'] != 0) {
			$rows = API::ProxyGroup()->get(['output' => ['name'], 'proxy_groupids' => [$db['proxy_groupid']]]);
			$state['proxy_group'] = $rows ? $rows[0]['name'] : '#'.$db['proxy_groupid'];
		}

		return $state;
	}

	/**
	 * Interface principal: a "main" do primeiro tipo disponível na ordem agent, snmp, jmx, ipmi.
	 */
	private static function mainInterface(array $interfaces): array {
		foreach ([1, 2, 4, 3] as $type) {
			foreach ($interfaces as $interface) {
				if ((int) $interface['type'] === $type && (int) $interface['main'] === 1) {
					$result = [
						'type' => self::INTERFACE_TYPES[$type],
						'ip' => $interface['ip'],
						'dns' => $interface['dns'],
						'port' => $interface['port'],
						'useip' => (string) $interface['useip']
					];

					if ($type === 2 && is_array($interface['details'] ?? null)) {
						foreach (self::SNMP_KEYS as $key) {
							if (array_key_exists($key, $interface['details'])) {
								$result['snmp'][$key] = (string) $interface['details'][$key];
							}
						}
					}

					return $result;
				}
			}
		}

		return [];
	}

	/**
	 * Aplica o payload sobre o estado (sem tocar no Zabbix).
	 */
	public static function apply(array $state, array $payload): array {
		foreach ($payload['host'] ?? [] as $key => $value) {
			$state['host'][$key] = $value;
		}

		if (!empty($payload['interface'])) {
			$snmp = $payload['interface']['snmp'] ?? [];
			unset($payload['interface']['snmp']);

			$state['interface'] = array_replace($state['interface'], $payload['interface']);

			if ($snmp) {
				$state['interface']['snmp'] = array_replace($state['interface']['snmp'] ?? [], $snmp);
			}
		}

		if (!empty($payload['groups'])) {
			foreach ($payload['groups']['substituir'] ?? [] as $prefix => $names) {
				$state['groups'] = array_values(array_filter($state['groups'], static function ($g) use ($prefix) {
					return strpos($g, (string) $prefix) !== 0;
				}));
				$state['groups'] = array_merge($state['groups'], $names);
			}

			$state['groups'] = array_merge($state['groups'], $payload['groups']['adicionar'] ?? []);
			$state['groups'] = array_values(array_unique($state['groups']));
			sort($state['groups']);
		}

		if (!empty($payload['templates'])) {
			$state['templates'] = array_values(array_diff(
				array_unique(array_merge($state['templates'], $payload['templates']['vincular'] ?? [])),
				$payload['templates']['desvincular'] ?? []
			));
			sort($state['templates']);
		}

		if (array_key_exists('proxy', $payload)) {
			$state['proxy'] = $payload['proxy'];
			$state['proxy_group'] = null;
		}

		if (array_key_exists('proxy_group', $payload)) {
			$state['proxy_group'] = $payload['proxy_group'];
			$state['proxy'] = null;
		}

		foreach ($payload['tags'] ?? [] as $tag => $values) {
			$state['tags'][$tag] = $values;
		}

		ksort($state['tags']);

		foreach ($payload['macros'] ?? [] as $macro => $value) {
			$state['macros'][$macro] = $value;
		}

		foreach ($payload['inventory'] ?? [] as $key => $value) {
			$state['inventory'][$key] = $value;
		}

		$operation = $payload['operacao'] ?? null;

		if ($operation === 'excluir') {
			$state['excluir'] = true;
		}
		elseif ($operation === 'desativar' && !isset($payload['host']['status'])) {
			$state['host']['status'] = '1';
		}

		return $state;
	}

	/**
	 * Achata o estado em "atributo" => "texto" para exibição e diff.
	 */
	public static function flatten(array $state, bool $mask_secrets = true): array {
		$flat = [];

		foreach (['host', 'name', 'description', 'status'] as $key) {
			$flat['host.'.$key] = (string) ($state['host'][$key] ?? '');
		}

		foreach (['type', 'ip', 'dns', 'port', 'useip'] as $key) {
			$flat['interface.'.$key] = (string) ($state['interface'][$key] ?? '');
		}

		foreach ($state['interface']['snmp'] ?? [] as $key => $value) {
			$flat['interface.snmp.'.$key] = ($mask_secrets && in_array($key, self::SECRET_SNMP_KEYS, true)
					&& $value !== '' && strpos((string) $value, '{$') !== 0)
				? '******'
				: (string) $value;
		}

		$flat['groups[]'] = implode("\n", $state['groups']);
		$flat['templates[]'] = implode("\n", $state['templates']);
		$flat['proxy'] = (string) ($state['proxy'] ?? '');
		$flat['proxy_group'] = (string) ($state['proxy_group'] ?? '');

		foreach ($state['tags'] as $tag => $values) {
			$flat['tag:'.$tag] = implode("\n", $values);
		}

		foreach ($state['macros'] as $macro => $value) {
			$flat['macro:'.$macro] = (string) $value;
		}

		foreach ($state['inventory'] as $key => $value) {
			$flat['inventory.'.$key] = (string) $value;
		}

		return $flat;
	}

	/**
	 * @return array<int, array{atributo: string, atual: string, proposto: string}>
	 */
	public static function diff(array $before, array $after): array {
		if (!empty($after['excluir'])) {
			return [['atributo' => 'host', 'atual' => $before['host']['host'] ?? '', 'proposto' => '(EXCLUIR HOST)']];
		}

		$a = self::flatten($before);
		$b = self::flatten($after);
		$rows = [];

		foreach (array_unique(array_merge(array_keys($a), array_keys($b))) as $key) {
			$old = $a[$key] ?? '';
			$new = $b[$key] ?? '';

			if ($old !== $new) {
				$rows[] = ['atributo' => $key, 'atual' => $old, 'proposto' => $new];
			}
		}

		return $rows;
	}

	/**
	 * Valor atual de um alvo, para pré-preencher formulários de update/move/delete.
	 *
	 * @return string|string[]|null
	 */
	public static function valueOf(array $state, string $target) {
		if (strpos($target, 'host.') === 0) {
			return $state['host'][substr($target, 5)] ?? null;
		}

		if (strpos($target, 'interface.snmp.') === 0) {
			return $state['interface']['snmp'][substr($target, 15)] ?? null;
		}

		if (strpos($target, 'interface.') === 0) {
			return $state['interface'][substr($target, 10)] ?? null;
		}

		switch ($target) {
			case 'groups[]':
				return $state['groups'];

			case 'templates[]':
				return $state['templates'];

			case 'proxy':
			case 'proxy_group':
			case 'hostid':
				return $state[$target];
		}

		if (strpos($target, 'tag:') === 0) {
			return $state['tags'][substr($target, 4)] ?? null;
		}

		if (strpos($target, 'macro:') === 0) {
			return $state['macros'][substr($target, 6)] ?? null;
		}

		if (strpos($target, 'inventory.') === 0) {
			return $state['inventory'][substr($target, 10)] ?? null;
		}

		return null;
	}

	/**
	 * Pré-preenchimento: para cada campo, usa o primeiro mapeamento. Se ele tem padrão
	 * (ex.: "Sites/{site.regiao}/{site}/Switches"), extrai o valor do campo por regex.
	 *
	 * @return array<string, string|string[]>
	 */
	public static function prefill(array $form, array $state, Options $options): array {
		$values = [];

		foreach ($form['campos'] as $field) {
			if ($field['tipo'] === 'zbx_host' || !$field['mapeamento']) {
				continue;
			}

			$map = $field['mapeamento'][0];
			$current = self::valueOf($state, $map['alvo']);

			if ($current === null || $current === '' || $current === []) {
				continue;
			}

			$candidates = (array) $current;

			if ($map['alvo'] === 'groups[]' && ($map['modo'] ?? '') === 'substituir_prefixo') {
				$candidates = array_values(array_filter($candidates, static function ($g) use ($map) {
					return strpos($g, $map['prefixo']) === 0;
				}));
			}

			$found = [];

			if (($map['padrao'] ?? '') === '') {
				$found = $candidates;
			}
			else {
				$regex = self::reversePattern($map['padrao'], $field['id']);

				foreach ($candidates as $candidate) {
					if (preg_match($regex, (string) $candidate, $m) && isset($m['v']) && $m['v'] !== '') {
						$found[] = $m['v'];
					}
				}
			}

			$allowed = $options->forField($field);

			if ($allowed !== null) {
				$allowed_values = array_column($allowed, 'valor');
				$found = array_values(array_filter($found, static function ($v) use ($allowed_values) {
					return in_array((string) $v, $allowed_values, true);
				}));
			}

			if (!$found) {
				continue;
			}

			$values[$field['id']] = Options::isMulti($field)
				? array_values(array_unique(array_map('strval', $found)))
				: (string) $found[0];
		}

		return $values;
	}

	/**
	 * Converte o padrão em regex: {campo} vira o grupo de captura "v", outros placeholders viram coringa.
	 */
	private static function reversePattern(string $pattern, string $field_id): string {
		$regex = '';
		$offset = 0;
		$captured = false;

		preg_match_all(FormSchema::PLACEHOLDER_PATTERN, $pattern, $matches, PREG_OFFSET_CAPTURE | PREG_SET_ORDER);

		foreach ($matches as $m) {
			$regex .= preg_quote(substr($pattern, $offset, $m[0][1] - $offset), '/');

			$has_attr = isset($m[2]) && $m[2][1] !== -1;
			$is_self = ($m[1][0] === $field_id && !$has_attr);

			// Coringa preguiçoso: valores podem conter "/" (ex.: "Switch/Core"); o resultado ainda é
			// filtrado pelas opções válidas do campo.
			if ($is_self && !$captured) {
				$regex .= '(?P<v>.+?)';
				$captured = true;
			}
			else {
				$regex .= '.+?';
			}

			$offset = $m[0][1] + strlen($m[0][0]);
		}

		$regex .= preg_quote(substr($pattern, $offset), '/');

		return '/^'.$regex.'$/u';
	}
}
HOSTFLOW_EOF

# ---- lib/form/ListSchema.php
cat > "$MOD/lib/form/ListSchema.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

use Modules\HostFlow\Lib\Storage\JsonStore;

/**
 * Listas compartilhadas de valores controlados (sites, clientes, categorias...).
 *
 * Formato em disco:
 * {"id": "sites", "nome": "Sites", "itens": [{"valor": "SITE_A", "rotulo": "Site A", "attrs": {"regiao": "NORTE"}}]}
 *
 * Formato de edição (uma linha por item):  VALOR | Rótulo | chave=valor; chave2=valor2
 */
final class ListSchema {

	public const ATTR_PATTERN = '/^[a-zA-Z0-9_]{1,64}$/';

	private array $errors = [];

	public function validate(array $raw): ?array {
		$this->errors = [];

		$list = [
			'id' => trim((string) ($raw['id'] ?? '')),
			'nome' => trim((string) ($raw['nome'] ?? '')),
			'itens' => []
		];

		if (!JsonStore::isValidId($list['id'])) {
			$this->errors[] = 'ID: use de 1 a 64 caracteres: letras minúsculas, números, "-" e "_".';
		}

		if ($list['nome'] === '') {
			$this->errors[] = 'Nome: obrigatório.';
		}

		$seen = [];

		foreach (is_array($raw['itens'] ?? null) ? $raw['itens'] : [] as $i => $item) {
			$value = trim((string) ($item['valor'] ?? ''));

			if ($value === '') {
				continue;
			}

			if (array_key_exists($value, $seen)) {
				$this->errors[] = sprintf('Item %d: valor "%s" repetido.', $i + 1, $value);
				continue;
			}

			$seen[$value] = true;
			$attrs = [];

			foreach (is_array($item['attrs'] ?? null) ? $item['attrs'] : [] as $key => $attr_value) {
				if (!preg_match(self::ATTR_PATTERN, (string) $key)) {
					$this->errors[] = sprintf('Item "%s": atributo "%s" inválido (use a-z, 0-9 e "_").', $value, $key);
					continue;
				}

				$attrs[(string) $key] = trim((string) $attr_value);
			}

			$label = trim((string) ($item['rotulo'] ?? ''));

			$list['itens'][] = [
				'valor' => $value,
				'rotulo' => ($label !== '') ? $label : $value,
				'attrs' => (object) $attrs
			];
		}

		if (!$list['itens']) {
			$this->errors[] = 'Itens: a lista precisa de pelo menos um item.';
		}

		return $this->errors ? null : $list;
	}

	public function getErrors(): array {
		return $this->errors;
	}

	/**
	 * Converte o texto de edição em itens.
	 */
	public static function parseText(string $text): array {
		$items = [];

		foreach (preg_split('/\r\n|\r|\n/', $text) as $line) {
			if (trim($line) === '' || strpos(ltrim($line), '#') === 0) {
				continue;
			}

			$parts = array_map('trim', explode('|', $line, 3));
			$attrs = [];

			if (isset($parts[2]) && $parts[2] !== '') {
				foreach (explode(';', $parts[2]) as $pair) {
					if (trim($pair) === '') {
						continue;
					}

					[$key, $value] = array_pad(array_map('trim', explode('=', $pair, 2)), 2, '');
					$attrs[$key] = $value;
				}
			}

			$items[] = ['valor' => $parts[0], 'rotulo' => $parts[1] ?? '', 'attrs' => $attrs];
		}

		return $items;
	}

	public static function toText(array $items): string {
		$lines = [];

		foreach ($items as $item) {
			$line = $item['valor'];
			$attrs = (array) ($item['attrs'] ?? []);
			$label = (string) ($item['rotulo'] ?? '');

			if (($label !== '' && $label !== $item['valor']) || $attrs) {
				$line .= ' | '.$label;
			}

			if ($attrs) {
				$pairs = [];

				foreach ($attrs as $key => $value) {
					$pairs[] = $key.'='.$value;
				}

				$line .= ' | '.implode('; ', $pairs);
			}

			$lines[] = $line;
		}

		return implode("\n", $lines);
	}
}
HOSTFLOW_EOF

# ---- lib/form/Options.php
cat > "$MOD/lib/form/Options.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

/**
 * Resolve as opções válidas de um campo: lista estática, lista compartilhada ou objetos do Zabbix
 * visíveis ao usuário. É a mesma fonte para renderizar o formulário e para validar o envio,
 * então o usuário nunca consegue mandar um valor fora da lista.
 */
final class Options {

	private array $lists;

	public function __construct(array $lists) {
		$this->lists = $lists;
	}

	/**
	 * @return array<int, array{valor: string, rotulo: string, attrs: array}>|null  null = campo sem lista fechada.
	 */
	public function forField(array $field): ?array {
		switch ($field['tipo']) {
			case 'select':
			case 'multiselect':
			case 'tag_value':
				if (($field['lista'] ?? '') !== '') {
					$list = $this->lists[$field['lista']] ?? ['itens' => []];

					return array_map(static function (array $item): array {
						return [
							'valor' => (string) $item['valor'],
							'rotulo' => (string) ($item['rotulo'] ?? $item['valor']),
							'attrs' => (array) ($item['attrs'] ?? [])
						];
					}, $list['itens']);
				}

				return array_map(static function (array $o): array {
					return $o + ['attrs' => []];
				}, $field['opcoes'] ?? []);

			case 'zbx_hostgroup':
				return self::names(ZabbixLookup::hostGroupNames($field['prefixo'] ?? ''));

			case 'zbx_template':
				if (!empty($field['permitidos'])) {
					return self::names($field['permitidos']);
				}

				if (($field['grupo_templates'] ?? '') !== '') {
					return self::names(ZabbixLookup::templateNamesInGroup($field['grupo_templates']));
				}

				return [];

			case 'zbx_proxy':
				return self::names(!empty($field['permitidos']) ? $field['permitidos'] : ZabbixLookup::proxyNames());

			case 'zbx_proxy_group':
				return self::names(!empty($field['permitidos'])
					? $field['permitidos']
					: ZabbixLookup::proxyGroupNames()
				);
		}

		return null;
	}

	public function attrsOf(array $field, string $value): array {
		foreach ($this->forField($field) ?? [] as $option) {
			if ($option['valor'] === $value) {
				return $option['attrs'];
			}
		}

		return [];
	}

	public static function isMulti(array $field): bool {
		return $field['tipo'] === 'multiselect'
			|| (in_array($field['tipo'], FormSchema::MULTI_CAPABLE, true) && !empty($field['multiplo']));
	}

	private static function names(array $names): array {
		return array_map(static function (string $name): array {
			return ['valor' => $name, 'rotulo' => $name, 'attrs' => []];
		}, array_values($names));
	}
}
HOSTFLOW_EOF

# ---- lib/form/PayloadBuilder.php
cat > "$MOD/lib/form/PayloadBuilder.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

/**
 * Converte valores do formulário + mapeamentos + valores fixos em um "payload" de host:
 *
 * {
 *   "hostid": "10601",                         (update/move/delete)
 *   "operacao": "desativar",                   (delete)
 *   "host": {"host": "...", "name": "...", "description": "...", "status": "0"},
 *   "interface": {"type": "snmp", "ip": "...", "port": "161", "snmp": {"version": "2", "community": "..."}},
 *   "groups": {"adicionar": ["A/B"], "substituir": {"Sites/": ["Sites/X/Y"]}},
 *   "templates": {"vincular": ["T1"], "desvincular": []},
 *   "proxy": "proxy-x" | "proxy_group": "grupo-x",
 *   "tags": {"categoria": ["REDE"]},
 *   "macros": {"{$SNMP_COMMUNITY}": "..."},
 *   "inventory": {"location": "..."}
 * }
 *
 * O payload é declarativo (o que deve mudar). Quem aplica a mesclagem com o estado atual é HostState::apply().
 */
final class PayloadBuilder {

	private array $form;
	private Options $options;
	private array $fields_by_id = [];

	public function __construct(array $form, Options $options) {
		$this->form = $form;
		$this->options = $options;

		foreach ($form['campos'] as $field) {
			$this->fields_by_id[$field['id']] = $field;
		}
	}

	public static function emptyPayload(): array {
		return [
			'host' => [],
			'interface' => [],
			'groups' => ['adicionar' => [], 'substituir' => []],
			'templates' => ['vincular' => [], 'desvincular' => []],
			'tags' => [],
			'macros' => [],
			'inventory' => []
		];
	}

	/**
	 * @param array $values  Valores validados (Submission::getValues()); null = campo oculto.
	 */
	public function build(array $values): array {
		$payload = self::emptyPayload();

		foreach ($this->form['campos'] as $field) {
			$value = $values[$field['id']] ?? null;

			if ($value === null || $value === '' || $value === []) {
				continue;
			}

			foreach ($field['mapeamento'] as $map) {
				foreach ((array) $value as $single) {
					$resolved = ($map['padrao'] ?? '') === ''
						? $single
						: $this->resolve($map['padrao'], $values, $field['id'], $single);

					if ($resolved !== null && $resolved !== '') {
						self::apply($payload, $map, $resolved);
					}

					if (!in_array($map['alvo'], ['groups[]', 'templates[]'], true)
							&& strpos($map['alvo'], 'tag:') !== 0) {
						// Alvos de valor único usam só o primeiro valor de um campo múltiplo.
						break;
					}
				}
			}
		}

		foreach ($this->form['valores_fixos'] as $fixed) {
			if (!Submission::isVisible($fixed, $values)) {
				continue;
			}

			$resolved = $this->resolve($fixed['valor'], $values, null, null);

			if ($resolved !== null && $resolved !== '') {
				self::apply($payload, $fixed, $resolved);
			}
		}

		return self::cleanup($payload);
	}

	/**
	 * Substitui {campo} e {campo.atributo}. Retorna null se algum placeholder ficar vazio,
	 * para nunca gerar algo como "Sites//Switches".
	 */
	private function resolve(string $template, array $values, ?string $self_id, ?string $self_value): ?string {
		$failed = false;

		$result = preg_replace_callback(FormSchema::PLACEHOLDER_PATTERN,
			function (array $m) use ($values, $self_id, $self_value, &$failed): string {
				$ref = $m[1];
				$attr = $m[2] ?? '';

				if ($ref === $self_id) {
					$value = $self_value;
				}
				else {
					$value = $values[$ref] ?? null;
					$value = is_array($value) ? (reset($value) ?: null) : $value;
				}

				if ($value === null || $value === '') {
					$failed = true;

					return '';
				}

				if ($attr === '') {
					return (string) $value;
				}

				$field = $this->fields_by_id[$ref] ?? null;
				$attrs = ($field !== null) ? $this->options->attrsOf($field, (string) $value) : [];

				if (!array_key_exists($attr, $attrs) || (string) $attrs[$attr] === '') {
					$failed = true;

					return '';
				}

				return (string) $attrs[$attr];
			},
			$template
		);

		return $failed ? null : $result;
	}

	private static function apply(array &$payload, array $map, string $value): void {
		$target = $map['alvo'];

		if (strpos($target, 'host.') === 0) {
			$payload['host'][substr($target, 5)] = $value;
		}
		elseif (strpos($target, 'interface.snmp.') === 0) {
			$payload['interface']['snmp'][substr($target, 15)] = $value;
		}
		elseif (strpos($target, 'interface.') === 0) {
			$payload['interface'][substr($target, 10)] = $value;
		}
		elseif ($target === 'groups[]') {
			if (($map['modo'] ?? 'adicionar') === 'substituir_prefixo') {
				$prefix = $map['prefixo'];

				if (!in_array($value, $payload['groups']['substituir'][$prefix] ?? [], true)) {
					$payload['groups']['substituir'][$prefix][] = $value;
				}
			}
			elseif (!in_array($value, $payload['groups']['adicionar'], true)) {
				$payload['groups']['adicionar'][] = $value;
			}
		}
		elseif ($target === 'templates[]') {
			$mode = $map['modo'] ?? 'vincular';

			if (!in_array($value, $payload['templates'][$mode], true)) {
				$payload['templates'][$mode][] = $value;
			}
		}
		elseif ($target === 'proxy') {
			$payload['proxy'] = $value;
			unset($payload['proxy_group']);
		}
		elseif ($target === 'proxy_group') {
			$payload['proxy_group'] = $value;
			unset($payload['proxy']);
		}
		elseif ($target === 'hostid' || $target === 'operacao') {
			$payload[$target] = $value;
		}
		elseif (strpos($target, 'tag:') === 0) {
			$tag = substr($target, 4);

			if (!in_array($value, $payload['tags'][$tag] ?? [], true)) {
				$payload['tags'][$tag][] = $value;
			}
		}
		elseif (strpos($target, 'macro:') === 0) {
			$payload['macros'][substr($target, 6)] = $value;
		}
		elseif (strpos($target, 'inventory.') === 0) {
			$payload['inventory'][substr($target, 10)] = $value;
		}
	}

	private static function cleanup(array $payload): array {
		foreach (['host', 'interface', 'tags', 'macros', 'inventory'] as $key) {
			if (!$payload[$key]) {
				unset($payload[$key]);
			}
		}

		if (!$payload['groups']['adicionar'] && !$payload['groups']['substituir']) {
			unset($payload['groups']);
		}

		if (!$payload['templates']['vincular'] && !$payload['templates']['desvincular']) {
			unset($payload['templates']);
		}

		return $payload;
	}
}
HOSTFLOW_EOF

# ---- lib/form/Repository.php
cat > "$MOD/lib/form/Repository.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

use Modules\HostFlow\Lib\Config;
use Modules\HostFlow\Lib\Storage\JsonStore;

/**
 * Acesso a formulários (<data_dir>/forms) e listas compartilhadas (<data_dir>/lists).
 * Trocar o backend (ex.: banco) depois significa reimplementar só esta classe.
 */
final class Repository {

	private JsonStore $forms;
	private JsonStore $lists;

	public function __construct(?string $data_dir = null) {
		$data_dir = $data_dir ?? Config::dataDir();

		$this->forms = new JsonStore($data_dir.'/forms');
		$this->lists = new JsonStore($data_dir.'/lists');
	}

	public function formsStore(): JsonStore {
		return $this->forms;
	}

	public function listsStore(): JsonStore {
		return $this->lists;
	}

	/**
	 * @return array<string, array>
	 */
	public function forms(bool $only_active = false): array {
		$forms = $this->forms->all();

		if ($only_active) {
			$forms = array_filter($forms, static function (array $form): bool {
				return !empty($form['ativo']);
			});
		}

		uasort($forms, static function (array $a, array $b): int {
			return strcasecmp((string) ($a['nome'] ?? ''), (string) ($b['nome'] ?? ''));
		});

		return $forms;
	}

	public function form(string $id): ?array {
		return $this->forms->get($id);
	}

	public function saveForm(array $form): void {
		$this->forms->put($form['id'], $form);
	}

	public function deleteForm(string $id): void {
		$this->forms->delete($id);
	}

	/**
	 * @return array<string, array>
	 */
	public function lists(): array {
		return $this->lists->all();
	}

	public function list(string $id): ?array {
		return $this->lists->get($id);
	}

	public function saveList(array $list): void {
		$this->lists->put($list['id'], $list);
	}

	public function deleteList(string $id): void {
		$this->lists->delete($id);
	}

	/**
	 * Formulários que usam a lista (para impedir exclusão de lista em uso).
	 */
	public function formsUsingList(string $list_id): array {
		$names = [];

		foreach ($this->forms->all() as $form) {
			foreach ($form['campos'] ?? [] as $field) {
				if (($field['lista'] ?? '') === $list_id) {
					$names[] = $form['nome'] ?? $form['id'];
					break;
				}
			}
		}

		return $names;
	}
}
HOSTFLOW_EOF

# ---- lib/form/Submission.php
cat > "$MOD/lib/form/Submission.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

/**
 * Valida os valores enviados pelo usuário contra a definição do formulário
 * e monta o estado proposto do host.
 */
final class Submission {

	private const HOST_NAME_PATTERN = '/^[0-9a-zA-Z_. \-]+$/';
	private const DNS_PATTERN = '/^(?=.{1,255}$)[A-Za-z0-9](?:[A-Za-z0-9_-]{0,62}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9_-]{0,62}[A-Za-z0-9])?)*\.?$/';

	private array $form;
	private Options $options;

	/** @var array<string, string[]> erros por id de campo */
	private array $field_errors = [];

	/** @var string[] erros gerais */
	private array $errors = [];

	/** @var array<string, string|string[]|null> valores normalizados (null = campo oculto) */
	private array $values = [];

	public function __construct(array $form, Options $options) {
		$this->form = $form;
		$this->options = $options;
	}

	public function getValues(): array {
		return $this->values;
	}

	public function getFieldErrors(): array {
		return $this->field_errors;
	}

	public function getErrors(): array {
		return $this->errors;
	}

	public function hasErrors(): bool {
		return $this->field_errors || $this->errors;
	}

	/**
	 * Etapa 1: valida cada campo isoladamente.
	 */
	public function validateFields(array $raw): bool {
		$this->values = [];

		// Primeiro normaliza tudo, porque a visibilidade depende do valor de outros campos.
		$normalized = [];

		foreach ($this->form['campos'] as $field) {
			$normalized[$field['id']] = self::normalize($field, $raw[$field['id']] ?? null);
		}

		foreach ($this->form['campos'] as $field) {
			$id = $field['id'];

			if (!self::isVisible($field, $normalized)) {
				$this->values[$id] = null;
				continue;
			}

			$value = $normalized[$id];
			$this->values[$id] = $value;

			$empty = is_array($value) ? !$value : ($value === '' || ($field['tipo'] === 'checkbox' && $value === '0'));

			if ($empty) {
				if ($field['obrigatorio']) {
					$this->fieldError($id, 'Campo obrigatório.');
				}

				continue;
			}

			$this->validateValue($field, $value);
		}

		return !$this->hasErrors();
	}

	/**
	 * Etapa 2: monta o payload e faz as checagens que dependem do Zabbix.
	 */
	public function buildPayload(): array {
		return (new PayloadBuilder($this->form, $this->options))->build($this->values);
	}

	/**
	 * Checagens cruzadas com o estado do Zabbix. Rodam com a sessão de quem envia, então só
	 * enxergam o que esse usuário pode ler. A revalidação completa acontece depois do submit.
	 */
	public function validatePayload(array $payload, ?array $current_host): bool {
		$type = $this->form['tipo'];

		if ($type !== 'create') {
			if ($current_host === null) {
				$this->errors[] = 'Host não encontrado ou sem permissão de leitura.';

				return false;
			}
		}

		$host_name = $payload['host']['host'] ?? null;

		if ($host_name !== null) {
			if (!preg_match(self::HOST_NAME_PATTERN, $host_name)) {
				$this->errors[] = sprintf('Nome técnico "%s" inválido: use letras, números, espaço, ".", "_" e "-".',
					$host_name
				);
			}
			else {
				foreach (ZabbixLookup::hostsByTechnicalName($host_name) as $other) {
					if ($current_host === null || $other['hostid'] !== $current_host['hostid']) {
						$this->errors[] = sprintf('Já existe um host com o nome técnico "%s".', $host_name);
						break;
					}
				}
			}
		}

		$visible_name = $payload['host']['name'] ?? null;

		if ($visible_name !== null) {
			foreach (ZabbixLookup::hostsByVisibleName($visible_name) as $other) {
				if ($current_host === null || $other['hostid'] !== $current_host['hostid']) {
					$this->errors[] = sprintf('Já existe um host com o nome visível "%s".', $visible_name);
					break;
				}
			}
		}

		$ip = $payload['interface']['ip'] ?? null;

		if ($ip !== null && $type === 'create') {
			$others = ZabbixLookup::hostsWithIp($ip);

			if ($others) {
				$this->errors[] = sprintf('O IP %s já está em uso por: %s.', $ip,
					implode(', ', array_column($others, 'name'))
				);
			}
		}

		$groups = $payload['groups']['adicionar'] ?? [];

		foreach ($payload['groups']['substituir'] ?? [] as $names) {
			$groups = array_merge($groups, $names);
		}

		$missing = ZabbixLookup::missingHostGroups(array_values(array_unique($groups)));

		if ($missing) {
			$this->errors[] = sprintf('Grupo(s) inexistente(s) ou sem permissão: %s. Peça a criação ao administrador.',
				implode(', ', $missing)
			);
		}

		if ($type === 'create' && !$groups) {
			$this->errors[] = 'Nenhum grupo de hosts foi definido.';
		}

		return !$this->hasErrors();
	}

	private function validateValue(array $field, $value): void {
		$id = $field['id'];
		$type = $field['tipo'];

		if (in_array($type, FormSchema::TEXT_TYPES, true)) {
			if ($type === 'ip' && filter_var($value, FILTER_VALIDATE_IP) === false) {
				$this->fieldError($id, 'Endereço IP inválido.');
			}

			if ($type === 'dns' && !preg_match(self::DNS_PATTERN, $value)) {
				$this->fieldError($id, 'Nome DNS inválido.');
			}

			if (mb_strlen($value) > ($type === 'textarea' ? 65535 : 2048)) {
				$this->fieldError($id, 'Texto longo demais.');
			}

			if (($field['regex'] ?? '') !== '' && !preg_match(FormSchema::wrapRegex($field['regex']), $value)) {
				$this->fieldError($id, 'Formato inválido.'
					.(($field['ajuda'] ?? '') !== '' ? ' '.$field['ajuda'] : '')
				);
			}

			return;
		}

		if ($type === 'zbx_host') {
			if (ZabbixLookup::host($value) === null) {
				$this->fieldError($id, 'Host não encontrado ou sem permissão de leitura.');
			}

			return;
		}

		$options = $this->options->forField($field);

		if ($options === null) {
			return;
		}

		$allowed = array_column($options, 'valor');

		foreach ((array) $value as $v) {
			if (!in_array($v, $allowed, true)) {
				$this->fieldError($id, sprintf('Valor "%s" não é permitido.', $v));
			}
		}
	}

	/**
	 * @return string|string[]
	 */
	public static function normalize(array $field, $raw) {
		if (Options::isMulti($field)) {
			$values = [];

			foreach (is_array($raw) ? $raw : (($raw === null || $raw === '') ? [] : [$raw]) as $v) {
				if (is_scalar($v) && trim((string) $v) !== '' && !in_array(trim((string) $v), $values, true)) {
					$values[] = trim((string) $v);
				}
			}

			return $values;
		}

		if ($field['tipo'] === 'checkbox') {
			return ($raw === '1' || $raw === 1 || $raw === true || $raw === 'on') ? '1' : '0';
		}

		if ($field['tipo'] === 'zbx_host' && is_array($raw)) {
			$raw = reset($raw);
		}

		if (!is_scalar($raw)) {
			return '';
		}

		$raw = (string) $raw;

		return ($field['tipo'] === 'textarea') ? trim(str_replace("\r\n", "\n", $raw)) : trim($raw);
	}

	public static function isVisible(array $field, array $values): bool {
		$cond = $field['quando'] ?? null;

		if ($cond === null) {
			return true;
		}

		$other = $values[$cond['campo']] ?? null;

		return is_array($other) ? in_array($cond['igual'], $other, true) : ((string) $other === $cond['igual']);
	}

	private function fieldError(string $id, string $message): void {
		$this->field_errors[$id][] = $message;
	}
}
HOSTFLOW_EOF

# ---- lib/form/ZabbixLookup.php
cat > "$MOD/lib/form/ZabbixLookup.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Form;

use API;

/**
 * Consultas à API interna do frontend. Todas rodam com a sessão do usuário logado,
 * então só retornam o que ele tem permissão de ler.
 */
final class ZabbixLookup {

	private static array $cache = [];

	/**
	 * @return string[]  Nomes de grupos de hosts visíveis que começam com $prefix.
	 */
	public static function hostGroupNames(string $prefix = ''): array {
		return self::cached('hg:'.$prefix, static function () use ($prefix): array {
			$options = ['output' => ['name'], 'sortfield' => 'name'];

			if ($prefix !== '') {
				$options['search'] = ['name' => $prefix];
				$options['startSearch'] = true;
			}

			$rows = API::HostGroup()->get($options);

			$names = is_array($rows) ? array_column($rows, 'name') : [];

			// startSearch não diferencia maiúsculas; garante o prefixo exato.
			return array_values(array_filter($names, static function (string $name) use ($prefix): bool {
				return $prefix === '' || strpos($name, $prefix) === 0;
			}));
		});
	}

	public static function templateNamesInGroup(string $group_name): array {
		return self::cached('tg:'.$group_name, static function () use ($group_name): array {
			$groups = API::TemplateGroup()->get(['output' => ['groupid'], 'filter' => ['name' => $group_name]]);

			if (!$groups) {
				return [];
			}

			$rows = API::Template()->get([
				'output' => ['name'],
				'groupids' => array_column($groups, 'groupid'),
				'sortfield' => 'name'
			]);

			return is_array($rows) ? array_column($rows, 'name') : [];
		});
	}

	public static function proxyNames(): array {
		return self::cached('px', static function (): array {
			$rows = API::Proxy()->get(['output' => ['name'], 'sortfield' => 'name']);

			return is_array($rows) ? array_column($rows, 'name') : [];
		});
	}

	public static function proxyGroupNames(): array {
		return self::cached('pg', static function (): array {
			$rows = API::ProxyGroup()->get(['output' => ['name'], 'sortfield' => 'name']);

			return is_array($rows) ? array_column($rows, 'name') : [];
		});
	}

	public static function missingTemplates(array $names): array {
		return self::missing($names, static function (array $names) {
			return API::Template()->get(['output' => ['name'], 'filter' => ['name' => $names]]);
		});
	}

	public static function missingProxies(array $names): array {
		return self::missing($names, static function (array $names) {
			return API::Proxy()->get(['output' => ['name'], 'filter' => ['name' => $names]]);
		});
	}

	public static function missingProxyGroups(array $names): array {
		return self::missing($names, static function (array $names) {
			return API::ProxyGroup()->get(['output' => ['name'], 'filter' => ['name' => $names]]);
		});
	}

	public static function missingHostGroups(array $names): array {
		return self::missing($names, static function (array $names) {
			return API::HostGroup()->get(['output' => ['name'], 'filter' => ['name' => $names]]);
		});
	}

	/**
	 * @return array|null  ['hostid', 'host', 'name'] ou null se não existe ou o usuário não enxerga.
	 */
	public static function host(string $hostid): ?array {
		if (!ctype_digit($hostid)) {
			return null;
		}

		$rows = API::Host()->get(['output' => ['hostid', 'host', 'name'], 'hostids' => [$hostid]]);

		return $rows ? $rows[0] : null;
	}

	/**
	 * Hosts com esse nome técnico (entre os que o usuário enxerga).
	 */
	public static function hostsByTechnicalName(string $host): array {
		$rows = API::Host()->get(['output' => ['hostid', 'host', 'name'], 'filter' => ['host' => $host]]);

		return is_array($rows) ? $rows : [];
	}

	public static function hostsByVisibleName(string $name): array {
		$rows = API::Host()->get(['output' => ['hostid', 'host', 'name'], 'filter' => ['name' => $name]]);

		return is_array($rows) ? $rows : [];
	}

	/**
	 * Hosts que já têm interface com esse IP (entre os que o usuário enxerga).
	 */
	public static function hostsWithIp(string $ip): array {
		$interfaces = API::HostInterface()->get(['output' => ['hostid'], 'filter' => ['ip' => $ip]]);

		if (!$interfaces) {
			return [];
		}

		$rows = API::Host()->get([
			'output' => ['hostid', 'host', 'name'],
			'hostids' => array_unique(array_column($interfaces, 'hostid'))
		]);

		return is_array($rows) ? $rows : [];
	}

	private static function missing(array $names, callable $fetch): array {
		$names = array_values(array_filter($names, 'strlen'));

		if (!$names) {
			return [];
		}

		$rows = $fetch($names);
		$found = is_array($rows) ? array_column($rows, 'name') : [];

		return array_values(array_diff($names, $found));
	}

	private static function cached(string $key, callable $fn): array {
		if (!array_key_exists($key, self::$cache)) {
			self::$cache[$key] = $fn();
		}

		return self::$cache[$key];
	}
}
HOSTFLOW_EOF

# ---- lib/storage/JsonStore.php
cat > "$MOD/lib/storage/JsonStore.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Storage;

use RuntimeException;

/**
 * Diretório de documentos JSON, um arquivo por id (<dir>/<id>.json).
 * A gravação é atômica: escreve num arquivo temporário e renomeia.
 */
class JsonStore {

	public const ID_PATTERN = '/^[a-z0-9][a-z0-9_-]{0,63}$/';

	private string $dir;

	public function __construct(string $dir) {
		$this->dir = rtrim($dir, '/');
	}

	public function getDir(): string {
		return $this->dir;
	}

	public static function isValidId(string $id): bool {
		return (bool) preg_match(self::ID_PATTERN, $id);
	}

	public function isWritable(): bool {
		if (is_dir($this->dir)) {
			return is_writable($this->dir);
		}

		$parent = dirname($this->dir);

		return is_dir($parent) && is_writable($parent);
	}

	/**
	 * @return string[]
	 */
	public function ids(): array {
		if (!is_dir($this->dir)) {
			return [];
		}

		$ids = [];

		foreach (glob($this->dir.'/*.json') ?: [] as $file) {
			$id = basename($file, '.json');

			if (self::isValidId($id)) {
				$ids[] = $id;
			}
		}

		sort($ids);

		return $ids;
	}

	public function exists(string $id): bool {
		return self::isValidId($id) && is_file($this->path($id));
	}

	public function get(string $id): ?array {
		if (!$this->exists($id)) {
			return null;
		}

		$raw = file_get_contents($this->path($id));
		$data = ($raw === false) ? null : json_decode($raw, true);

		return is_array($data) ? $data : null;
	}

	/**
	 * @return array<string, array>
	 */
	public function all(): array {
		$all = [];

		foreach ($this->ids() as $id) {
			$doc = $this->get($id);

			if ($doc !== null) {
				$all[$id] = $doc;
			}
		}

		return $all;
	}

	public function put(string $id, array $data): void {
		if (!self::isValidId($id)) {
			throw new RuntimeException(sprintf('ID inválido: "%s".', $id));
		}

		if (!is_dir($this->dir) && !@mkdir($this->dir, 0770, true) && !is_dir($this->dir)) {
			throw new RuntimeException(sprintf('Não foi possível criar o diretório "%s".', $this->dir));
		}

		$json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

		if ($json === false) {
			throw new RuntimeException('Falha ao serializar JSON.');
		}

		$tmp = $this->dir.'/.'.$id.'.'.bin2hex(random_bytes(4)).'.tmp';

		if (@file_put_contents($tmp, $json."\n", LOCK_EX) === false) {
			throw new RuntimeException(sprintf('Sem permissão de escrita em "%s".', $this->dir));
		}

		@chmod($tmp, 0660);

		if (!@rename($tmp, $this->path($id))) {
			@unlink($tmp);
			throw new RuntimeException(sprintf('Não foi possível gravar "%s".', $this->path($id)));
		}
	}

	public function delete(string $id): void {
		if ($this->exists($id) && !@unlink($this->path($id))) {
			throw new RuntimeException(sprintf('Não foi possível excluir "%s".', $this->path($id)));
		}
	}

	private function path(string $id): string {
		return $this->dir.'/'.$id.'.json';
	}
}
HOSTFLOW_EOF

# ---- lib/submit/NullSubmitHandler.php
cat > "$MOD/lib/submit/NullSubmitHandler.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Submit;

/**
 * Padrão do MVP: não envia nada. Será substituído pela integração com o sistema de chamados.
 */
final class NullSubmitHandler implements SubmitHandler {

	public function handle(array $submission): array {
		return [
			'ok' => true,
			'mensagem' => 'Envio ainda não configurado: a solicitação foi validada, mas não foi enviada a nenhum sistema.',
			'referencia' => null
		];
	}
}
HOSTFLOW_EOF

# ---- lib/submit/SubmitHandler.php
cat > "$MOD/lib/submit/SubmitHandler.php" <<'HOSTFLOW_EOF'
<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Submit;

/**
 * Ponto de extensão do que acontece depois de um envio válido.
 * A integração com o sistema de chamados (abrir chamado para a equipe responsável) vai implementar esta interface
 * e ser ativada em /etc/zabbix/hostflow.conf.php via 'submit_handler'.
 */
interface SubmitHandler {

	/**
	 * @param array $submission  [
	 *     'formulario' => array   definição completa do formulário (inclui 'equipe_responsavel'),
	 *     'valores'    => array   id do campo => valor (null = campo oculto),
	 *     'resumo'     => array   [['rotulo' => ..., 'valor' => ...]] legível por humanos,
	 *     'payload'    => array   alterações declarativas no host (ver PayloadBuilder),
	 *     'host_atual' => ?array  estado do host antes (update/move/delete),
	 *     'diff'       => array   [['atributo', 'atual', 'proposto']],
	 *     'justificativa' => string,
	 *     'solicitante' => ['userid', 'username', 'name', 'surname'],
	 *     'enviado_em' => int     timestamp
	 * ]
	 *
	 * @return array ['ok' => bool, 'mensagem' => string, 'referencia' => ?string]
	 */
	public function handle(array $submission): array;
}
HOSTFLOW_EOF

# ---- manifest.json
cat > "$MOD/manifest.json" <<'HOSTFLOW_EOF'
{
	"manifest_version": 2.0,
	"id": "hostflow",
	"name": "HostFlow - Solicitações de hosts",
	"namespace": "HostFlow",
	"version": "0.1.0",
	"author": "HostFlow",
	"description": "Formulários padronizados para solicitar criação, alteração, movimentação e exclusão de hosts.",
	"actions": {
		"hostflow.form.list": {
			"class": "FormList",
			"view": "hostflow.form.list"
		},
		"hostflow.form.edit": {
			"class": "FormEdit",
			"view": "hostflow.form.edit"
		},
		"hostflow.form.save": {
			"class": "FormSave",
			"view": "hostflow.form.edit"
		},
		"hostflow.form.delete": {
			"class": "FormDelete"
		},
		"hostflow.list.list": {
			"class": "ListList",
			"view": "hostflow.list.list"
		},
		"hostflow.list.edit": {
			"class": "ListEdit",
			"view": "hostflow.list.edit"
		},
		"hostflow.list.save": {
			"class": "ListSave",
			"view": "hostflow.list.edit"
		},
		"hostflow.list.delete": {
			"class": "ListDelete"
		},
		"hostflow.request.new": {
			"class": "RequestNew",
			"view": "hostflow.request.new"
		},
		"hostflow.request.submit": {
			"class": "RequestSubmit",
			"view": "hostflow.request.new"
		}
	},
	"assets": {
		"css": ["hostflow.css"],
		"js": ["hostflow.common.js", "hostflow.builder.js", "hostflow.request.js"]
	}
}
HOSTFLOW_EOF

# ---- views/hostflow.form.edit.php
cat > "$MOD/views/hostflow.form.edit.php" <<'HOSTFLOW_EOF'
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
	->addItem(new CVar('definition', '', 'hf-definition'));

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
HOSTFLOW_EOF

# ---- views/hostflow.form.list.php
cat > "$MOD/views/hostflow.form.list.php" <<'HOSTFLOW_EOF'
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
HOSTFLOW_EOF

# ---- views/hostflow.list.edit.php
cat > "$MOD/views/hostflow.list.edit.php" <<'HOSTFLOW_EOF'
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
HOSTFLOW_EOF

# ---- views/hostflow.list.list.php
cat > "$MOD/views/hostflow.list.list.php" <<'HOSTFLOW_EOF'
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
HOSTFLOW_EOF

# ---- views/hostflow.request.new.php
cat > "$MOD/views/hostflow.request.new.php" <<'HOSTFLOW_EOF'
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

		if ($field['quando'] !== null) {
			$el->setAttribute('data-hf-when-field', $field['quando']['campo']);
			$el->setAttribute('data-hf-when-value', $field['quando']['igual']);
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
HOSTFLOW_EOF

# ---- permissões do código do módulo (somente leitura para o servidor web)
chown -R root:root "$MOD"
find "$MOD" -type d -exec chmod 755 {} +
find "$MOD" -type f -exec chmod 644 {} +

echo "HostFlow copiado para $MOD"
