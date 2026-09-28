import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const saveAllocation = app.slice(app.indexOf("async function saveWorkforceAllocation"),app.indexOf("async function removeWorkforceAllocation"));
test("alocar confirma transação e recarrega mantendo o scroll", () => {
 assert(saveAllocation.includes('workforceRequest(supabase, action, payload, true, preview.versao)'));
 assert(saveAllocation.includes('loadTeamData(true, true)'));
 assert(!saveAllocation.includes('method: "DELETE"'));
});
test("a atualização da grelha preserva scroll da página e grelha", () => {
 assert(app.includes('if (preserveScroll) renderTeamPreservingScroll();'));
 assert(app.includes('window.scrollTo(pagePosition.x, pagePosition.y)'));
 assert(app.includes('element.scrollTo({ top: position.top, left: position.left'));
});
