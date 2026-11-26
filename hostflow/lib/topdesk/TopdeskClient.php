<?php declare(strict_types = 0);

namespace Modules\HostFlow\Lib\Topdesk;

use RuntimeException;

/**
 * Cliente mínimo da API REST do TOPdesk (/tas/api), autenticado por usuário + application password.
 */
final class TopdeskClient {

	private string $base;
	private string $auth;
	private bool $verify_ssl;

	public function __construct(string $url, string $user, string $password, bool $verify_ssl = true) {
		if (!function_exists('curl_init')) {
			throw new RuntimeException('A extensão PHP "curl" não está instalada no servidor do frontend.');
		}

		$this->base = rtrim($url, '/');
		$this->auth = $user.':'.$password;
		$this->verify_ssl = $verify_ssl;
	}

	public static function fromSettings(array $s): self {
		return new self($s['url'], $s['usuario'], $s['senha'], !empty($s['verificar_ssl']));
	}

	public function baseUrl(): string {
		return $this->base;
	}

	/**
	 * @return array  incidente criado (inclui "id" e "number")
	 */
	public function createIncident(array $body): array {
		return $this->json('POST', '/tas/api/incidents', $body);
	}

	/**
	 * Anexa um arquivo ao chamado. $invisible = oculto para o solicitante.
	 */
	public function addAttachment(string $incident_id, string $filename, string $content, string $mime,
			bool $invisible, string $description = ''): array {
		$query = http_build_query(['invisibleForCaller' => $invisible ? 'true' : 'false', 'description' => $description]);
		$boundary = '----hostflow'.bin2hex(random_bytes(8));
		$safe_name = str_replace(['"', "\r", "\n"], '_', $filename);

		$body = '--'.$boundary."\r\n"
			.'Content-Disposition: form-data; name="file"; filename="'.$safe_name.'"'."\r\n"
			.'Content-Type: '.$mime."\r\n\r\n"
			.$content."\r\n"
			.'--'.$boundary."--\r\n";

		return $this->request('POST', '/tas/api/incidents/id/'.rawurlencode($incident_id).'/attachments?'.$query,
			$body, 'multipart/form-data; boundary='.$boundary
		);
	}

	/**
	 * Testa endereço e credenciais. Retorna a versão do TOPdesk e quantos tipos de chamado o usuário enxerga.
	 */
	public function test(): string {
		$version = $this->json('GET', '/tas/api/version');
		$call_types = $this->json('GET', '/tas/api/incidents/call_types');

		return sprintf('Conectado ao TOPdesk %s. Tipos de chamado visíveis: %d.',
			$version['version'] ?? '?', is_array($call_types) ? count($call_types) : 0
		);
	}

	private function json(string $method, string $path, ?array $body = null): array {
		$payload = ($body === null)
			? null
			: json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

		return $this->request($method, $path, $payload, 'application/json');
	}

	private function request(string $method, string $path, ?string $body, string $content_type): array {
		$ch = curl_init($this->base.$path);
		$headers = ['Accept: application/json'];

		if ($body !== null) {
			$headers[] = 'Content-Type: '.$content_type;
		}

		curl_setopt_array($ch, [
			CURLOPT_CUSTOMREQUEST => $method,
			CURLOPT_RETURNTRANSFER => true,
			CURLOPT_HTTPAUTH => CURLAUTH_BASIC,
			CURLOPT_USERPWD => $this->auth,
			CURLOPT_HTTPHEADER => $headers,
			CURLOPT_CONNECTTIMEOUT => 10,
			CURLOPT_TIMEOUT => 30,
			CURLOPT_SSL_VERIFYPEER => $this->verify_ssl,
			CURLOPT_SSL_VERIFYHOST => $this->verify_ssl ? 2 : 0,
			CURLOPT_FOLLOWLOCATION => false
		]);

		if ($body !== null) {
			curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
		}

		$raw = curl_exec($ch);
		$status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
		$error = curl_error($ch);
		curl_close($ch);

		if ($raw === false) {
			throw new RuntimeException('TOPdesk inacessível: '.$error);
		}

		$data = json_decode((string) $raw, true);

		if ($status < 200 || $status >= 300) {
			throw new RuntimeException(sprintf('TOPdesk respondeu HTTP %d em %s %s: %s', $status, $method,
				strtok($path, '?'), self::errorText($status, $data, (string) $raw)
			));
		}

		return is_array($data) ? $data : [];
	}

	/**
	 * O TOPdesk devolve erros como [{"message": "..."}] ou {"errors": [...]}.
	 */
	private static function errorText(int $status, $data, string $raw): string {
		if ($status === 401) {
			return 'usuário ou application password inválidos.';
		}

		if ($status === 403) {
			return 'o usuário da API não tem permissão para esta operação.';
		}

		$messages = [];

		foreach ((array) (is_array($data) && isset($data['errors']) ? $data['errors'] : $data) as $item) {
			if (is_array($item) && isset($item['message'])) {
				$messages[] = $item['message'];
			}
			elseif (is_string($item)) {
				$messages[] = $item;
			}
		}

		return $messages ? implode(' | ', $messages) : mb_substr(trim(strip_tags($raw)), 0, 300);
	}
}
