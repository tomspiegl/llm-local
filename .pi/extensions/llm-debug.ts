/**
 * Debug extension: logs raw LLM communication to .local/llm-debug/
 *
 * Enabled by default. /llm-debug toggles logging on/off.
 * Captures only raw provider payloads (sent) and assistant responses (received).
 */
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

export default function (pi: ExtensionAPI) {
	let enabled = false;
	let debugDir = "";
	let sessionId = "";
	let eventCounter = 0;

	function ensureDir(cwd: string) {
		debugDir = join(cwd, ".local", "llm-debug");
		mkdirSync(debugDir, { recursive: true });
	}

	function pad(n: number, width: number): string {
		return String(n).padStart(width, "0");
	}

	function writeEvent(label: string, data: unknown, cwd?: string) {
		if (!enabled) return;
		if (!debugDir && cwd) startSession(cwd);
		if (!debugDir) return;
		eventCounter++;
		const filepath = join(debugDir, `${sessionId}_${pad(eventCounter, 5)}_${label}.json`);
		writeFileSync(filepath, JSON.stringify({
			timestamp: new Date().toISOString(),
			event: eventCounter,
			label,
			data,
		}, null, 2), "utf8");
	}

	function startSession(cwd: string) {
		ensureDir(cwd);
		sessionId = new Date().toISOString().replace(/[:.]/g, "-");
		eventCounter = 0;
	}

	// What we SEND to the LLM
	pi.on("before_provider_request", (event, ctx) => {
		if (!enabled) return;
		writeEvent("request", event.payload, ctx.cwd);
	});

	// What we RECEIVE from the LLM (complete assistant message)
	pi.on("message_end", (event, ctx) => {
		if (!enabled) return;
		const msg = event.message;
		if (msg?.role === "assistant") {
			writeEvent("response", msg, ctx.cwd);
		}
	});

	pi.registerCommand("llm-debug", {
		description: "Toggle raw LLM communication logging to .local/llm-debug/",
		handler: async (_args, ctx) => {
			enabled = !enabled;
			if (enabled) {
				startSession(ctx.cwd);
				ctx.ui.notify(`LLM debug ON → .local/pi-debug/${sessionId}_*`, "success");
			} else {
				ctx.ui.notify("LLM debug OFF", "info");
			}
		},
	});
}
