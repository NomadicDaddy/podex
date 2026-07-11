// prettier.config.js, .prettierrc.js, prettier.config.mjs, or .prettierrc.mjs

/**
 * @see https://prettier.io/docs/en/configuration.html
 * @type {import("prettier").Config}
 */
const config = {
	trailingComma: 'es5',
	tabWidth: 4,
	semi: true,
	singleQuote: true,
	printWidth: 180,
	useTabs: true,
	bracketSameLine: true,
	tailwindStylesheet: './public/css/tailwind.css',
	tailwindPreserveWhitespace: true,
	plugins: ['prettier-plugin-sql', 'prettier-plugin-tailwindcss'],
	overrides: [
		{
			files: ['*.sql'],
			options: {
				language: 'sqlite',
			},
		},
	],
};

export default config;
