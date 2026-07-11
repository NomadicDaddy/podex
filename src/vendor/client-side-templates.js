(function () {
	// htmx 4 dispatches extensions globally, so replicate 2.x per-element
	// activation here: the extension is active only where the nearest governing
	// hx-ext enables it (and is not ignored).
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

	var templateSelectors = [
		'[mustache-template]',
		'[mustache-array-template]',
		'[handlebars-template]',
		'[handlebars-array-template]',
		'[nunjucks-template]',
		'[nunjucks-array-template]',
		'[xslt-template]',
	].join(',');

	function transform(sourceElement, text) {
		var node;
		var data;
		var templateId;
		var template;

		node = sourceElement.closest('[mustache-template]');
		if (node) {
			data = JSON.parse(text);
			templateId = node.getAttribute('mustache-template');
			template = document.getElementById(templateId);
			if (template) {
				return Mustache.render(template.innerHTML, data);
			}
			throw new Error('Unknown mustache template: ' + templateId);
		}

		node = sourceElement.closest('[mustache-array-template]');
		if (node) {
			data = JSON.parse(text);
			templateId = node.getAttribute('mustache-array-template');
			template = document.getElementById(templateId);
			if (template) {
				return Mustache.render(template.innerHTML, { data: data });
			}
			throw new Error('Unknown mustache template: ' + templateId);
		}

		node = sourceElement.closest('[handlebars-template]');
		if (node) {
			data = JSON.parse(text);
			templateId = node.getAttribute('handlebars-template');
			template = document.getElementById(templateId);
			if (template) {
				var handlebarsRenderer = Handlebars.compile(template.innerHTML);
				return handlebarsRenderer(data);
			}
			throw new Error('Unknown handlebars template: ' + templateId);
		}

		node = sourceElement.closest('[handlebars-array-template]');
		if (node) {
			data = JSON.parse(text);
			templateId = node.getAttribute('handlebars-array-template');
			template = document.getElementById(templateId);
			if (template) {
				var handlebarsArrayRenderer = Handlebars.compile(template.innerHTML);
				return handlebarsArrayRenderer(data);
			}
			throw new Error('Unknown handlebars template: ' + templateId);
		}

		node = sourceElement.closest('[nunjucks-template]');
		if (node) {
			data = JSON.parse(text);
			templateId = node.getAttribute('nunjucks-template');
			template = document.getElementById(templateId);
			if (template) {
				return nunjucks.renderString(template.innerHTML, data);
			}
			return nunjucks.render(templateId, data);
		}

		node = sourceElement.closest('[nunjucks-array-template]');
		if (node) {
			data = JSON.parse(text);
			templateId = node.getAttribute('nunjucks-array-template');
			template = document.getElementById(templateId);
			if (template) {
				return nunjucks.renderString(template.innerHTML, { data: data });
			}
			return nunjucks.render(templateId, { data: data });
		}

		node = sourceElement.closest('[xslt-template]');
		if (node) {
			templateId = node.getAttribute('xslt-template');
			template = document.getElementById(templateId);
			if (template) {
				var content = template.innerHTML ? new DOMParser().parseFromString(template.innerHTML, 'application/xml') : template.contentDocument;
				var processor = new XSLTProcessor();
				processor.importStylesheet(content);
				var xmlDoc = new DOMParser().parseFromString(text, 'application/xml');
				var fragment = processor.transformToFragment(xmlDoc, document);
				return new XMLSerializer().serializeToString(fragment);
			}
			throw new Error('Unknown XSLT template: ' + templateId);
		}

		return text;
	}

	htmx.registerExtension('client-side-templates', {
		htmx_after_request: function (elt, detail) {
			var ctx = detail.ctx;
			if (!isActiveFor(ctx.sourceElement, 'client-side-templates')) return;
			// Only transform when a client-side template is actually requested;
			// otherwise leave the response (plain HTML, boosted navigation, etc.) untouched.
			if (!ctx.sourceElement.closest(templateSelectors)) return;
			ctx.text = transform(ctx.sourceElement, ctx.text);
		},
	});
})();
