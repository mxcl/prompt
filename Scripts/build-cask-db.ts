#!/usr/bin/env -S pkgx deno run -A

import { downloadCasks, parseCasks, type ParsedCask } from "./parse-casks.ts";

async function main() {
  const args = Deno.args;
  const outputFile = args.find(arg => arg.startsWith('--output='))?.split('=')[1] || './Data/parsed-casks.json';
  
  try {
    console.log("Downloading and parsing cask data...");
    const casks = await downloadCasks();
    const parsedCasks = parseCasks(casks);
    
    console.log(`Successfully parsed ${parsedCasks.length} casks`);
    console.log(`Writing to ${outputFile}...`);
    
    await Deno.writeTextFile(outputFile, JSON.stringify(parsedCasks, null, 2));
    
    console.log("✅ Done! Parsed cask data saved.");
    console.log(`📁 Output file: ${outputFile}`);
    console.log(`📊 Total casks: ${parsedCasks.length}`);
    
    // Show a few examples
    console.log("\n🔍 Sample data:");
    parsedCasks.slice(0, 3).forEach((cask, index) => {
      console.log(`${index + 1}. ${cask.name} (${cask.token})`);
      console.log(`   Description: ${cask.description}`);
      console.log(`   Homepage: ${cask.homepage}`);
      console.log(`   Install: ${cask.brewInstallCommand}`);
      console.log("");
    });
    
  } catch (error) {
    console.error(`❌ Error: ${error instanceof Error ? error.message : String(error)}`);
    Deno.exit(1);
  }
}

if (import.meta.main) {
  await main();
}
