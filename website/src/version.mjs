import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * The published release, read from the library's own gleam.toml at build time.
 *
 * The splash page states the current version as a trust signal; hardcoding it
 * here would guarantee it goes stale on the next release and quietly become the
 * opposite of a trust signal.
 *
 * Resolved from the working directory rather than `import.meta.url`: this module
 * is bundled into `dist/chunks/` before it runs, so a URL-relative path points
 * at the wrong tree. Both `astro dev` and `astro build` run from `website/`.
 */
const gleamToml = readFileSync(resolve(process.cwd(), "../gleam.toml"), "utf8");

const match = gleamToml.match(/^version\s*=\s*"([^"]+)"/m);

if (!match) {
	throw new Error(
		"Could not read `version` from gleam.toml — the splash page's release badge depends on it.",
	);
}

export const version = match[1];
