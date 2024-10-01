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
	tailwindConfig: './tailwind.config.mjs',
	tailwindPreserveWhitespace: true,
	plugins: ['prettier-plugin-sql', 'prettier-plugin-tailwindcss'],
	overrides: [
		{
			files: ['*.pode'],
			options: {
				parser: 'html',
			},
		},
		{
			files: ['*.sql'],
			options: {
				language: 'sqlite',
			},
		},
	],
};

export default config;
