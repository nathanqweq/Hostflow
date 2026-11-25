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
