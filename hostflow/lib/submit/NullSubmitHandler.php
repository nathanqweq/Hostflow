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
