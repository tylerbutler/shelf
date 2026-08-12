import starlight from "@astrojs/starlight";
import a11yEmoji from "@fec/remark-a11y-emoji";
import { defineConfig } from "astro/config";
import mermaid from "astro-mermaid";
import starlightLinksValidator from "starlight-links-validator";
import starlightLlmsTxt from "starlight-llms-txt";
import { berryDark, berryLight } from "./src/styles/berry-code-themes.mjs";

// https://astro.build/config
export default defineConfig({
	site: "https://shelf.tylerbutler.com",
	prefetch: {
		defaultStrategy: "hover",
		prefetchAll: true,
	},
	integrations: [
		// Mermaid ships a lavender/olive palette in Trebuchet MS, which breaks three
		// of DESIGN.md's named rules at once (No-Gray, One Family, Two-Ends).
		//
		// autoTheme is off deliberately: it can only pick between mermaid's stock
		// 'default' and 'dark', and it re-renders every diagram on each theme
		// toggle (a visible flash). Instead we render once on the `base` theme and
		// let themeCSS resolve CSS custom properties defined per theme in
		// custom.css — so switching themes is a repaint, not a re-render.
		mermaid({
			theme: "base",
			autoTheme: false,
			mermaidConfig: {
				fontFamily:
					'"Spline Sans Variable", "Spline Sans", sans-serif',
				// Fallbacks for anything themeCSS doesn't reach. Values are the
				// dark-theme ramp; themeCSS overrides them in both themes.
				themeVariables: {
					fontFamily:
						'"Spline Sans Variable", "Spline Sans", sans-serif',
					fontSize: "14px",
					primaryColor: "#6b0031",
					primaryBorderColor: "#a2004e",
					primaryTextColor: "#f8aabe",
					lineColor: "#ff729e",
					textColor: "#f8aabe",
					mainBkg: "#6b0031",
					clusterBkg: "transparent",
					clusterBorder: "#a2004e",
					edgeLabelBackground: "#4d0022",
				},
				// Scoped into each diagram's own <style> by mermaid, so these win
				// on specificity without !important, and `var()` resolves against
				// the page theme at paint time.
				themeCSS: `
					.node rect, .node polygon, .node circle, .node path,
					.basic.label-container, .block {
						fill: var(--shelf-diagram-surface);
						stroke: var(--shelf-diagram-border);
						stroke-width: 1px;
					}
					.cluster rect {
						fill: none;
						stroke: var(--shelf-diagram-cluster-border);
						stroke-width: 1px;
					}
					text, .label, .nodeLabel, .nodeLabel p,
					.label span, .label text,
					.cluster-label, .cluster-label text,
					.cluster-label span, .cluster-label span p {
						fill: var(--shelf-diagram-text);
						color: var(--shelf-diagram-text);
					}
					.edgePath .path, .flowchart-link, line, path.path {
						stroke: var(--shelf-diagram-line);
					}
					.arrowheadPath, marker path, defs marker path {
						fill: var(--shelf-diagram-line);
						stroke: var(--shelf-diagram-line);
					}
					.edgeLabel, .edgeLabel p, .labelBkg {
						background-color: var(--shelf-diagram-panel);
						color: var(--shelf-diagram-text);
					}
					.edgeLabel .label > span, .edgeLabel foreignObject div {
						padding: 0.125rem 0.375rem;
					}
					.edgeLabel rect {
						fill: var(--shelf-diagram-panel);
						opacity: 1;
					}
				`,
			},
		}),
		starlight({
			title: "shelf",
			components: {
				Head: "./src/components/Head.astro",
			},
			editLink: {
				baseUrl:
					"https://github.com/tylerbutler/shelf/edit/main/website/",
			},
			description:
				"Persistent ETS tables backed by DETS for Gleam.",
			lastUpdated: true,
			logo: {
				light: "./src/assets/shelf-wordmark.webp",
				dark: "./src/assets/shelf-wordmark-dark.webp",
				replacesTitle: true,
				alt: "shelf logo",
			},
			favicon: "./src/assets/favicon.png",
			// Starlight's default Night Owl is built from neutral grays and
			// blue-slates, which DESIGN.md's No-Gray Rule forbids. Dark is listed
			// first because it is the site's default theme.
			expressiveCode: {
				themes: [berryDark, berryLight],
				styleOverrides: {
					// DESIGN.md §3 specifies code at 0.8125rem; the default
					// resolves to 14px. Inline <code> already matches.
					codeFontSize: "0.8125rem",
					codeFontFamily:
						'"Spline Sans Mono Variable", "Spline Sans Mono", ui-monospace, monospace',
					borderColor: "var(--sl-color-gray-5)",
					frames: {
						// The Tonal-Depth Rule: depth comes from the ramp, never
						// a shadow. Code blocks keep their hairline border.
						frameBoxShadowCssValue: "none",
					},
				},
			},
			customCss: [
				"@fontsource-variable/spline-sans",
				"@fontsource-variable/spline-sans-mono",
				"./src/styles/fonts.css",
				"./src/styles/custom.css",
			],
			plugins: [
				starlightLlmsTxt(),
				starlightLinksValidator(),
			],
			social: [
				{
					icon: "github",
					label: "GitHub",
					href: "https://github.com/tylerbutler/shelf",
				},
			],
			sidebar: [
				{
					label: "Start Here",
					items: [
						{
							label: "What is shelf?",
							slug: "introduction",
						},
						{
							label: "Installation",
							slug: "installation",
						},
						{
							label: "Quick Start",
							slug: "quick-start",
						},
					],
				},
				{
					label: "Guides",
					items: [
						{
							label: "Set Tables",
							slug: "guides/set-tables",
						},
						{
							label: "Bag Tables",
							slug: "guides/bag-tables",
						},
						{
							label: "Duplicate Bag Tables",
							slug: "guides/duplicate-bag-tables",
						},
						{
							label: "Write Modes",
							slug: "guides/write-modes",
						},
						{
							label: "Common Patterns",
							slug: "guides/common-patterns",
						},
					],
				},
				{
					label: "Advanced",
					items: [
						{
							label: "Persistence Operations",
							slug: "advanced/persistence-operations",
						},
						{
							label: "Limitations",
							slug: "advanced/limitations",
						},
						{
							label: "Schema Migration",
							slug: "advanced/schema-migration",
						},
						{
							label: "Troubleshooting",
							slug: "advanced/troubleshooting",
						},
					],
				},
			],
		}),
	],
	markdown: {
		smartypants: false,
		remarkPlugins: [
			a11yEmoji,
		],
	},
});
