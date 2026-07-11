(function () {
	var events = [
		'htmx:abort',
		'htmx:before:process',
		'htmx:after:process',
		'htmx:config:request',
		'htmx:before:request',
		'htmx:before:response',
		'htmx:after:request',
		'htmx:response:error',
		'htmx:error',
		'htmx:before:swap',
		'htmx:after:swap',
		'htmx:before:settle',
		'htmx:after:settle',
		'htmx:confirm',
		'htmx:finally:request',
	];

	var logger = function (name) {
		return function (elt, detail) {
			if (!(htmx.config && htmx.config.debug)) return;
			if (detail && detail.error) {
				console.error('htmx ' + name, detail.error, { elt: elt, detail: detail });
			} else if (console.debug) {
				console.debug(name, { elt: elt, detail: detail });
			} else {
				console.log('DEBUG:', name, { elt: elt, detail: detail });
			}
		};
	};

	var extension = {};
	events.forEach(function (eventName) {
		extension[eventName.replace(/:/g, '_')] = logger(eventName);
	});

	htmx.registerExtension('debug', extension);
})();
