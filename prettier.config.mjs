// prettier.config.js, .prettierrc.js, prettier.config.mjs, or .prettierrc.mjs

/**
 * @see https://prettier.io/docs/en/configuration.html
 * @type {import("prettier").Config}
 */
const config = {
	trailingComma: 'all',
	tabWidth: 4,
	semi: true,
	singleQuote: true,
	printWidth: 180,
	useTabs: true,
	bracketSameLine: true,
	tailwindStylesheet: './public/css/tailwind.css',
	tailwindPreserveWhitespace: true,
	plugins: ['prettier-plugin-tailwindcss'],
	overrides: [
		{
			files: ['scripts/check-license-core.ts', 'scripts/lib/license-core/**/*.ts'],
			options: {
				printWidth: 100,
			},
		},
		{
			files: ['scripts/**/*.mjs'],
			options: {
				printWidth: 100,
			},
		},
	],
};

export default config;
