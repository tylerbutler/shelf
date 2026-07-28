/**
 * Berry syntax themes for Expressive Code.
 *
 * DESIGN.md's No-Gray Rule forbids neutral grays and blue-tinted slates anywhere
 * in this system. Starlight ships Night Owl by default, which is built almost
 * entirely from them (`#403f53`, `#5f636f`, `#919f9f`, `#82aaff`), so code blocks
 * — the site's most-read component — read as unthemed vendor default.
 *
 * These two themes place every token on the berry ramp. With a single hue family
 * available, tokens are differentiated on two axes rather than by hue:
 *
 *   - lightness  → emphasis (function/type names brightest, comments dimmest)
 *   - chroma     → voice (keywords vivid, comments desaturated)
 *
 * Every value below is verified ≥4.5:1 against its own code background in the
 * theme it belongs to, per the Two-Ends Rule. Ratios are noted inline; re-verify
 * if you change a value.
 */

/** Dark: tokens on Deep Currant (#4d0022), one ramp step above Blackberry Night. */
const DARK = {
	bg: "#4d0022",
	/** Petal Pink — identifiers, punctuation, default text. 8.58:1 */
	fg: "#f8aabe",
	/** Dusty rose — comments. Desaturated so they recede without dropping below AA. 6.50:1 */
	muted: "#c99aab",
	/** Raspberry Glow — keywords, operators, control flow. Highest chroma. 6.09:1 */
	keyword: "#ff729e",
	/** Rose Paper — string and char literals. 13.37:1 */
	string: "#ffe7ec",
	/** Accent Blush — numbers, booleans, constants. 9.22:1 */
	constant: "#e6bbcb",
	/** Pure White — function and type names. Maximum emphasis. 15.70:1 */
	name: "#ffffff",
	border: "#6b0031",
};

/** Light: tokens on Blush White (#fff3f5), the palest tint on the ramp. */
const LIGHT = {
	bg: "#fff3f5",
	/** Deep Currant — identifiers, punctuation, default text. 11.61:1 */
	fg: "#6b0031",
	/** Desaturated plum — comments. 5.13:1 */
	muted: "#8a5a70",
	/** Berry Stain — keywords, operators, control flow. 7.33:1 */
	keyword: "#a2004e",
	/** Boysenberry — string and char literals. 5.50:1 */
	string: "#ab3772",
	/** Mulberry Ink — numbers, booleans, constants. 7.90:1 */
	constant: "#8f195a",
	/** Blackberry Night — function and type names. Maximum emphasis. 16.77:1 */
	name: "#340014",
	border: "#eeccd9",
};

/**
 * Scope map shared by both themes. Kept deliberately generic so it covers the
 * Gleam and Erlang grammars this site uses plus the shell/toml/json blocks.
 */
function tokenColors(p) {
	return [
		{
			scope: ["comment", "punctuation.definition.comment", "string.comment"],
			settings: { foreground: p.muted, fontStyle: "italic" },
		},
		{
			scope: [
				"string",
				"string.quoted",
				"string.template",
				"constant.character",
				"punctuation.definition.string",
			],
			settings: { foreground: p.string },
		},
		{
			scope: [
				"constant.numeric",
				"constant.language",
				"constant.language.boolean",
				"constant.other",
				"support.constant",
			],
			settings: { foreground: p.constant },
		},
		{
			scope: [
				"keyword",
				"keyword.control",
				"keyword.operator",
				"keyword.other",
				"storage",
				"storage.type",
				"storage.modifier",
				"variable.language",
			],
			settings: { foreground: p.keyword },
		},
		{
			scope: [
				"entity.name.function",
				"entity.name.type",
				"entity.name.class",
				"entity.name.namespace",
				"entity.name.tag",
				"support.function",
				"support.type",
				"support.class",
				"meta.function-call",
			],
			settings: { foreground: p.name },
		},
		{
			scope: [
				"variable",
				"variable.other",
				"variable.parameter",
				"meta.definition.variable",
				"entity.name.label",
			],
			settings: { foreground: p.fg },
		},
		{
			scope: [
				"punctuation",
				"meta.brace",
				"meta.delimiter",
				"punctuation.separator",
				"punctuation.terminator",
			],
			settings: { foreground: p.fg },
		},
		{
			scope: ["entity.name.tag.yaml", "support.type.property-name.json", "entity.name.type.toml"],
			settings: { foreground: p.name },
		},
		{
			scope: ["invalid", "invalid.illegal"],
			settings: { foreground: p.keyword },
		},
	];
}

function theme(name, type, p) {
	return {
		name,
		type,
		colors: {
			"editor.background": p.bg,
			"editor.foreground": p.fg,
			"editorLineNumber.foreground": p.muted,
			"editorLineNumber.activeForeground": p.fg,
			"editor.selectionBackground": type === "dark" ? "#8f195a" : "#ffe7ec",
			"editor.lineHighlightBackground": type === "dark" ? "#6b0031" : "#ffe7ec",
			"editorGroup.border": p.border,
			focusBorder: type === "dark" ? "#ab3772" : "#8f195a",
			"terminal.background": p.bg,
			"terminal.foreground": p.fg,
			"titleBar.activeBackground": type === "dark" ? "#340014" : "#ffe7ec",
			"titleBar.activeForeground": p.fg,
		},
		tokenColors: tokenColors(p),
	};
}

/** Dark theme is listed first: it is the site's default. */
export const berryDark = theme("berry-dark", "dark", DARK);
export const berryLight = theme("berry-light", "light", LIGHT);
