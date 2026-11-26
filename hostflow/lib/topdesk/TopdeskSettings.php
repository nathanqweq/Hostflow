<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Topdesk;

use Modules\HostFlow\Lib\Config;
use Modules\HostFlow\Lib\Storage\JsonStore;

/**
 * Configuração da integração com o TOPdesk, editada em "Solicitações › Integração TOPdesk"
 * e gravada em <data_dir>/settings/topdesk.json (fora do webroot, 0660).
 *
 * A senha (application password do TOPdesk) nunca volta para o navegador: o formulário só a substitui
 * quando um valor novo é digitado.
 */
final class TopdeskSettings {

	private const STORE_ID = 'topdesk';

	/**
	 * Campos de classificação do chamado: chave interna => [rótulo, chave no JSON do TOPdesk, dica].
	 * O valor pode ser o ID (UUID) ou o nome exato cadastrado no TOPdesk.
	 */
	public const LOOKUPS = [
		'tipo_chamado' => ['Tipo de chamado (call_type)', 'callType', ''],
		'categoria' => ['Categoria (category)', 'category', ''],
		'subcategoria' => ['Subcategoria (subcategory)', 'subcategory', ''],
		'impacto' => ['Impacto (impact)', 'impact', ''],
		'urgencia' => ['Urgência (urgency)', 'urgency', ''],
		'prioridade' => ['Prioridade (priority)', 'priority', ''],
		'grupo_operador' => ['Grupo de operadores (oper_group)', 'operatorGroup', ''],
		'operador' => ['Operador (ID)', 'operator', ''],
		'sla' => ['SLA (ID)', 'sla', ''],
		'contrato' => ['Contrato (ID)', 'contract', 'Se o TOPdesk recusar o campo "contract", deixe vazio.'],
		'status' => ['Status de processamento (processingStatus)', 'processingStatus',
			'Status com que o chamado é aberto.'
		]
	];

	public static function defaults(): array {
		$defaults = [
			'ativo' => false,
			'url' => '',
			'usuario' => '',
			'senha' => '',
			'cliente' => '',
			'solicitante_padrao' => '',
			'verificar_ssl' => true,
			'enviar_segredos' => false,
			'campos_extras' => ''
		];

		foreach (array_keys(self::LOOKUPS) as $key) {
			$defaults[$key] = '';
		}

		$defaults['status'] = 'Registrado';

		return $defaults;
	}

	private static function store(): JsonStore {
		return new JsonStore(Config::dataDir().'/settings');
	}

	public static function load(): array {
		$saved = self::store()->get(self::STORE_ID) ?? [];

		return array_replace(self::defaults(), array_intersect_key($saved, self::defaults()));
	}

	public static function save(array $settings): void {
		self::store()->put(self::STORE_ID, array_intersect_key($settings, self::defaults()));
	}

	public static function isWritable(): bool {
		return self::store()->isWritable();
	}

	public static function isActive(): bool {
		$s = self::load();

		return !empty($s['ativo']) && $s['url'] !== '' && $s['usuario'] !== '' && $s['senha'] !== '';
	}

	/**
	 * @return string[]  erros de validação
	 */
	public static function validate(array $s): array {
		$errors = [];

		if ($s['url'] !== '' && !preg_match('~^https?://[^\s/]+~i', $s['url'])) {
			$errors[] = 'Endereço inválido. Use algo como https://empresa.topdesk.net';
		}

		if (!empty($s['ativo'])) {
			foreach (['url' => 'Endereço', 'usuario' => 'Usuário', 'senha' => 'Senha', 'cliente' => 'Cliente'] as $k => $label) {
				if (trim((string) $s[$k]) === '') {
					$errors[] = sprintf('Para ativar a integração, preencha "%s".', $label);
				}
			}
		}

		if ($s['solicitante_padrao'] !== '' && !filter_var($s['solicitante_padrao'], FILTER_VALIDATE_EMAIL)) {
			$errors[] = 'O solicitante padrão deve ser um e-mail.';
		}

		if (trim($s['campos_extras']) !== '') {
			$extra = json_decode($s['campos_extras'], true);

			// array_is_list() só existe a partir do PHP 8.1.
			if (!is_array($extra) || ($extra && array_keys($extra) === range(0, count($extra) - 1))) {
				$errors[] = 'Campos extras: informe um objeto JSON, ex.: {"entryType": {"name": "Zabbix"}}';
			}
		}

		return $errors;
	}

	/**
	 * Valor de referência do TOPdesk: UUID vira {"id"}, qualquer outro texto vira {"name"}.
	 */
	public static function reference(string $value): array {
		$value = trim($value);

		return preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $value)
			? ['id' => $value]
			: ['name' => $value];
	}
}
