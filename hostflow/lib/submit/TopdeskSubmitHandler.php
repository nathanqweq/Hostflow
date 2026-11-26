<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Submit;

use Modules\HostFlow\Lib\Topdesk\TopdeskClient;
use Modules\HostFlow\Lib\Topdesk\TopdeskSettings;
use Modules\HostFlow\Lib\Topdesk\ZabbixExport;
use RuntimeException;
use Throwable;

/**
 * Abre um chamado no TOPdesk para cada envio válido:
 *  - título "[CLIENTE] - Nova solicitação - <formulário>";
 *  - solicitante = e-mail do usuário do Zabbix que preencheu (ou o solicitante padrão da configuração);
 *  - classificação (tipo, categoria, impacto, urgência, prioridade, grupo/operador, SLA, contrato) da configuração;
 *  - ação oculta para o solicitante com o JSON da solicitação;
 *  - em formulários de criação, anexo oculto com o arquivo de importação do host no Zabbix.
 *
 * Ativado em "Solicitações › Integração TOPdesk".
 */
final class TopdeskSubmitHandler implements SubmitHandler {

	private const BRIEF_MAX = 80; // limite do TOPdesk para briefDescription
	private const SECRET_SNMP_KEYS = ['community', 'authpassphrase', 'privpassphrase'];

	public function handle(array $submission): array {
		$s = TopdeskSettings::load();
		$form = $submission['formulario'];
		$requester = $submission['solicitante'];

		$email = trim((string) ($requester['email'] ?? ''));
		$email = ($email !== '') ? $email : trim($s['solicitante_padrao']);

		if ($email === '') {
			return self::fail('Seu usuário do Zabbix não tem e-mail cadastrado (Perfil › Mídias) e não há solicitante '.
				'padrão na configuração do TOPdesk. A solicitação não foi enviada.'
			);
		}

		$title = sprintf('[%s] - Nova solicitação - %s', $s['cliente'], $form['nome']);
		$with_secrets = !empty($s['enviar_segredos']);
		$payload = $with_secrets ? $submission['payload'] : self::maskPayload($submission['payload']);

		$body = [
			'briefDescription' => mb_substr($title, 0, self::BRIEF_MAX),
			'request' => self::requestText($title, $submission),
			'callerLookup' => ['email' => $email],
			'action' => self::actionText($submission, $payload, $email),
			'actionInvisibleForCaller' => true
		];

		foreach (TopdeskSettings::LOOKUPS as $key => [, $api_key]) {
			if (trim((string) $s[$key]) !== '') {
				$body[$api_key] = TopdeskSettings::reference($s[$key]);
			}
		}

		if (trim($s['campos_extras']) !== '') {
			$body = array_replace_recursive($body, (array) json_decode($s['campos_extras'], true));
		}

		$client = TopdeskClient::fromSettings($s);

		try {
			$incident = $client->createIncident($body);
		}
		catch (RuntimeException $e) {
			// E-mail sem cadastro de pessoa no TOPdesk: registra como solicitante não cadastrado.
			if (stripos($e->getMessage(), 'caller') === false) {
				throw $e;
			}

			unset($body['callerLookup']);
			$body['caller'] = ['dynamicName' => self::requesterName($requester, $email), 'email' => $email];
			$incident = $client->createIncident($body);
		}

		$number = (string) ($incident['number'] ?? '');
		$id = (string) ($incident['id'] ?? '');
		$message = 'Chamado aberto no TOPdesk.';

		if ($id !== '' && ($form['tipo'] ?? '') === 'create') {
			$host = (string) ($submission['payload']['host']['host'] ?? 'host');
			$file = 'zabbix-import-'.preg_replace('/[^A-Za-z0-9._-]+/', '_', $host).'.json';
			$json = json_encode(ZabbixExport::build($submission['payload'], $with_secrets),
				JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
			);

			try {
				$client->addAttachment($id, $file, $json."\n", 'application/json', true,
					'Importar em Data collection › Hosts › Import'
				);
				$message .= ' Arquivo de importação do Zabbix anexado.';
			}
			catch (Throwable $e) {
				$message .= ' Atenção: não foi possível anexar o arquivo do Zabbix ('.$e->getMessage().').';
			}
		}

		return ['ok' => true, 'mensagem' => $message, 'referencia' => $number !== '' ? $number : $id];
	}

	private static function fail(string $message): array {
		return ['ok' => false, 'mensagem' => $message, 'referencia' => null];
	}

	private static function requesterName(array $requester, string $email): string {
		$name = trim(($requester['name'] ?? '').' '.($requester['surname'] ?? ''));

		return $name !== '' ? $name : (string) ($requester['username'] ?? $email);
	}

	/**
	 * Texto visível ao solicitante: título, dados informados e justificativa.
	 */
	private static function requestText(string $title, array $submission): string {
		$lines = [$title, ''];

		foreach ($submission['resumo'] as $row) {
			$lines[] = $row['rotulo'].': '.$row['valor'];
		}

		$lines[] = '';
		$lines[] = 'Justificativa:';
		$lines[] = $submission['justificativa'];
		$lines[] = '';
		$lines[] = sprintf('Solicitado por %s via Zabbix HostFlow em %s.',
			self::requesterName($submission['solicitante'], (string) ($submission['solicitante']['email'] ?? '')),
			date('d/m/Y H:i', (int) $submission['enviado_em'])
		);

		return implode("\n", $lines);
	}

	/**
	 * Ação oculta: JSON técnico da solicitação para a equipe que executa.
	 */
	private static function actionText(array $submission, array $payload, string $email): string {
		$form = $submission['formulario'];
		$data = [
			'formulario' => ['id' => $form['id'], 'nome' => $form['nome'], 'tipo' => $form['tipo']],
			'solicitante' => [
				'username' => $submission['solicitante']['username'] ?? null,
				'nome' => self::requesterName($submission['solicitante'], $email),
				'email' => $email
			],
			'enviado_em' => date('c', (int) $submission['enviado_em']),
			'valores' => array_column($submission['resumo'], 'valor', 'campo'),
			'justificativa' => $submission['justificativa'],
			'payload' => $payload,
			'diff' => $submission['diff']
		];

		return "Solicitação HostFlow (JSON):\n\n"
			.json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
	}

	private static function maskPayload(array $payload): array {
		foreach (self::SECRET_SNMP_KEYS as $key) {
			$value = (string) ($payload['interface']['snmp'][$key] ?? '');

			if ($value !== '' && strpos($value, '{$') !== 0) {
				$payload['interface']['snmp'][$key] = ZabbixExport::SECRET_PLACEHOLDER;
			}
		}

		return $payload;
	}
}
