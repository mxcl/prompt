#!/usr/bin/env -S pkgx deno run -A

import {
  basename,
  dirname,
  fromFileUrl,
  join,
  resolve,
} from "https://deno.land/std@0.206.0/path/mod.ts";

type DownloadResult<T> = {
  json: T;
  etag: string | null;
};

type RawCask = {
  token?: string;
  full_token?: string;
  name?: unknown;
  desc?: unknown;
  homepage?: unknown;
  deprecated?: unknown;
  artifacts?: unknown;
};

type TrimmedCask = {
  token: string;
  full_token: string;
  name: string[];
  desc?: string;
  homepage?: string;
  deprecated?: true;
  artifacts?: Array<{ app: string[] }>;
};

const scriptPath = fromFileUrl(import.meta.url);
const scriptDir = dirname(scriptPath);
const repoRoot = resolve(scriptDir, "..");
const dataDir = join(repoRoot, "Data");
const cacheDir = join(repoRoot, "DerivedData", "mkdb");
const BREW_API_BASE = "https://formulae.brew.sh/api";

await Promise.all([
  Deno.mkdir(cacheDir, { recursive: true }),
  Deno.mkdir(dataDir, { recursive: true }),
]);

const caskDownloadPromise = downloadJSON<RawCask[]>(
  `${BREW_API_BASE}/cask.json`,
);
const formulaDownloadPromise = downloadJSON(`${BREW_API_BASE}/formula.json`);

const { json: caskSource, etag: caskEtag } = await caskDownloadPromise;
await formulaDownloadPromise;

const trimmedCasks = (Array.isArray(caskSource) ? caskSource : [])
  .map(trimCask)
  .filter((entry): entry is TrimmedCask => entry !== null);

const caskOutput: Record<string, unknown> = { data: trimmedCasks };
if (caskEtag) {
  caskOutput.etag = caskEtag;
}
await writeJSON(join(dataDir, "cask.json"), caskOutput);

// Keep the formula payload around in DerivedData but ship an empty list for now.
for (const filename of ["formula.json", "formulae.json"]) {
  await writeJSON(join(dataDir, filename), []);
}

async function downloadJSON<T>(url: string): Promise<DownloadResult<T>> {
  const filename = basename(new URL(url).pathname);
  const targetPath = join(cacheDir, filename);
  const etagPath = `${targetPath}.etag`;

  const headers: HeadersInit = {};
  const hasCache = await fileExists(targetPath);
  let etag: string | null = null;

  if (hasCache) {
    etag = await readFileOrNull(etagPath);
    if (etag) {
      headers["If-None-Match"] = etag;
    }
  }

  const response = await fetch(url, { headers });

  if (response.status === 304) {
    if (!hasCache) {
      throw new Error(`Received 304 for ${url} without cached content.`);
    }
    const cachedText = await Deno.readTextFile(targetPath);
    return { json: JSON.parse(cachedText) as T, etag };
  }

  if (!response.ok) {
    throw new Error(`Failed to fetch ${url}: ${response.status} ${response.statusText}`);
  }

  const text = await response.text();
  await Deno.writeTextFile(targetPath, text);

  const newEtag = response.headers.get("etag");
  if (newEtag) {
    await Deno.writeTextFile(etagPath, newEtag);
  } else if (await fileExists(etagPath)) {
    await Deno.remove(etagPath);
  }

  return { json: JSON.parse(text) as T, etag: newEtag };
}

async function fileExists(path: string): Promise<boolean> {
  try {
    await Deno.lstat(path);
    return true;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      return false;
    }
    throw error;
  }
}

async function readFileOrNull(path: string): Promise<string | null> {
  try {
    return (await Deno.readTextFile(path)).trim();
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      return null;
    }
    throw error;
  }
}

function trimCask(raw: RawCask): TrimmedCask | null {
  if (!raw?.token) {
    return null;
  }

  const trimmed: TrimmedCask = {
    token: raw.token,
    full_token: typeof raw.full_token === "string" && raw.full_token.length > 0
      ? raw.full_token
      : raw.token,
    name: normalizeNameArray(raw.name, raw.token),
  };

  const desc = sanitizeString(raw.desc);
  if (desc) trimmed.desc = desc;

  const homepage = sanitizeString(raw.homepage);
  if (homepage) trimmed.homepage = homepage;

  if (raw.deprecated === true) {
    trimmed.deprecated = true;
  }

  const artifacts = extractAppArtifacts(raw.artifacts);
  if (artifacts.length > 0) {
    trimmed.artifacts = artifacts;
  }

  return trimmed;
}

function normalizeNameArray(value: unknown, fallback: string): string[] {
  if (Array.isArray(value)) {
    const names = value
      .map((entry) => sanitizeString(entry))
      .filter((entry): entry is string => Boolean(entry));
    if (names.length > 0) {
      return names;
    }
  } else if (typeof value === "string") {
    const normalized = sanitizeString(value);
    if (normalized) {
      return [normalized];
    }
  }
  return [fallback];
}

function sanitizeString(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function extractAppArtifacts(value: unknown): Array<{ app: string[] }> {
  if (!Array.isArray(value)) {
    return [];
  }

  const artifacts: Array<{ app: string[] }> = [];

  for (const artifact of value) {
    if (!artifact || typeof artifact !== "object") {
      continue;
    }
    const apps = normalizeStringArray(
      (artifact as Record<string, unknown>)["app"],
    );
    if (apps.length > 0) {
      artifacts.push({ app: apps });
    }
  }

  return artifacts;
}

function normalizeStringArray(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value
      .map((entry) => sanitizeString(entry))
      .filter((entry): entry is string => Boolean(entry));
  }
  const single = sanitizeString(value);
  return single ? [single] : [];
}

async function writeJSON(path: string, value: unknown) {
  const text = JSON.stringify(value, null, 2) + "\n";
  await Deno.writeTextFile(path, text);
}
