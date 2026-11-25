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
