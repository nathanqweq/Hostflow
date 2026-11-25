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
