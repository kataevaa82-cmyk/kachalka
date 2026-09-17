import { createServer } from "node:http";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { globSync, statSync } from "node:fs";
import { platform, tmpdir } from "node:os";
import { dirname, extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, spawnSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "godot", "export", "web");
// CHROME_PATH wins; otherwise take the first Chrome/Chromium this OS actually has.
const chromeCandidates = {
  win32: [
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
  ],
  darwin: [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
  ],
  linux: [
    "/usr/bin/google-chrome",
    "/usr/bin/chromium-browser",
    "/usr/bin/chromium",
    // Playwright-managed browsers (CI images ship these under a versioned dir).
    ...globSync("/opt/pw-browsers/chromium-*/chrome-linux/chrome"),
  ],
};
const isExecutable = (candidate) => {
  try {
    return statSync(candidate).isFile();
  } catch {
    return false;
  }
};
const chromePath = process.env.CHROME_PATH
  || (chromeCandidates[platform()] ?? []).find(isExecutable);
if (!chromePath) {
  console.error(`No Chrome found for ${platform()}. Set CHROME_PATH to the browser binary.`);
  process.exit(2);
}
const debugPort = 9223;
if (!statSync(join(root, "index.html"), { throwIfNoEntry: false })?.isFile()) {
  console.error(`No web build at ${root}. Export the YandexGamesWeb preset first.`);
  process.exit(2);
}
let pagePort = 0;
const sdkStub = `
window.__sdkCalls = { loading: 0, starts: 0, stops: 0, cloudGets: 0, cloudSets: 0, scores: 0, boardReads: 0 };
window.__sdkEvents = {};
window.YaGames = {
  init: async () => ({
    on: (name, callback) => { window.__sdkEvents[name] = callback; },
    features: {
      LoadingAPI: { ready: () => { window.__loadingReady = true; window.__sdkCalls.loading += 1; } },
      GameplayAPI: {
        start: () => { window.__gameplay = 'started'; window.__sdkCalls.starts += 1; },
        stop: () => { window.__gameplay = 'stopped'; window.__sdkCalls.stops += 1; },
      },
    },
    adv: {
      showFullscreenAdv: ({ callbacks }) => {
        callbacks?.onOpen?.();
        setTimeout(() => callbacks?.onClose?.(true), 100);
      },
      showRewardedVideo: ({ callbacks }) => {
        callbacks?.onOpen?.();
        setTimeout(() => callbacks?.onRewarded?.(), 50);
        setTimeout(() => callbacks?.onClose?.(true), 120);
      },
    },
    deviceInfo: { type: "desktop", isDesktop: () => true, isMobile: () => false, isTablet: () => false, isTV: () => false },
    auth: { openAuthDialog: async () => {} },
    getPlayer: async () => ({
      getData: async () => { window.__sdkCalls.cloudGets += 1; return {}; },
      setData: async () => { window.__sdkCalls.cloudSets += 1; },
    }),
    isAvailableMethod: async () => true,
    leaderboards: {
      setScore: async () => { window.__sdkCalls.scores += 1; },
      getEntries: async () => {
        window.__sdkCalls.boardReads += 1;
        return { entries: [{ rank: 1, score: 812, player: { publicName: 'Zhelezo' } }], userRank: 0 };
      },
    },
  }),
};`;
const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
};

const server = createServer(async (request, response) => {
  try {
    if (request.url === "/sdk.js") {
      response.writeHead(200, { "Content-Type": mime[".js"] });
      response.end(sdkStub);
      return;
    }
    const relative = request.url === "/" ? "index.html" : decodeURIComponent(request.url.slice(1));
    const path = normalize(join(root, relative));
    if (!path.startsWith(normalize(root))) throw new Error("bad path");
    const data = await readFile(path);
    response.writeHead(200, { "Content-Type": mime[extname(path)] ?? "application/octet-stream" });
    response.end(data);
  } catch {
    response.writeHead(404);
    response.end("not found");
  }
});

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function openDebugger() {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      const pages = await fetch(`http://127.0.0.1:${debugPort}/json`).then((response) => response.json());
      const page = pages.find((item) => item.type === "page" && item.url.includes(`127.0.0.1:${pagePort}`));
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await delay(100);
  }
  throw new Error("Chrome DevTools endpoint did not appear");
}

// Software-rendered headless Chrome blocks the page for tens of seconds while the gym loads.
async function command(socketUrl, method, params = {}, timeoutMs = 90000) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(socketUrl);
    const timeout = setTimeout(() => reject(new Error(`DevTools ${method} timed out`)), timeoutMs);
    socket.addEventListener("open", () => {
      socket.send(JSON.stringify({
        id: 1,
		method,
		params,
      }));
    });
    socket.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (message.id !== 1) return;
      clearTimeout(timeout);
      socket.close();
      if (message.error || message.result?.exceptionDetails) {
        reject(new Error(JSON.stringify(message.error ?? message.result.exceptionDetails)));
      } else {
		resolve(message.result);
      }
    });
    socket.addEventListener("error", () => reject(new Error("DevTools WebSocket failed")));
  });
}

async function evaluate(socketUrl, expression) {
	const response = await command(socketUrl, "Runtime.evaluate", { expression, returnByValue: true });
	return response.result?.value;
}

let chrome;
let profile;
let socketUrl;
try {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  pagePort = server.address().port;
  profile = await mkdtemp(join(tmpdir(), "kach-browser-smoke-"));
  chrome = spawn(chromePath, [
    "--headless=new",
    "--disable-gpu",
    "--no-sandbox",
    `--remote-debugging-port=${debugPort}`,
	`--user-data-dir=${profile}`,
    `http://127.0.0.1:${pagePort}/index.html`,
  ], { stdio: "ignore" });
	socketUrl = await openDebugger();
	await delay(8000);
  let result;
  for (let attempt = 0; attempt < 120; attempt += 1) {
    result = await evaluate(socketUrl, `JSON.stringify({
      status: document.querySelector('#status')?.style.display || '',
      statusText: document.querySelector('#status')?.textContent || '',
      canvas: !!document.querySelector('#canvas'),
      loadingReady: window.__loadingReady === true,
      gameplay: window.__gameplay || '',
    })`);
    const parsed = JSON.parse(result);
    if (parsed.status === "none" && parsed.loadingReady) break;
    await delay(100);
  }
	const parsed = JSON.parse(result);
	parsed.calls = JSON.parse(await evaluate(socketUrl, "JSON.stringify(window.__sdkCalls)"));
	if (!parsed.canvas || parsed.status !== "none" || !parsed.loadingReady) {
		console.log(JSON.stringify(parsed));
		process.exitCode = 1;
	} else {
		console.log(JSON.stringify(parsed));
		// Title is not gameplay: GameplayAPI stays untouched until the gym starts.
		if (parsed.calls.loading < 1 || parsed.calls.starts !== 0 || parsed.calls.stops !== 0 || parsed.calls.cloudGets < 1) process.exitCode = 1;
		// Yandex: no page scroll/zoom, text selection or long-tap callout.
		const page = JSON.parse(await evaluate(socketUrl, `JSON.stringify((() => {
			const body = getComputedStyle(document.body);
			const menu = new MouseEvent('contextmenu', { bubbles: true, cancelable: true });
			document.querySelector('#canvas').dispatchEvent(menu);
			return { touchAction: body.touchAction, userSelect: body.userSelect || body.webkitUserSelect, overflow: body.overflow, contextMenuBlocked: menu.defaultPrevented };
		})())`));
		console.log(JSON.stringify({ page }));
		if (page.touchAction !== "none" || page.userSelect !== "none" || page.overflow !== "hidden" || !page.contextMenuBlocked) process.exitCode = 1;
		// Title -> gym: Space starts the game; the gym must load its GLBs and start gameplay.
		const key = { key: " ", code: "Space", windowsVirtualKeyCode: 32, nativeVirtualKeyCode: 32 };
		await command(socketUrl, "Input.dispatchKeyEvent", { type: "keyDown", text: " ", ...key });
		await command(socketUrl, "Input.dispatchKeyEvent", { type: "keyUp", ...key });
		let gym;
		for (let attempt = 0; attempt < 200; attempt += 1) {
			gym = JSON.parse(await evaluate(socketUrl, "JSON.stringify({ gameplay: window.__gameplay || '', calls: window.__sdkCalls })"));
			if (gym.gameplay === "started") break;
			await delay(100);
		}
		console.log(JSON.stringify({ gym }));
		// LoadingAPI.ready is one-shot: the gym must not repeat the title's call.
		if (gym.gameplay !== "started" || gym.calls.loading !== 1 || gym.calls.starts < 1) process.exitCode = 1;
		const snapshot = async () => JSON.parse(await evaluate(socketUrl, "JSON.stringify({ gameplay: window.__gameplay || '', calls: window.__sdkCalls })"));
		const settle = async (label, want) => {
			let state;
			for (let attempt = 0; attempt < 50; attempt += 1) {
				state = await snapshot();
				if (want(state)) break;
				await delay(100);
			}
			console.log(JSON.stringify({ [label]: state }));
			if (!want(state)) process.exitCode = 1;
			return state;
		};
		const setHidden = (hidden) => evaluate(socketUrl, `Object.defineProperty(document, 'hidden', { value: ${hidden}, configurable: true }); document.dispatchEvent(new Event('visibilitychange')); true`);
		// SDK pause (ad / purchase): stop gameplay and push the save to the cloud immediately.
		await evaluate(socketUrl, "window.__sdkEvents.game_api_pause(); true");
		await settle("sdkPause", (s) => s.calls.cloudSets >= 1 && s.gameplay === "stopped");
		await evaluate(socketUrl, "window.__sdkEvents.game_api_resume(); true");
		await settle("sdkResume", (s) => s.gameplay === "started");
		// Hidden tab pauses too, even without an SDK event.
		await setHidden(true);
		await settle("tabHidden", (s) => s.gameplay === "stopped");
		// Overlap: SDK resume while the tab is still hidden must not resume the game.
		await evaluate(socketUrl, "window.__sdkEvents.game_api_pause(); window.__sdkEvents.game_api_resume(); true");
		await delay(500);
		await settle("stillHidden", (s) => s.gameplay === "stopped");
		await setHidden(false);
		await settle("tabVisible", (s) => s.gameplay === "started");
	}
} catch (error) {
  console.error(error);
  process.exitCode = 1;
} finally {
	if (socketUrl) {
		await command(socketUrl, "Browser.close", {}, 2000).catch(() => {});
		await delay(500);
	}
	if (chrome && !chrome.killed) {
		spawnSync("taskkill", ["/PID", String(chrome.pid), "/T", "/F"], { stdio: "ignore" });
	}
	server.closeAllConnections?.();
	server.close();
	server.unref();
	if (profile) {
		await Promise.race([
			rm(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 150 }).catch(() => {}),
			delay(2000),
		]);
	}
}
