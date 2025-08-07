#!/usr/bin/env -S pkgx deno run -A

import { basename } from "https://deno.land/std@0.206.0/path/mod.ts";

interface CaskArtifact {
  app?: string[];
  pkg?: string[];
  [key: string]: any;
}

interface Cask {
  token: string;
  full_token: string;
  name: string[];
  desc: string;
  homepage: string;
  artifacts: CaskArtifact[];
  [key: string]: any;
}

interface ParsedCask {
  token: string;
  name: string;
  description: string;
  homepage: string;
  brewInstallCommand: string;
}

async function downloadCasks(): Promise<Cask[]> {
  const url = 'https://formulae.brew.sh/api/cask.json';
  const cacheFile = `./Data/${basename(url)}`;

  let etag: string | null = null;
  let cachedData: Cask[] | null = null;

  // Check if we have cached data
  try {
    const cache = await Deno.readTextFile(cacheFile);
    const { data, etag: storedEtag } = JSON.parse(cache);
    etag = storedEtag;
    cachedData = data;
  } catch (err) {
    console.log("No cached data found, fetching fresh data...");
  }

  // Setup headers with If-None-Match if we have an ETag
  const headers: HeadersInit = {};
  if (etag) {
    headers["If-None-Match"] = etag;
  }

  const response = await fetch(url, { headers });

  if (response.status === 304 && cachedData) {
    console.log("Using cached data (not modified)");
    return cachedData;
  } else if (response.ok) {
    console.log("Downloading fresh data...");
    const newEtag = response.headers.get("ETag");
    const jsonData = await response.json();

    // Cache the new data along with the new ETag
    await Deno.writeTextFile(cacheFile, JSON.stringify({etag: newEtag, data: jsonData}, null, 2));

    return jsonData;
  } else {
    throw new Error(`Failed to fetch data: ${response.statusText}`);
  }
}

function parseCasks(casks: Cask[]): ParsedCask[] {
  return casks.map(cask => {
    // Get the primary name (first name in the array)
    const name = cask.name[0] || cask.token;
    
    // Get description (fallback to empty string if not available)
    const description = cask.desc || '';
    
    // Get homepage
    const homepage = cask.homepage || '';
    
    // Generate brew install command
    const brewInstallCommand = `brew install --cask ${cask.token}`;

    return {
      token: cask.token,
      name,
      description,
      homepage,
      brewInstallCommand
    };
  });
}

function outputResults(parsedCasks: ParsedCask[], format: 'json' | 'csv' | 'table' = 'json') {
  switch (format) {
    case 'json':
      console.log(JSON.stringify(parsedCasks, null, 2));
      break;
    
    case 'csv':
      console.log('token,name,description,homepage,brewInstallCommand');
      parsedCasks.forEach(cask => {
        const escapedName = `"${cask.name.replace(/"/g, '""')}"`;
        const escapedDesc = `"${cask.description.replace(/"/g, '""')}"`;
        const escapedHomepage = `"${cask.homepage.replace(/"/g, '""')}"`;
        const escapedCommand = `"${cask.brewInstallCommand.replace(/"/g, '""')}"`;
        console.log(`${cask.token},${escapedName},${escapedDesc},${escapedHomepage},${escapedCommand}`);
      });
      break;
    
    case 'table':
      console.log('┌─────────────────────┬─────────────────────┬─────────────────────┬─────────────────────┬─────────────────────┐');
      console.log('│ Token               │ Name                │ Description         │ Homepage            │ Brew Install        │');
      console.log('├─────────────────────┼─────────────────────┼─────────────────────┼─────────────────────┼─────────────────────┤');
      parsedCasks.slice(0, 10).forEach(cask => {
        const token = cask.token.padEnd(19).slice(0, 19);
        const name = cask.name.padEnd(19).slice(0, 19);
        const desc = cask.description.padEnd(19).slice(0, 19);
        const homepage = cask.homepage.padEnd(19).slice(0, 19);
        const command = cask.brewInstallCommand.padEnd(19).slice(0, 19);
        console.log(`│ ${token} │ ${name} │ ${desc} │ ${homepage} │ ${command} │`);
      });
      console.log('└─────────────────────┴─────────────────────┴─────────────────────┴─────────────────────┴─────────────────────┘');
      if (parsedCasks.length > 10) {
        console.log(`... and ${parsedCasks.length - 10} more casks`);
      }
      break;
  }
}

async function main() {
  const args = Deno.args;
  const format = args.includes('--csv') ? 'csv' : 
                 args.includes('--table') ? 'table' : 'json';
  
  const limit = args.find(arg => arg.startsWith('--limit='))?.split('=')[1];
  const limitNumber = limit ? parseInt(limit, 10) : undefined;

  try {
    console.error("Downloading cask data...");
    const casks = await downloadCasks();
    
    console.error(`Found ${casks.length} casks`);
    console.error("Parsing cask data...");
    
    let parsedCasks = parseCasks(casks);
    
    if (limitNumber && limitNumber > 0) {
      parsedCasks = parsedCasks.slice(0, limitNumber);
      console.error(`Limited output to first ${limitNumber} casks`);
    }
    
    console.error("Outputting results...");
    outputResults(parsedCasks, format);
    
  } catch (error) {
    console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    Deno.exit(1);
  }
}

// Run the script if this file is executed directly
if (import.meta.main) {
  await main();
}

export { downloadCasks, parseCasks, type ParsedCask, type Cask };
