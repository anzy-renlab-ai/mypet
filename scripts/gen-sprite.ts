#!/usr/bin/env bun
/**
 * Single-sprite generator via OpenRouter.
 *
 * Usage:
 *   bun scripts/gen-sprite.ts \
 *     --ref /path/to/north-star.png \
 *     --prompt "the kitten in eating pose, mouth open, transparent background" \
 *     --model google/gemini-3.1-flash-image-preview \
 *     --out Sources/MyPet/Resources/sprites/cat-eating.png
 *
 * Auth:
 *   export OPENROUTER_API_KEY=sk-or-v1-...
 *   OR  echo '{"api_key":"sk-or-v1-..."}' > ~/.openrouter.json
 */

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

function loadKey(): string {
  if (process.env.OPENROUTER_API_KEY) return process.env.OPENROUTER_API_KEY;
  const cfgPath = join(homedir(), ".openrouter.json");
  if (existsSync(cfgPath)) {
    const cfg = JSON.parse(readFileSync(cfgPath, "utf8"));
    if (cfg.api_key) return cfg.api_key;
  }
  throw new Error(
    "No OpenRouter key. Set OPENROUTER_API_KEY env var, or write " +
      "{ \"api_key\": \"sk-or-v1-...\" } to ~/.openrouter.json"
  );
}

function parseArgs(): {
  ref?: string;
  prompt: string;
  model: string;
  out: string;
  size: string;
} {
  const args = process.argv.slice(2);
  const get = (flag: string) => {
    const i = args.indexOf(flag);
    return i >= 0 ? args[i + 1] : undefined;
  };
  const ref = get("--ref");
  const prompt = get("--prompt");
  const model = get("--model") ?? "google/gemini-3.1-flash-image-preview";
  const out = get("--out");
  const size = get("--size") ?? "1K";
  if (!prompt || !out) {
    console.error("Usage: bun gen-sprite.ts --prompt '...' --out path.png [--ref path] [--model X] [--size 1K|2K]");
    process.exit(2);
  }
  return { ref, prompt, model, out, size };
}

function imageToDataURL(path: string): string {
  const buf = readFileSync(path);
  const mime = path.toLowerCase().endsWith(".png") ? "image/png" : "image/jpeg";
  return `data:${mime};base64,${buf.toString("base64")}`;
}

interface OpenRouterImage {
  type: "image_url";
  image_url: { url: string };
}

interface OpenRouterMsgPartText {
  type: "text";
  text: string;
}

type OpenRouterMsgPart = OpenRouterImage | OpenRouterMsgPartText;

interface OpenRouterChoice {
  message: {
    content?: string;
    images?: Array<{ image_url: { url: string } } | { type: string; image_url: { url: string } }>;
  };
}

async function main() {
  const { ref, prompt, model, out, size } = parseArgs();
  const key = loadKey();

  const content: OpenRouterMsgPart[] = [{ type: "text", text: prompt }];
  if (ref) {
    if (!existsSync(ref)) throw new Error(`Reference image not found: ${ref}`);
    const dataURL = imageToDataURL(ref);
    content.push({ type: "image_url", image_url: { url: dataURL } });
  }

  const body = {
    model,
    messages: [{ role: "user", content }],
    modalities: ["image", "text"],
    image_config: { aspect_ratio: "1:1", image_size: size },
  };

  console.log(`→ ${model} → ${out}`);
  const t0 = Date.now();

  const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://github.com/baidu/mypet",
      "X-Title": "mypet sprite gen",
    },
    body: JSON.stringify(body),
  });

  const elapsedSec = ((Date.now() - t0) / 1000).toFixed(1);
  const text = await res.text();
  if (!res.ok) {
    console.error(`  HTTP ${res.status} after ${elapsedSec}s`);
    console.error(`  ${text.slice(0, 500)}`);
    process.exit(1);
  }

  let json: { choices?: OpenRouterChoice[]; error?: { message: string } };
  try {
    json = JSON.parse(text);
  } catch (e) {
    console.error(`  Non-JSON response: ${text.slice(0, 200)}`);
    process.exit(1);
  }

  if (json.error) {
    console.error(`  API error: ${json.error.message}`);
    process.exit(1);
  }

  const images = json.choices?.[0]?.message?.images;
  if (!images || images.length === 0) {
    console.error(`  No images in response. Full: ${JSON.stringify(json).slice(0, 500)}`);
    process.exit(1);
  }

  const first = images[0];
  const url = "image_url" in first ? first.image_url.url : (first as any).url;
  const match = url.match(/^data:image\/\w+;base64,(.+)$/);
  if (!match) {
    console.error(`  Unexpected image URL format: ${url.slice(0, 100)}`);
    process.exit(1);
  }
  const png = Buffer.from(match[1], "base64");
  writeFileSync(out, png);
  console.log(`  ✓ ${png.length / 1024 | 0} KB in ${elapsedSec}s`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
