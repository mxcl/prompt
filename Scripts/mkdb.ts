#!/usr/bin/env -S pkgx deno run -A

import { basename } from "https://deno.land/std@0.206.0/path/mod.ts";

const formulae = await get('https://formulae.brew.sh/api/formula.json')
const casks = await get('https://formulae.brew.sh/api/cask.json')


async function get(url: string) {
  const cacheFile = `./Data/${basename(url)}`;

  let etag: string | null = null;
  let cachedData: any = null;

  // Check if we have cached data
  try {
    const cache = await Deno.readTextFile(cacheFile);
    const { data, etag: storedEtag } = JSON.parse(cache);
    etag = storedEtag;
    cachedData = data;
  } catch (err) {
    // File doesn't exist, or error while reading cache, proceed with fetch
  }

  // Setup headers with If-None-Match if we have an ETag
  const headers: HeadersInit = {};
  if (etag) {
    headers["If-None-Match"] = etag;
  }

  const response = await fetch(url, { headers });

  if (response.status === 304) {
    return cachedData;
  } else if (response.ok) {
    const newEtag = response.headers.get("ETag");
    const jsonData = await response.json();

    // Cache the new data along with the new ETag
    await Deno.writeTextFile(cacheFile, JSON.stringify({etag: newEtag, data: jsonData}, null, 2));

    return jsonData;
  } else {
    throw new Error(`Failed to fetch data: ${response.statusText}`);
  }
}

for (const cask of casks) {
  const artifacts = cask.artifacts.flatMap(artifact => artifact.app || artifact.pkg).filter(x => x)
  console.log(artifacts)
}
