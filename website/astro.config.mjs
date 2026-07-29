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
		mermaid(),
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
