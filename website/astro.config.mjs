import starlight from "@astrojs/starlight";
import a11yEmoji from "@fec/remark-a11y-emoji";
import { defineConfig } from "astro/config";
import starlightLinksValidator from "starlight-links-validator";
import starlightLlmsTxt from "starlight-llms-txt";

// https://astro.build/config
export default defineConfig({
	site: "https://shelf.tylerbutler.com",
	prefetch: {
		defaultStrategy: "hover",
		prefetchAll: true,
	},
	integrations: [
		starlight({
			title: "shelf",
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
			customCss: [
				"@fontsource/metropolis/400.css",
				"@fontsource/metropolis/600.css",
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
