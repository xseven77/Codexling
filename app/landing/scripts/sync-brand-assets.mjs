import { cp, mkdir, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const landingRoot = resolve(scriptDirectory, "..");
const source = resolve(landingRoot, "../../assets/brands/catalog");
const destination = resolve(landingRoot, "public/brand-assets");

await rm(destination, { recursive: true, force: true });
await mkdir(dirname(destination), { recursive: true });
await cp(source, destination, { recursive: true });
