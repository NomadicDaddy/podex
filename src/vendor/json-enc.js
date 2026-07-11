(function () {
	// HTTP methods that send a request body (GET and HEAD never do)
	var bodyMethods = { post: true, put: true, patch: true, delete: true };

	// htmx 4 dispatches extensions globally, so replicate 2.x per-element
	// activation here: json-enc is active for an element only when the nearest
	// governing hx-ext enables it (and is not ignored).
	function isActiveFor(elt, extName) {
		var node = elt;
		while (node && node.nodeType === 1) {
			var attr = node.getAttribute && node.getAttribute('hx-ext');
			if (attr) {
				var tokens = attr.split(/[\s,]+/);
				if (tokens.indexOf('ignore:' + extName) !== -1) return false;
				if (tokens.indexOf(extName) !== -1) return true;
			}
			node = node.parentNode;
		}
		return false;
	}

	htmx.registerExtension('json-enc', {
		htmx_before_request: function (elt, detail) {
			if (!isActiveFor(detail.ctx.sourceElement, 'json-enc')) return;

			var request = detail.ctx.request;
			if (!bodyMethods[(request.method || 'get').toLowerCase()]) return;
			if (!request.body) return;

			var object = {};
			var body = request.body;
			var entries = typeof body.entries === 'function' ? body.entries() : [];
			var iterator = entries.next
				? entries
				: {
						next: function () {
							return { done: true };
						},
					};
			var step = iterator.next();
			while (!step.done) {
				var key = step.value[0];
				var value = step.value[1];
				if (Object.prototype.hasOwnProperty.call(object, key)) {
					if (!Array.isArray(object[key])) {
						object[key] = [object[key]];
					}
					object[key].push(value);
				} else {
					object[key] = value;
				}
				step = iterator.next();
			}

			// FormData encodes every value as a string; restore hx-vals/hx-vars
			// (provided by htmx 4 as ctx.vals) to their original types.
			var vals = detail.ctx.vals || {};
			Object.keys(object).forEach(function (key) {
				if (Object.prototype.hasOwnProperty.call(vals, key)) {
					object[key] = vals[key];
				}
			});

			request.headers['Content-Type'] = 'application/json';
			request.body = JSON.stringify(object);
		},
	});
})();
