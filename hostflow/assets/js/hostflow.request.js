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

	/*
	 * Condição: {logica: "e"|"ou", regras: [{campo, operador: "igual"|"diferente", valores: [...]}]}.
	 * Mesma semântica de Submission::conditionMet(): "igual" = tem algum dos valores; "diferente" = não tem
	 * nenhum. Um campo oculto conta como vazio para quem depende dele.
	 */
	function initConditions(form) {
		var conditional = form.querySelectorAll('[data-hf-when]');

		if (!conditional.length) {
			return;
		}

		var conditions = {};

		conditional.forEach(function (el) {
			try {
				conditions[el.getAttribute('data-hf-field')] = JSON.parse(el.getAttribute('data-hf-when'));
			}
			catch (e) {
				// condição ilegível: o campo fica visível e o servidor decide.
			}
		});

		function isVisible(id, stack) {
			var cond = conditions[id];

			if (!cond || !cond.regras || !cond.regras.length) {
				return true;
			}

			if (stack.indexOf(id) !== -1) {
				return false; // ciclo: o servidor já impede, mas por segurança.
			}

			var next = stack.concat([id]);

			var results = cond.regras.map(function (rule) {
				var current = isVisible(rule.campo, next) ? valuesOf(form, rule.campo) : [];
				var hit = current.some(function (v) {
					return rule.valores.indexOf(v) !== -1;
				});

				return rule.operador === 'diferente' ? !hit : hit;
			});

			return cond.logica === 'ou'
				? results.indexOf(true) !== -1
				: results.indexOf(false) === -1;
		}

		function apply() {
			conditional.forEach(function (el) {
				el.classList.toggle('hf-hidden', !isVisible(el.getAttribute('data-hf-field'), []));
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
