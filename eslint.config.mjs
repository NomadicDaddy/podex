import pluginJs from '@eslint/js';
import globals from 'globals';

export default [
	{
		// Globally ignored: vendored/copied distribution libs are not linted
		ignores: ['public/js/**', 'node_modules/**', 'logs/**', '.vscode/**'],
	},
	{
		languageOptions: {
			globals: {
				...globals.browser,
				...globals.node,
				// Client-side template engines referenced by the vendored htmx extensions
				htmx: 'readonly',
				Mustache: 'readonly',
				Handlebars: 'readonly',
				nunjucks: 'readonly',
			},
			parserOptions: {
				ecmaVersion: 12,
				sourceType: 'module',
			},
		},
		rules: {},
	},
	pluginJs.configs.recommended,
];
