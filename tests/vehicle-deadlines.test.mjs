import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const css = await readFile(new URL("../src/styles.css", import.meta.url), "utf8");

assert(app.includes('renderVehicleDeadline("SEGURO ATÉ", vehicle.seguro_data)'));
assert(app.includes('renderVehicleDeadline("PRÓXIMA INSPEÇÃO", vehicle.data_inspecao_proxima)'));
assert(app.includes("Última: ${formatOptionalDate(vehicle.data_revisao)}"));
assert(app.includes("data_proxima_revisao"));
assert(!app.includes("const dueDates = [vehicle.seguro_data, vehicle.data_revisao, vehicle.data_inspecao_proxima]"));
assert(app.includes('data-team-alert-filter="missing_contract"'));
assert(app.includes('data-team-alert-filter="birthday"'));
assert(app.includes('data-team-alert-filter="medicine_due"'));
assert(app.includes("function activateTeamTab"));

const tinySizes = [...css.matchAll(/font-size:\s*([5-8])px|font:\s*[^;{}]*?\s([5-8])px(?:[/\s;])/g)];
assert.equal(tinySizes.length, 0, "A interface não deve voltar a usar tipografia abaixo de 9 px.");

console.log("Prazos da frota separados e escala tipográfica mínima validada.");
