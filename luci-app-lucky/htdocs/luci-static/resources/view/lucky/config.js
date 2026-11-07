'use strict';
'require view';
'require dom';
'require fs';
'require poll';
'require rpc';
'require uci';
'require ui';
'require form';

var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

var STYLE_CSS = [
	'.lucky-panel { margin-bottom: 18px; }',
	'.lucky-inline { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; min-height: 30px; }',
	'.lucky-badge {',
	'	display: inline-flex; align-items: center; padding: 3px 10px; border-radius: 999px;',
	'	font-weight: 600; font-size: 12px; line-height: 1.4; border: 1px solid transparent;',
	'}',
	'.lucky-badge.success { background: rgba(40, 167, 69, 0.15); color: #2fb344; border-color: rgba(40, 167, 69, 0.35); }',
	'.lucky-badge.danger { background: rgba(220, 53, 69, 0.15); color: #e03131; border-color: rgba(220, 53, 69, 0.35); }',
	'.lucky-badge.secondary { background: rgba(108, 117, 125, 0.15); color: inherit; opacity: 0.85; border-color: rgba(108, 117, 125, 0.3); }',
	'.lucky-val-text { font-weight: 600; }',
	'.lucky-code-chip {',
	'	font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;',
	'	padding: 3px 10px; border-radius: 4px; font-size: 13px; font-weight: 600;',
	'	background: rgba(127, 127, 127, 0.12); border: 1px solid rgba(127, 127, 127, 0.25);',
	'}',
	'.lucky-admin-link {',
	'	display: inline-flex; align-items: center; gap: 6px; padding: 4px 12px;',
	'	border-radius: 5px; font-weight: 600; text-decoration: none !important;',
	'	background: rgba(13, 110, 253, 0.14); color: #2b7de9 !important;',
	'	border: 1px solid rgba(13, 110, 253, 0.35); transition: background 0.15s ease;',
	'}',
	'.lucky-admin-link:hover { background: rgba(13, 110, 253, 0.24); }'
].join('\n');

function getServiceStatus() {
	return L.resolveDefault(callServiceList('lucky'), {}).then(function(res) {
		var instances = res && res.lucky && res.lucky.instances;
		if (!instances)
			return false;
		return Object.keys(instances).some(function(k) {
			return instances[k] && instances[k].running === true;
		});
	});
}

function getFirstSectionId() {
	var sections = uci.sections('lucky', 'lucky');
	if (sections && sections.length > 0)
		return sections[0]['.name'];
	return null;
}

function getConfigDir() {
	var sid = getFirstSectionId();
	var dir = sid ? uci.get('lucky', sid, 'configdir') : null;
	return (dir && dir.trim()) ? dir.trim() : '/etc/config/lucky.daji';
}

function buildAdminUrl(conf) {
	if (!conf)
		return '';
	var isHttps = !!(conf.HttpsEnable || conf.AdminEnableTLS);
	var port = (isHttps && conf.AdminWebListenTLSPort)
		? conf.AdminWebListenTLSPort
		: (conf.AdminWebListenPort || 16601);
	var host = window.location.hostname || '127.0.0.1';
	if (host.indexOf(':') !== -1 && host.charAt(0) !== '[')
		host = '[' + host + ']';
	var safeUrl = conf.SafeURL ? String(conf.SafeURL).trim() : '';
	if (safeUrl && safeUrl.charAt(0) !== '/')
		safeUrl = '/' + safeUrl;
	return (isHttps ? 'https://' : 'http://') + host + ':' + port + safeUrl;
}

function showToast(msg, type) {
	var note = ui.addNotification(null, E('p', {}, msg), type || 'info');
	if ((!type || type === 'info') && note) {
		window.setTimeout(function() {
			if (note && note.parentNode)
				note.parentNode.removeChild(note);
		}, 3500);
	}
}

function setLuckyConf(configDir, key, value) {
	var args = ['-setconf', '-key', key];
	if (value !== '' && value !== null && value !== undefined)
		args.push('-value', String(value));
	args.push('-cd', configDir);

	return fs.exec('/usr/bin/lucky', args).then(function(res) {
		if (!res || res.code !== 0) {
			var errMsg = (res && (res.stderr || res.stdout)) ? (res.stderr || res.stdout).trim() : _('Command execution failed.');
			return Promise.reject(new Error(errMsg));
		}
		return res;
	});
}

function queryLuckyData() {
	var configDir = getConfigDir();

	return Promise.all([
		getServiceStatus(),
		L.resolveDefault(fs.stat('/usr/bin/lucky'), null),
		L.resolveDefault(fs.exec('/usr/bin/luckyarch'), null),
		L.resolveDefault(fs.exec('/usr/bin/lucky', ['-info']), null)
	]).then(function(res) {
		var running = res[0];
		var binStat = res[1];
		var archRes = res[2];
		var infoRes = res[3];
		var arch = (archRes && archRes.code === 0 && archRes.stdout) ? archRes.stdout.trim() : '-';
		var installed = !!(binStat && infoRes && infoRes.code === 0 && infoRes.stdout && infoRes.stdout.trim());

		if (!installed) {
			return {
				running: running,
				installed: false,
				arch: arch,
				detail: null,
				baseConf: null,
				configDir: configDir
			};
		}

		var detail = null;
		try {
			detail = JSON.parse(infoRes.stdout.trim());
		} catch (e) {}

		return L.resolveDefault(
			fs.exec('/usr/bin/lucky', ['-baseConfInfo', '-cd', configDir]),
			null
		).then(function(confRes) {
			var baseConf = null;
			try {
				if (confRes && confRes.code === 0 && confRes.stdout) {
					var parsed = JSON.parse(confRes.stdout.trim());
					baseConf = parsed ? (parsed.BaseConfigure || null) : null;
				}
			} catch (e) {}

			return {
				running: running,
				installed: true,
				arch: arch,
				detail: detail,
				baseConf: baseConf,
				configDir: configDir
			};
		});
	});
}

return view.extend({
	load: function() {
		return uci.load('lucky').then(function() {
			return queryLuckyData();
		});
	},

	render: function(initialState) {
		var self = this;
		var state = initialState || {
			running: false,
			installed: false,
			arch: '-',
			detail: null,
			baseConf: null,
			configDir: '/etc/config/lucky.daji'
		};

		var refs = {
			installStatus: E('div', { 'class': 'lucky-inline' }),
			runStatus: E('div', { 'class': 'lucky-inline' }),
			arch: E('div', { 'class': 'lucky-inline' }),
			version: E('div', { 'class': 'lucky-inline' }),
			compileTime: E('div', { 'class': 'lucky-inline' }),
			adminLink: E('div', { 'class': 'lucky-inline' }),
			loginInfo: E('div', { 'class': 'lucky-inline' }),
			httpPort: E('div', { 'class': 'lucky-inline' }),
			safeUrl: E('div', { 'class': 'lucky-inline' }),
			allowInternet: E('div', { 'class': 'lucky-inline' })
		};

		function refreshAll() {
			return uci.unload('lucky')
				.then(function() { return uci.load('lucky'); })
				.then(function() { return queryLuckyData(); })
				.then(function(nextState) {
					state = nextState;
					renderDashboard();
				});
		}

		function syncEnabledCheckbox(enabledVal) {
			var sid = getFirstSectionId();
			if (!sid)
				return;
			var cb = document.getElementById('cbid.lucky.' + sid + '.enabled');
			if (cb && cb.type === 'checkbox')
				cb.checked = (enabledVal === '1');
		}

		function runServiceAction(action, skipConfirm) {
			var confirmMessages = {
				start: _('Are you sure you want to start the Lucky service?'),
				stop: _('Are you sure you want to stop the Lucky service?'),
				restart: _('Are you sure you want to restart the Lucky service?')
			};

			var execute = function() {
				ui.showModal(_('Applying changes'), [
					E('p', { 'class': 'spinning' }, _('Processing Lucky service action, please wait...'))
				]);

				var sid = getFirstSectionId();
				var enabledTarget = (action === 'stop') ? '0' : '1';
				var uciChain = Promise.resolve();

				if (sid) {
					uci.set('lucky', sid, 'enabled', enabledTarget);
					uciChain = uci.save().then(function() {
						return L.resolveDefault(uci.apply(), null);
					});
				}

				return uciChain
					.then(function() {
						return fs.exec('/etc/init.d/lucky', [action]);
					})
					.then(function() {
						syncEnabledCheckbox(enabledTarget);
						return new Promise(function(resolve) {
							window.setTimeout(resolve, 800);
						});
					})
					.then(function() {
						return refreshAll();
					})
					.then(function() {
						ui.hideModal();
					})
					.catch(function(err) {
						ui.hideModal();
						showToast(_('Service operation failed: ') + (err.message || err), 'danger');
					});
			};

			if (skipConfirm)
				return execute();

			ui.showModal(_('Confirm Operation'), [
				E('p', {}, confirmMessages[action] || _('Confirm action?')),
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'btn',
						'click': ui.hideModal
					}, _('Cancel')),
					' ',
					E('button', {
						'class': 'btn ' + (action === 'stop' ? 'cbi-button-remove' : 'cbi-button-action'),
						'click': function() {
							ui.hideModal();
							execute();
						}
					}, _('Confirm'))
				])
			]);
		}

		function applyConfAndReload(promiseFactory) {
			ui.showModal(_('Saving Configuration'), [
				E('p', { 'class': 'spinning' }, _('Updating Lucky configuration, please wait...'))
			]);

			return promiseFactory()
				.then(function() {
					if (state.running)
						return fs.exec('/etc/init.d/lucky', ['restart']);
					return null;
				})
				.then(function() {
					return new Promise(function(resolve) {
						window.setTimeout(resolve, state.running ? 900 : 200);
					});
				})
				.then(function() {
					return refreshAll();
				})
				.then(function() {
					ui.hideModal();
					showToast(_('Configuration updated successfully.'), 'info');
				})
				.catch(function(err) {
					ui.hideModal();
					showToast(_('Update failed: ') + (err.message || err), 'danger');
				});
		}

		function openPortModal() {
			var curPort = String((state.baseConf && state.baseConf.AdminWebListenPort) || 16601);
			var inputEl = E('input', {
				'type': 'number',
				'class': 'cbi-input-text',
				'min': '1',
				'max': '65535',
				'value': curPort,
				'style': 'width: 100%; max-width: 240px;'
			});
			var errEl = E('div', { 'style': 'color: #e03131; margin-top: 6px; display: none;' });

			var submit = function() {
				var raw = (inputEl.value || '').trim();
				var num = Number(raw);
				if (!/^\d+$/.test(raw) || num < 1 || num > 65535) {
					errEl.textContent = _('Invalid port number. Please enter an integer between 1 and 65535.');
					errEl.style.display = 'block';
					return;
				}
				if (raw === curPort) {
					ui.hideModal();
					return;
				}
				ui.hideModal();
				applyConfAndReload(function() {
					return setLuckyConf(state.configDir, 'AdminWebListenPort', raw);
				});
			};

			inputEl.addEventListener('keydown', function(ev) {
				if (ev.key === 'Enter') {
					ev.preventDefault();
					submit();
				}
			});

			ui.showModal(_('Change Admin Web Port'), [
				E('p', {}, _('Enter a new HTTP/HTTPS listening port (1 - 65535) for the Lucky admin panel:')),
				E('div', { 'style': 'margin: 10px 0;' }, [inputEl, errEl]),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
					' ',
					E('button', { 'class': 'btn cbi-button-positive', 'click': submit }, _('Save'))
				])
			]);
			inputEl.focus();
		}

		function openSafeUrlModal() {
			var curUrl = (state.baseConf && state.baseConf.SafeURL) ? String(state.baseConf.SafeURL) : '';
			var inputEl = E('input', {
				'type': 'text',
				'class': 'cbi-input-text',
				'placeholder': '/lucky',
				'value': curUrl,
				'style': 'width: 100%; max-width: 300px;'
			});
			var errEl = E('div', { 'style': 'color: #e03131; margin-top: 6px; display: none;' });

			var submit = function() {
				var val = (inputEl.value || '').trim();
				if (val !== '' && !/^\/[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=-]*$/.test(val)) {
					errEl.textContent = _('Safe URL must start with "/" and contain only valid URL characters, or be left empty to disable.');
					errEl.style.display = 'block';
					return;
				}
				if (val === curUrl) {
					ui.hideModal();
					return;
				}
				ui.hideModal();
				applyConfAndReload(function() {
					return setLuckyConf(state.configDir, 'SetSafeURL', val);
				});
			};

			inputEl.addEventListener('keydown', function(ev) {
				if (ev.key === 'Enter') {
					ev.preventDefault();
					submit();
				}
			});

			ui.showModal(_('Change Safe URL'), [
				E('p', {}, _('Leave empty to disable Safe URL, or enter a custom entry path starting with "/" (e.g. /lucky):')),
				E('div', { 'style': 'margin: 10px 0;' }, [inputEl, errEl]),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
					' ',
					E('button', { 'class': 'btn cbi-button-positive', 'click': submit }, _('Save'))
				])
			]);
			inputEl.focus();
		}

		function openResetAuthModal() {
			ui.showModal(_('Reset Login Credentials'), [
				E('p', {}, _('Reset both admin account and password to "666"?')),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
					' ',
					E('button', {
						'class': 'btn cbi-button-reset',
						'click': function() {
							ui.hideModal();
							applyConfAndReload(function() {
								return setLuckyConf(state.configDir, 'AdminAccount', '666')
									.then(function() {
										return setLuckyConf(state.configDir, 'AdminPassword', '666');
									});
							});
						}
					}, _('Reset'))
				])
			]);
		}

		function openToggleInternetModal(enable) {
			var promptText = enable
				? _('Are you sure you want to enable external (WAN) access to the Lucky admin panel?')
				: _('Are you sure you want to disable external (WAN) access to the Lucky admin panel?');

			ui.showModal(_('Confirm Operation'), [
				E('p', {}, promptText),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
					' ',
					E('button', {
						'class': 'btn ' + (enable ? 'cbi-button-apply' : 'cbi-button-remove'),
						'click': function() {
							ui.hideModal();
							applyConfAndReload(function() {
								return setLuckyConf(state.configDir, 'AllowInternetaccess', enable ? 'true' : 'false');
							});
						}
					}, _('Confirm'))
				])
			]);
		}

		function renderRunStatusAndLink() {
			if (!state.installed) {
				dom.content(refs.runStatus, E('span', { 'class': 'lucky-badge danger' }, _('Not installed')));
				dom.content(refs.adminLink, E('span', { 'class': 'lucky-badge secondary' }, _('Not available')));
				return;
			}

			if (state.running) {
				dom.content(refs.runStatus, [
					E('span', { 'class': 'lucky-badge success' }, _('The Lucky service is running.')),
					E('button', {
						'type': 'button',
						'class': 'btn cbi-button cbi-button-reload',
						'click': function() { runServiceAction('restart', false); }
					}, _('Restart')),
					E('button', {
						'type': 'button',
						'class': 'btn cbi-button cbi-button-remove',
						'click': function() { runServiceAction('stop', false); }
					}, _('Stop'))
				]);

				var adminUrl = buildAdminUrl(state.baseConf || {});
				dom.content(refs.adminLink, E('a', {
					'class': 'lucky-admin-link',
					'href': adminUrl,
					'target': '_blank',
					'rel': 'noopener noreferrer'
				}, [
					adminUrl,
					E('span', { 'aria-hidden': 'true' }, '↗')
				]));
			} else {
				dom.content(refs.runStatus, [
					E('span', { 'class': 'lucky-badge danger' }, _('The Lucky service is not running.')),
					E('button', {
						'type': 'button',
						'class': 'btn cbi-button cbi-button-apply',
						'click': function() { runServiceAction('start', false); }
					}, _('Start'))
				]);
				dom.content(refs.adminLink, E('span', { 'class': 'lucky-badge danger' }, _('Service is stopped')));
			}
		}

		function renderDashboard() {
			dom.content(refs.arch, E('span', { 'class': 'lucky-val-text' }, state.arch || '-'));

			var latestBtn = E('button', {
				'type': 'button',
				'class': 'btn cbi-button cbi-button-action',
				'click': function() {
					window.open('https://release.66666.host/', '_blank', 'noopener,noreferrer');
				}
			}, _('Check Latest Version'));

			if (!state.installed) {
				var notInst = function() {
					return E('span', { 'class': 'lucky-badge danger' }, _('Not installed'));
				};
				dom.content(refs.installStatus, notInst());
				dom.content(refs.version, [notInst(), latestBtn]);
				dom.content(refs.compileTime, notInst());
				dom.content(refs.loginInfo, notInst());
				dom.content(refs.httpPort, notInst());
				dom.content(refs.safeUrl, notInst());
				dom.content(refs.allowInternet, notInst());
				renderRunStatusAndLink();
				return;
			}

			var detail = state.detail || {};
			var conf = state.baseConf || {};

			dom.content(refs.installStatus, E('span', { 'class': 'lucky-badge success' }, _('Installed')));
			dom.content(refs.version, [
				E('span', { 'class': 'lucky-val-text' }, detail.Version || '-'),
				latestBtn
			]);
			dom.content(refs.compileTime, E('span', { 'class': 'lucky-val-text' }, detail.Date || '-'));

			dom.content(refs.loginInfo, [
				E('span', { 'class': 'lucky-val-text' }, _('Default Auth') + ': '),
				E('span', { 'class': 'lucky-code-chip' }, '666 / 666'),
				E('button', {
					'type': 'button',
					'class': 'btn cbi-button cbi-button-reset',
					'click': openResetAuthModal
				}, _('Reset'))
			]);

			dom.content(refs.httpPort, [
				E('span', { 'class': 'lucky-code-chip' }, String(conf.AdminWebListenPort || 16601)),
				E('button', {
					'type': 'button',
					'class': 'btn cbi-button cbi-button-edit',
					'click': openPortModal
				}, _('Change'))
			]);

			var safeUrlDisplay = conf.SafeURL ? String(conf.SafeURL) : _('Not set');
			dom.content(refs.safeUrl, [
				E('span', { 'class': 'lucky-code-chip' }, safeUrlDisplay),
				E('button', {
					'type': 'button',
					'class': 'btn cbi-button cbi-button-edit',
					'click': openSafeUrlModal
				}, _('Change'))
			]);

			var allowWan = !!conf.AllowInternetaccess;
			dom.content(refs.allowInternet, [
				E('span', { 'class': 'lucky-badge ' + (allowWan ? 'success' : 'danger') },
					allowWan ? _('Allowed') : _('Disallowed')),
				E('button', {
					'type': 'button',
					'class': 'btn cbi-button ' + (allowWan ? 'cbi-button-remove' : 'cbi-button-apply'),
					'click': function() { openToggleInternetModal(!allowWan); }
				}, allowWan ? _('Disable') : _('Enable'))
			]);

			renderRunStatusAndLink();
		}

		function makeRow(label, fieldNode) {
			return E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, label),
				E('div', { 'class': 'cbi-value-field' }, [fieldNode])
			]);
		}

		var dashboardNode = E('div', {}, [
			E('style', { 'type': 'text/css' }, STYLE_CSS),
			E('div', { 'class': 'cbi-section lucky-panel' }, [
				E('h3', {}, _('Main Program Information')),
				makeRow(_('Installation Status'), refs.installStatus),
				makeRow(_('Lucky Status'), refs.runStatus),
				makeRow(_('Lucky Arch'), refs.arch),
				makeRow(_('Lucky Version'), refs.version),
				makeRow(_('Compilation Time'), refs.compileTime)
			]),
			E('div', { 'class': 'cbi-section lucky-panel' }, [
				E('h3', {}, _('Admin Panel Information')),
				makeRow(_('Admin Panel'), refs.adminLink),
				makeRow(_('Admin Panel Login Info'), refs.loginInfo),
				makeRow(_('Admin Web Port'), refs.httpPort),
				makeRow(_('Safe URL'), refs.safeUrl),
				makeRow(_('Allow Internet Access'), refs.allowInternet)
			])
		]);

		renderDashboard();

		poll.add(function() {
			return getServiceStatus().then(function(running) {
				if (state.running !== running) {
					state.running = running;
					if (running)
						return refreshAll();
					renderRunStatusAndLink();
				}
			});
		}, 3);

		self._refreshLuckyDashboard = refreshAll;

		var m = new form.Map('lucky', _('Lucky'),
			_('IPv4/IPv6 port forward, DDNS, reverse proxy, Wake-on-LAN, IoT and more.'));

		var statusSec = m.section(form.NamedSection, '_status');
		statusSec.anonymous = true;
		statusSec.render = function() { return dashboardNode; };
		statusSec.parse = function() { return Promise.resolve(); };

		var s = m.section(form.TypedSection, 'lucky', _('Basic Settings'));
		s.anonymous = true;
		s.addremove = false;

		var o;

		o = s.option(form.Flag, 'enabled', _('Enable'),
			_('Enable Lucky service and start automatically on boot.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'logger', _('System Log'),
			_('Forward Lucky stdout and stderr output to system log.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'configdir', _('Config dir path'),
			_('The directory path used to store Lucky configuration files.'));
		o.placeholder = '/etc/config/lucky.daji';
		o.default = '/etc/config/lucky.daji';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			var v = (value || '').trim();
			if (!v)
				return _('Config directory path cannot be empty.');
			if (v.charAt(0) !== '/')
				return _('Config directory path must be an absolute path starting with "/".');
			if (/[\0\r\n]/.test(v))
				return _('Config directory path contains invalid characters.');
			return true;
		};

		return m.render();
	},

	handleSaveApply: function(ev, mode) {
		var self = this;
		return this.super('handleSaveApply', [ev, mode]).then(function() {
			if (typeof self._refreshLuckyDashboard === 'function') {
				window.setTimeout(function() {
					self._refreshLuckyDashboard();
				}, 900);
			}
		});
	}
});
