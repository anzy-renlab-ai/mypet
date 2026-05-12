#!/usr/bin/env bun
/**
 * Generate all mypet sprite sheets in one run.
 *
 * Reads:
 *  - OPENROUTER_API_KEY  (or ~/.openrouter.json)
 *  - REF_IMAGE env var or defaults to designs/cat-variants-20260511/north-star-reference.png
 *
 * Writes PNGs to Sources/MyPet/Resources/sprites/
 *
 * Sprite spec follows DESIGN.md + D15 decision:
 *  - idle / sleepy / hungry  → 素颜 (no costume)
 *  - eating / excited / purring → 戏装 (Peking Opera attire, per user image)
 */

import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const REPO = "/Users/baidu/work/mypet";
const SPRITES_DIR = join(REPO, "Sources/MyPet/Resources/sprites");
const REF =
  process.env.REF_IMAGE ??
  join(
    homedir(),
    ".gstack/projects/mypet/designs/cat-variants-20260511/north-star-reference.png"
  );
const MODEL = process.env.MODEL ?? "google/gemini-3.1-flash-image-preview";
const GEN = join(REPO, "scripts/gen-sprite.ts");

interface SpriteSpec {
  name: string;
  costume: "plain" | "opera";
  prompt: string;
}

const PLAIN_BASE =
  "Same exact cute fluffy 3D-rendered kitten as in the reference image: gray-and-white tabby fur, pure white chest, " +
  "large round deep blue eyes with multi-layer star highlights, soft pink blush, pink rim-lit inner ears, head 1.2x body proportion, " +
  "stubby short legs, rounded plump body. Pixar/Disney short film 3D render quality. ";

const OPERA_BASE =
  "Same exact cute fluffy gray-white tabby kitten as in the reference, but now wearing traditional Chinese Peking Opera (京剧) wusheng costume: " +
  "ornate beaded headpiece with colorful silk pompoms (yellow, red, blue, pink, green), embroidered blue and red brocade armor with gold dragon and flower patterns, " +
  "tasseled fringe at waist, small ornate boots on hind paws, holding a red-handled spear with gold tassel and small flag. " +
  "Heroic 武生 stage pose. Same kitten face, eyes, fur color preserved. Pixar/Disney 3D render quality. ";

const LIGHTING =
  "Warm orange rim-light from upper-right, cool blue ambient. Pure transparent background. " +
  "Isolated subject — no scenery, no ground, no environment. High-detail fur strands. Studio cinematic render.";

const SPRITES: SpriteSpec[] = [
  {
    name: "cat-idle",
    costume: "plain",
    prompt:
      PLAIN_BASE +
      "Sitting calmly in idle pose, tail curled gently to one side, eyes open with peaceful curious wonder expression, " +
      "mouth in soft content smile, ears upright relaxed, paws tucked neatly in front. " +
      LIGHTING,
  },
  {
    name: "cat-sleepy",
    costume: "plain",
    prompt:
      PLAIN_BASE +
      "Sleepy pose: curled into a compact 'bread loaf' shape with paws and tail tucked under body, " +
      "eyes closed peacefully, head tilted to one side resting on chest. Small floating 'ZZZ' symbols above. Body looks soft and round. " +
      LIGHTING,
  },
  {
    name: "cat-hungry",
    costume: "plain",
    prompt:
      PLAIN_BASE +
      "Hungry pose: looking up at viewer with extra-large watery puppy-dog eyes, sad sparkle highlights, lower lip trembling, " +
      "one front paw pressed against round tummy, ears slightly drooped. Pleading expression. " +
      LIGHTING,
  },
  {
    name: "cat-eating",
    costume: "opera",
    prompt:
      OPERA_BASE +
      "Eating pose: mouth wide open in 'O' shape mid-bite, cheeks puffed cute, slight head tilt as if chewing, " +
      "eyes wide and delighted, holding the spear in one paw, looking down at a glowing yellow energy token between paws (representing compute tokens). " +
      LIGHTING,
  },
  {
    name: "cat-excited",
    costume: "opera",
    prompt:
      OPERA_BASE +
      "Excited 亮相 pose: ears popped straight up, eyes transformed into giant golden cartoon stars with bright sparkle highlights, " +
      "mid-jump body arched in classic Peking Opera 亮相 entrance pose, spear raised high, all four paws lifted, " +
      "small gold sparkle particles floating around. " +
      LIGHTING,
  },
  {
    name: "cat-purring",
    costume: "opera",
    prompt:
      OPERA_BASE +
      "Purring contented pose: eyes closed in blissful crescent shape, slight smile at mouth corners, body relaxed, " +
      "spear lowered to one side. Tiny floating heart symbols above head. " +
      LIGHTING,
  },
  // Error fallback states (plain costume; cat is in trouble, not performing)
  {
    name: "cat-error-auth",
    costume: "plain",
    prompt:
      PLAIN_BASE +
      "Looking up at viewer with a slightly confused but cute expression, one paw raised pointing upward as if asking a question. " +
      "Small '?' question mark floating above head. " +
      LIGHTING,
  },
  {
    name: "cat-error-rate",
    costume: "plain",
    prompt:
      PLAIN_BASE +
      "Dizzy spiral expression: eyes drawn as cartoon spirals (@@ style), mouth slightly open with tongue stuck out playfully, " +
      "head wobbling. Stars and small birds tweeting around head. " +
      LIGHTING,
  },
  {
    name: "cat-error-network",
    costume: "plain",
    prompt:
      PLAIN_BASE +
      "Puzzled pose: head tilted at exaggerated 30-degree angle, one ear slightly down, eyes wide with surprised 'what?' expression, " +
      "small lightbulb-shaped '?' above head. " +
      LIGHTING,
  },
];

async function genOne(spec: SpriteSpec): Promise<boolean> {
  const out = join(SPRITES_DIR, `${spec.name}.png`);
  const args = [
    "run",
    GEN,
    "--ref",
    REF,
    "--prompt",
    spec.prompt,
    "--model",
    MODEL,
    "--out",
    out,
    "--size",
    "1K",
  ];
  const r = spawnSync("bun", args, { stdio: "inherit" });
  if (r.status !== 0) {
    console.error(`✗ ${spec.name} failed`);
    return false;
  }
  return true;
}

async function main() {
  if (!existsSync(REF)) {
    console.error(`Reference image missing: ${REF}`);
    process.exit(1);
  }
  if (!existsSync(SPRITES_DIR)) mkdirSync(SPRITES_DIR, { recursive: true });

  console.log(`Generating ${SPRITES.length} sprites via ${MODEL}`);
  console.log(`Reference: ${REF}`);
  console.log(`Output: ${SPRITES_DIR}`);
  console.log("");

  const results: { name: string; ok: boolean }[] = [];
  for (const spec of SPRITES) {
    const ok = await genOne(spec);
    results.push({ name: spec.name, ok });
  }

  console.log("\n— Summary —");
  for (const r of results) {
    console.log(`  ${r.ok ? "✓" : "✗"} ${r.name}`);
  }
  const failures = results.filter((r) => !r.ok).length;
  if (failures > 0) {
    console.log(`\n${failures} sprite(s) failed. Re-run script to retry only failures.`);
    process.exit(1);
  }
  console.log("\nAll sprites generated. Ready to wire into SpriteKit.");
}

main();
