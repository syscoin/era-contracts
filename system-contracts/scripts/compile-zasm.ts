// hardhat import should be the first import in the file
import type { CompilerPaths } from "./utils";
import { spawn, compilerLocation, prepareCompilerPaths } from "./utils";
import * as fs from "fs";

const COMPILER_VERSION = "1.5.11";
const IS_COMPILER_PRE_RELEASE = false;

export async function compileZasm(paths: CompilerPaths, file: string) {
  const zksolcLocation = await compilerLocation(COMPILER_VERSION, IS_COMPILER_PRE_RELEASE);
  await spawn(
    `${zksolcLocation} ${paths.absolutePathSources}/${file} --eravm-assembly --bin --overwrite -o ${paths.absolutePathArtifacts}`
  );
}

export async function compileZasmFolder(path: string) {
  const paths = prepareCompilerPaths(path);
  const files: string[] = (await fs.promises.readdir(path)).filter((fn) => fn.endsWith(".zasm"));
  for (const file of files) {
    await compileZasm(paths, `${file}`);
  }
}

// Currently used only for the test contracts
async function main() {
  await compileZasmFolder("contracts-preprocessed/test-contracts");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Error:", err.message || err);
    process.exit(1);
  });
