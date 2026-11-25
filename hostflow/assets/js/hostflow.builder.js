/*
 * HostFlow: construtor visual de formulários.
 *
 * Mantém a definição em memória (state), redesenha a tela em mudanças estruturais e,
 * ao salvar, serializa tudo no campo oculto "definition". A aba JSON edita a mesma definição.
 * Toda validação definitiva acontece no servidor (FormSchema).
 */
(function () {
	'use strict';

	var root, cfg, state, tab = 'visual', jsonText = '';

	/* ------------------------------------------------------------ helpers */

	function h(tag, props) {
		var el = document.createElement(tag);
		var children = Array.prototype.slice.call(arguments, 2);

		props = props || {};

		Object.keys(props).forEach(function (key) {
			var v = props[key];

			if (v === undefined || v === null) {
				return;
			}

			if (key === 'class') {
				el.className = v;
			}
			else if (key === 'text') {
				el.textContent = v;
			}
			else if (key === 'on') {
				Object.keys(v).forEach(function (ev) {
					el.addEventListener(ev, v[ev]);
				});
			}
			else if (key === 'value') {
				el.value = v;
			}
			else if (key === 'checked' || key === 'disabled' || key === 'selected') {
				el[key] = !!v;
			}
			else {
				el.setAttribute(key, v);
			}
		});

		append(el, children);

		return el;
	}

	function append(el, children) {
		children.forEach(function (child) {
			if (child === null || child === undefined || child === false) {
				return;
			}

			if (Array.isArray(child)) {
				append(el, child);
			}
			else {
				el.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
			}
		});
	}

	function textInput(value, onInput, attrs) {
		return h('input', Object.assign({type: 'text', value: value || '', on: {input: function (e) {
			onInput(e.target.value);
		}}}, attrs || {}));
	}

	function textArea(value, onInput, attrs) {
		return h('textarea', Object.assign({value: value || '', rows: 4, on: {input: function (e) {
			onInput(e.target.value);
		}}}, attrs || {}));
	}

	function checkbox(checked, onChange, label) {
		return h('label', {class: 'hf-b-check'},
			h('input', {type: 'checkbox', checked: checked, on: {change: function (e) {
				onChange(e.target.checked);
			}}}),
			' ' + label
		);
	}

	/* options: [[value, label], ...] */
	function select(value, options, onChange, attrs) {
		var el = h('select', Object.assign({on: {change: function (e) {
			onChange(e.target.value);
		}}}, attrs || {}));

		options.forEach(function (opt) {
			el.appendChild(h('option', {value: opt[0], text: opt[1], selected: String(opt[0]) === String(value)}));
		});

		return el;
	}

	function prop(label, control, hint, cls) {
		return h('div', {class: 'hf-b-prop' + (cls ? ' ' + cls : '')},
			h('label', {class: 'hf-b-label', text: label}),
			control,
			hint ? h('div', {class: 'hf-b-hint', text: hint}) : null
		);
	}

	function button(text, onClick, cls, title) {
		return h('button', {type: 'button', class: cls || 'btn-alt', text: text, title: title || null,
			on: {click: function (e) {
				e.preventDefault();
				onClick();
			}}
		});
	}

	function entries(obj) {
		return Object.keys(obj).map(function (k) {
			return [k, obj[k]];
		});
	}

	function inArray(v, arr) {
		return arr.indexOf(v) !== -1;
	}

	function move(arr, i, delta) {
		var j = i + delta;

		if (j < 0 || j >= arr.length) {
			return;
		}

		var tmp = arr[i];
		arr[i] = arr[j];
		arr[j] = tmp;
	}

	/* ------------------------------------------------------------ conversões */

	function optionsToText(opcoes) {
		return (opcoes || []).map(function (o) {
			return (o.rotulo && o.rotulo !== o.valor) ? o.valor + ' | ' + o.rotulo : o.valor;
		}).join('\n');
	}

	function textToOptions(text) {
		return text.split(/\r?\n/).map(function (line) {
			var parts = line.split('|');
			var valor = (parts[0] || '').trim();
			var rotulo = parts.slice(1).join('|').trim();

			return {valor: valor, rotulo: rotulo || valor};
		}).filter(function (o) {
			return o.valor !== '';
		});
	}

	function linesToList(text) {
		return text.split(/\r?\n/).map(function (s) {
			return s.trim();
		}).filter(Boolean);
	}

	function splitTarget(alvo) {
		alvo = alvo || '';

		var prefixes = Object.keys(cfg.target_prefixes);

		for (var i = 0; i < prefixes.length; i++) {
			if (alvo.indexOf(prefixes[i]) === 0) {
				return {base: prefixes[i], name: alvo.substring(prefixes[i].length)};
			}
		}

		return {base: alvo, name: ''};
	}

	/* ------------------------------------------------------------ editores reutilizáveis */

	/* Alvo do mapeamento: alvo fixo, ou prefixo + nome (tag:, macro:, inventory.). */
	function targetEditor(map) {
		var t = splitTarget(map.alvo);
		var opts = [['', '— alvo —']];

		entries(cfg.targets).forEach(function (e) {
			opts.push([e[0], e[0] + '  ·  ' + e[1]]);
		});

		entries(cfg.target_prefixes).forEach(function (e) {
			opts.push([e[0], e[0] + '<nome>  ·  ' + e[1]]);
		});

		var wrap = h('div', {class: 'hf-b-target'});

		wrap.appendChild(select(t.base, opts, function (v) {
			map.alvo = (v in cfg.target_prefixes) ? v + (splitTarget(map.alvo).base === v ? t.name : '') : v;

			if (v !== 'groups[]' && v !== 'templates[]') {
				delete map.modo;
				delete map.prefixo;
			}

			render();
		}, {class: 'hf-b-target-base'}));

		if (t.base in cfg.target_prefixes) {
			if (t.base === 'inventory.' && cfg.inventory_fields.length) {
				wrap.appendChild(select(t.name, [['', '— campo —']].concat(cfg.inventory_fields.map(function (f) {
					return [f, f];
				})), function (v) {
					map.alvo = t.base + v;
				}));
			}
			else {
				wrap.appendChild(textInput(t.name, function (v) {
					map.alvo = t.base + v;
				}, {placeholder: t.base === 'macro:' ? '{$NOME}' : 'NOME', class: 'hf-b-target-name'}));
			}
		}

		return wrap;
	}

	function modeEditor(map) {
		var base = splitTarget(map.alvo).base;

		if (base === 'groups[]') {
			return h('div', {class: 'hf-b-mode'},
				select(map.modo || 'adicionar', cfg.group_modes.map(function (m) {
					return [m, m === 'adicionar' ? 'adicionar ao host' : 'substituir grupos com prefixo'];
				}), function (v) {
					map.modo = v;
					render();
				}),
				(map.modo === 'substituir_prefixo')
					? textInput(map.prefixo, function (v) {
						map.prefixo = v;
					}, {placeholder: 'Sites/'})
					: null
			);
		}

		if (base === 'templates[]') {
			return h('div', {class: 'hf-b-mode'},
				select(map.modo || 'vincular', cfg.template_modes.map(function (m) {
					return [m, m];
				}), function (v) {
					map.modo = v;
				})
			);
		}

		return h('div', {class: 'hf-b-mode hf-b-muted', text: '—'});
	}

	/*
	 * Condição: {logica: "e"|"ou", regras: [{campo, operador: "igual"|"diferente", valores: [...]}]}.
	 * Aceita o formato antigo {campo, igual} e converte.
	 */
	function normalizeCondition(cond) {
		if (!cond || typeof cond !== 'object') {
			return null;
		}

		if ('campo' in cond) {
			return cond.campo ? {logica: 'e', regras: [{campo: cond.campo, operador: 'igual',
				valores: [String(cond.igual || '')]}]} : null;
		}

		if (!Array.isArray(cond.regras) || !cond.regras.length) {
			return null;
		}

		cond.logica = cond.logica === 'ou' ? 'ou' : 'e';
		cond.regras.forEach(function (r) {
			r.operador = r.operador === 'diferente' ? 'diferente' : 'igual';
			r.valores = Array.isArray(r.valores) ? r.valores : [];
		});

		return cond;
	}

	/* Valores possíveis do campo referenciado, quando ele tem lista fechada. */
	function knownValues(fieldId) {
		var f = state.campos.filter(function (c) {
			return c.id === fieldId;
		})[0];

		if (!f) {
			return null;
		}

		if (f.tipo === 'checkbox') {
			return [['1', 'marcado'], ['0', 'desmarcado']];
		}

		if (!inArray(f.tipo, cfg.option_types)) {
			return null;
		}

		if (f.lista) {
			var list = cfg.lists.filter(function (l) {
				return l.id === f.lista;
			})[0];

			return list ? list.itens : null;
		}

		return (f.opcoes || []).map(function (o) {
			return [o.valor, o.rotulo || o.valor];
		});
	}

	function valuesEditor(rule) {
		var known = rule.campo ? knownValues(rule.campo) : null;

		if (known && known.length) {
			var box = h('div', {class: 'hf-b-vals'});

			known.forEach(function (opt) {
				box.appendChild(checkbox(inArray(opt[0], rule.valores), function (on) {
					rule.valores = rule.valores.filter(function (v) {
						return v !== opt[0];
					});

					if (on) {
						rule.valores.push(opt[0]);
					}
				}, opt[1]));
			});

			return box;
		}

		return textInput(rule.valores.join(', '), function (v) {
			rule.valores = v.split(',').map(function (s) {
				return s.trim();
			}).filter(Boolean);
		}, {placeholder: 'valor1, valor2', class: 'hf-b-vals-text'});
	}

	function conditionEditor(owner, selfId) {
		var cond = normalizeCondition(owner.quando);
		owner.quando = cond;

		var fieldOpts = [['', '— campo —']].concat(state.campos.filter(function (f) {
			return f.id && f.id !== selfId;
		}).map(function (f) {
			return [f.id, f.id + (f.rotulo ? ' (' + f.rotulo + ')' : '')];
		}));

		function newRule() {
			return {campo: '', operador: 'igual', valores: []};
		}

		if (!cond) {
			return h('div', {class: 'hf-b-cond'},
				h('span', {class: 'hf-b-muted', text: 'Sempre '}),
				button('+ condição', function () {
					owner.quando = {logica: 'e', regras: [newRule()]};
					render();
				})
			);
		}

		var rows = cond.regras.map(function (rule, k) {
			return h('div', {class: 'hf-b-rule'},
				(k === 0)
					? h('span', {class: 'hf-b-rule-logic', text: 'Se'})
					: select(cond.logica, [['e', 'E'], ['ou', 'OU']], function (v) {
						cond.logica = v;
						render();
					}, {class: 'hf-b-rule-logic', title: 'Vale para todas as regras desta condição'}),
				select(rule.campo, fieldOpts, function (v) {
					rule.campo = v;
					rule.valores = [];
					render();
				}),
				select(rule.operador, [['igual', 'for igual a'], ['diferente', 'for diferente de']], function (v) {
					rule.operador = v;
				}),
				valuesEditor(rule),
				button('✕', function () {
					cond.regras.splice(k, 1);

					if (!cond.regras.length) {
						owner.quando = null;
					}

					render();
				}, 'btn-alt hf-b-icon', 'Remover regra')
			);
		});

		return h('div', {class: 'hf-b-cond hf-b-cond-rules'},
			rows,
			h('div', {class: 'hf-b-cond-foot'},
				button('+ regra', function () {
					cond.regras.push(newRule());
					render();
				}),
				(cond.regras.length > 1)
					? h('span', {class: 'hf-b-hint', text: cond.logica === 'ou'
						? 'OU: basta uma regra ser verdadeira.'
						: 'E: todas as regras precisam ser verdadeiras.'})
					: h('span', {class: 'hf-b-hint', text: 'Marque vários valores para "qualquer um destes".'})
			)
		);
	}

	/* ------------------------------------------------------------ campo */

	function fieldCard(field, i) {
		var type = field.tipo;
		var isText = inArray(type, cfg.text_types);
		var isOption = inArray(type, cfg.option_types);
		var isAllowed = inArray(type, cfg.allowed_types);
		var isMultiCap = inArray(type, cfg.multi_capable);

		field.mapeamento = field.mapeamento || [];

		var typeOpts = entries(cfg.field_types);
		var listOpts = [['', '— opções próprias (abaixo) —']].concat(cfg.lists.map(function (l) {
			return [l.id, l.nome + ' (' + l.id + ')'];
		}));

		var header = h('div', {class: 'hf-b-card-head'},
			h('span', {class: 'hf-b-card-num', text: '#' + (i + 1)}),
			h('strong', {text: field.rotulo || '(sem rótulo)'}),
			h('span', {class: 'hf-b-muted', text: ' · ' + (cfg.field_types[type] || type) + (field.id ? ' · ' + field.id : '')}),
			h('span', {class: 'hf-b-spacer'}),
			button('↑', function () { move(state.campos, i, -1); render(); }, 'btn-alt hf-b-icon', 'Subir'),
			button('↓', function () { move(state.campos, i, 1); render(); }, 'btn-alt hf-b-icon', 'Descer'),
			button('Duplicar', function () {
				var copy = JSON.parse(JSON.stringify(field));
				copy.id = (copy.id || 'campo') + '_2';
				state.campos.splice(i + 1, 0, copy);
				render();
			}, 'btn-alt'),
			button('Remover', function () {
				if (window.confirm('Remover o campo "' + (field.rotulo || field.id) + '"?')) {
					state.campos.splice(i, 1);
					render();
				}
			}, 'btn-alt hf-b-danger')
		);

		var body = h('div', {class: 'hf-b-card-body'},
			h('div', {class: 'hf-b-row'},
				prop('ID', textInput(field.id, function (v) { field.id = v; }, {placeholder: 'ex.: site'}),
					'a-z, 0-9 e _. Usado em padrões: {id}'),
				prop('Rótulo', textInput(field.rotulo, function (v) { field.rotulo = v; })),
				prop('Tipo', select(type, typeOpts, function (v) {
					field.tipo = v;

					if (v === 'zbx_host' && !field.mapeamento.length) {
						field.mapeamento.push({alvo: 'hostid', padrao: ''});
					}

					if (v === 'tag_value' && !field.tag) {
						field.tag = '';
					}

					render();
				}))
			),
			h('div', {class: 'hf-b-row'},
				prop('', checkbox(field.obrigatorio, function (v) { field.obrigatorio = v; }, 'Obrigatório')),
				prop('Ajuda', textInput(field.ajuda, function (v) { field.ajuda = v; }), null, 'hf-b-grow'),
				(type !== 'zbx_host')
					? prop('Valor padrão', textInput(field.valor_padrao, function (v) { field.valor_padrao = v; }))
					: null
			),
			isText ? h('div', {class: 'hf-b-row'},
				prop('Regex (opcional)', textInput(field.regex, function (v) { field.regex = v; },
					{placeholder: '^SW-[A-Z0-9_-]+$', class: 'hf-mono'}), 'Sem delimitadores. Aplicada no servidor.', 'hf-b-grow')
			) : null,
			(type === 'tag_value') ? h('div', {class: 'hf-b-row'},
				prop('Nome da tag', textInput(field.tag, function (v) { field.tag = v; }, {placeholder: 'ex.: ambiente'}),
					'Sem mapeamento explícito, o valor vai para tag:<nome>.')
			) : null,
			isOption ? h('div', {class: 'hf-b-row'},
				prop('Lista compartilhada', select(field.lista || '', listOpts, function (v) {
					field.lista = v;
					render();
				}), 'Listas permitem usar atributos: {' + (field.id || 'campo') + '.atributo}'),
				!field.lista ? prop('Opções', textArea(optionsToText(field.opcoes), function (v) {
					field.opcoes = textToOptions(v);
				}, {class: 'hf-mono', rows: 5, placeholder: 'VALOR | Rótulo'}), 'Uma por linha: VALOR | Rótulo', 'hf-b-grow') : null
			) : null,
			(type === 'zbx_hostgroup') ? h('div', {class: 'hf-b-row'},
				prop('Prefixo dos grupos', textInput(field.prefixo, function (v) { field.prefixo = v; },
					{placeholder: 'ex.: Sites/'}), 'Só grupos com este prefixo, que o usuário enxerga.', 'hf-b-grow')
			) : null,
			isAllowed ? h('div', {class: 'hf-b-row'},
				prop('Permitidos', textArea((field.permitidos || []).join('\n'), function (v) {
					field.permitidos = linesToList(v);
				}, {class: 'hf-mono', rows: 4}),
				'Um nome por linha. Recomendado: usuários comuns podem não enxergar templates/proxies.'
					+ (type === 'zbx_proxy' || type === 'zbx_proxy_group' ? ' Vazio = todos.' : ''), 'hf-b-grow'),
				(type === 'zbx_template') ? prop('ou grupo de templates', textInput(field.grupo_templates, function (v) {
					field.grupo_templates = v;
				}, {placeholder: 'Templates/Network devices'}), 'Usado se "Permitidos" estiver vazio.') : null
			) : null,
			isMultiCap ? h('div', {class: 'hf-b-row'},
				prop('', checkbox(field.multiplo, function (v) { field.multiplo = v; }, 'Permitir vários valores'))
			) : null,
			h('div', {class: 'hf-b-row'},
				prop('Exibir quando', conditionEditor(field, field.id), null, 'hf-b-grow')
			),
			mappingTable(field)
		);

		return h('div', {class: 'hf-b-card'}, header, body);
	}

	function mappingTable(field) {
		var rows = field.mapeamento.map(function (map, j) {
			return h('tr', null,
				h('td', null, targetEditor(map)),
				h('td', null, textInput(map.padrao, function (v) { map.padrao = v; },
					{placeholder: 'vazio = o próprio valor', class: 'hf-mono'})),
				h('td', null, modeEditor(map)),
				h('td', null, button('✕', function () {
					field.mapeamento.splice(j, 1);
					render();
				}, 'btn-alt hf-b-icon', 'Remover mapeamento'))
			);
		});

		return h('div', {class: 'hf-b-maps'},
			h('div', {class: 'hf-b-label', text: 'Mapeamento: em que atributo(s) do host este valor vira'}),
			h('table', {class: 'hf-b-table'},
				h('thead', null, h('tr', null,
					h('th', {text: 'Alvo'}), h('th', {text: 'Padrão (opcional)'}), h('th', {text: 'Modo'}), h('th')
				)),
				h('tbody', null, rows.length ? rows : h('tr', null, h('td', {colspan: 4, class: 'hf-b-muted',
					text: 'Sem mapeamento: o valor só aparece no resumo da solicitação.'})))
			),
			button('+ mapeamento', function () {
				field.mapeamento.push({alvo: '', padrao: ''});
				render();
			})
		);
	}

	/* ------------------------------------------------------------ valores fixos */

	function fixedSection() {
		state.valores_fixos = state.valores_fixos || [];

		var rows = state.valores_fixos.map(function (fixed, j) {
			return h('tr', null,
				h('td', null, targetEditor(fixed)),
				h('td', null, textInput(fixed.valor, function (v) { fixed.valor = v; },
					{placeholder: 'ex.: producao ou {site}', class: 'hf-mono'})),
				h('td', null, modeEditor(fixed)),
				h('td', null, conditionEditor(fixed, null)),
				h('td', null, button('✕', function () {
					state.valores_fixos.splice(j, 1);
					render();
				}, 'btn-alt hf-b-icon', 'Remover'))
			);
		});

		return h('section', {class: 'hf-b-section'},
			h('h4', {text: 'Valores fixos'}),
			h('div', {class: 'hf-b-hint', text: 'Aplicados sem perguntar ao usuário (ex.: proxy, template ou tag '
				+ 'sempre iguais para este formulário). Aceitam {campo} e condição.'}),
			h('table', {class: 'hf-b-table'},
				h('thead', null, h('tr', null,
					h('th', {text: 'Alvo'}), h('th', {text: 'Valor'}), h('th', {text: 'Modo'}),
					h('th', {text: 'Aplicar quando'}), h('th')
				)),
				h('tbody', null, rows.length ? rows : h('tr', null, h('td', {colspan: 5, class: 'hf-b-muted',
					text: 'Nenhum valor fixo.'})))
			),
			button('+ valor fixo', function () {
				state.valores_fixos.push({alvo: '', valor: ''});
				render();
			})
		);
	}

	/* ------------------------------------------------------------ tela */

	function ensureHostField() {
		if (state.tipo === 'create') {
			return;
		}

		var has = state.campos.some(function (f) {
			return f.tipo === 'zbx_host';
		});

		if (!has) {
			state.campos.unshift({
				id: 'host', rotulo: 'Host', tipo: 'zbx_host', obrigatorio: true, ajuda: '',
				quando: null, mapeamento: [{alvo: 'hostid', padrao: ''}]
			});
		}
	}

	function metaSection() {
		return h('section', {class: 'hf-b-section'},
			h('div', {class: 'hf-b-row'},
				prop('ID do formulário', textInput(state.id, function (v) { state.id = v; },
					{placeholder: 'novo-switch'}), 'Minúsculas, números, - e _'),
				prop('Nome', textInput(state.nome, function (v) { state.nome = v; }), null, 'hf-b-grow'),
				prop('Tipo', select(state.tipo, entries(cfg.form_types), function (v) {
					state.tipo = v;
					ensureHostField();
					render();
				}))
			),
			h('div', {class: 'hf-b-row'},
				prop('Descrição', textInput(state.descricao, function (v) { state.descricao = v; }), null, 'hf-b-grow'),
				prop('Equipe responsável', textInput(state.equipe_responsavel, function (v) {
					state.equipe_responsavel = v;
				}, {placeholder: 'ex.: Equipe de redes'}), 'Destino do chamado na integração com o sistema de chamados.'),
				prop('', checkbox(state.ativo !== false, function (v) { state.ativo = v; }, 'Ativo (visível aos usuários)'))
			)
		);
	}

	function helpSection() {
		return h('details', {class: 'hf-b-help'},
			h('summary', {text: 'Como funcionam padrões e mapeamentos'}),
			h('ul', null,
				h('li', {text: 'Padrão vazio: o valor do campo vai direto para o alvo.'}),
				h('li', {text: 'Padrão com {campo}: monta o valor com outros campos. Ex.: Sites/{site.regiao}/{site}/{funcao}.'}),
				h('li', {text: '{campo.atributo} lê um atributo do item escolhido numa lista compartilhada.'}),
				h('li', {text: 'Se algum placeholder ficar vazio, aquele mapeamento é ignorado (nunca gera "A//B").'}),
				h('li', {text: 'Um campo pode ter vários mapeamentos: "Site" pode gerar o grupo e a tag site.'}),
				h('li', {text: 'Grupos: "substituir grupos com prefixo" troca só os grupos daquele ramo (movimentação).'}),
				h('li', {text: 'Em alteração, campos deixados vazios não mudam nada no host.'})
			)
		);
	}

	function render() {
		root.textContent = '';

		var tabs = h('div', {class: 'hf-b-tabs'},
			button('Construtor visual', function () { switchTab('visual'); },
				tab === 'visual' ? 'btn hf-b-tab-on' : 'btn-alt'),
			button('JSON', function () { switchTab('json'); }, tab === 'json' ? 'btn hf-b-tab-on' : 'btn-alt')
		);

		root.appendChild(tabs);

		if (tab === 'json') {
			root.appendChild(h('div', {class: 'hf-b-hint', text: 'Edite ou cole uma definição. Ela passa pela mesma '
				+ 'validação do construtor ao salvar.'}));
			root.appendChild(h('textarea', {id: 'hf-b-json', class: 'hf-mono hf-b-json', value: jsonText, spellcheck: 'false',
				on: {input: function (e) { jsonText = e.target.value; }}}));

			return;
		}

		root.appendChild(metaSection());

		var fields = h('section', {class: 'hf-b-section'}, h('h4', {text: 'Campos'}));

		state.campos.forEach(function (field, i) {
			fields.appendChild(fieldCard(field, i));
		});

		fields.appendChild(button('+ campo', function () {
			state.campos.push({id: '', rotulo: '', tipo: 'text', obrigatorio: false, ajuda: '', valor_padrao: '',
				regex: '', quando: null, mapeamento: []});
			render();
		}));

		root.appendChild(fields);
		root.appendChild(fixedSection());
		root.appendChild(helpSection());
	}

	function switchTab(next) {
		if (next === tab) {
			return;
		}

		if (next === 'json') {
			jsonText = JSON.stringify(state, null, 2);
			tab = 'json';
			render();

			return;
		}

		try {
			loadState(JSON.parse(jsonText));
			tab = 'visual';
			render();
		}
		catch (e) {
			window.alert('JSON inválido: ' + e.message);
		}
	}

	function loadState(def) {
		if (!def || typeof def !== 'object' || Array.isArray(def)) {
			throw new Error('a definição deve ser um objeto.');
		}

		def.campos = Array.isArray(def.campos) ? def.campos : [];
		def.valores_fixos = Array.isArray(def.valores_fixos) ? def.valores_fixos : [];
		state = def;
	}

	function init() {
		root = document.getElementById('hf-builder');

		if (!root) {
			return;
		}

		cfg = JSON.parse(root.getAttribute('data-config'));
		loadState(JSON.parse(root.getAttribute('data-definition')));

		var raw = root.getAttribute('data-raw');

		if (raw) {
			tab = 'json';
			jsonText = raw;
		}

		// Na aba JSON envia o texto como está: se for inválido, o servidor devolve o erro e preserva o texto.
		document.getElementById('hf-builder-form').addEventListener('submit', function () {
			document.getElementById('hf-definition').value = (tab === 'json') ? jsonText : JSON.stringify(state);
		});

		render();
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', init);
	}
	else {
		init();
	}
})();
