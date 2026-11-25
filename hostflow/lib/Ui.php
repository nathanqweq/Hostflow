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
