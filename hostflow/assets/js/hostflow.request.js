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
