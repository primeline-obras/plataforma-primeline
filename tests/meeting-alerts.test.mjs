import assert from "node:assert/strict";
import fs from "node:fs";
import { alertsForOverviewRole } from "../src/production-dashboard.js";

const source = fs.readFileSync(new URL("../src/production-dashboard.js", import.meta.url), "utf8");
const meeting = { id: "m1", tipo: "reserva_sala", destinatario_utilizador_id: "u1", estado: "pendente" };
assert.deepEqual(alertsForOverviewRole([meeting], "financeiro", new Set(), "u1").map(row => row.id), ["m1"]);
assert.deepEqual(alertsForOverviewRole([meeting], "diretor_obra", new Set(), "u2"), []);
assert.deepEqual(alertsForOverviewRole([meeting], "encarregado", new Set(), "u1").map(row => row.id), ["m1"]);
assert.match(source, /isMeetingInformation\(alert\).*INFORMATIVO/s);
assert.match(source, /isMeetingInformation\(alert\).*MARCAR COMO RESOLVIDO/s);
console.log("Meeting participant alerts are personal and informational.");
