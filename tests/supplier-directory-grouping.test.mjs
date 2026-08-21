import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../src/subcontractors.js", import.meta.url), "utf8");
const styles = await readFile(new URL("../src/specialties.css", import.meta.url), "utf8");
const cardFunction = source.slice(source.indexOf("function renderDirectoryCard"), source.indexOf("function renderDirectoryGroup"));
const card = cardFunction.slice(cardFunction.indexOf("return \u0060<button"));

test("o diretório agrupa fornecedores por especialidade e deixa os não classificados no fim", () => {
  assert.match(source, /function directoryGroups\(rows\)/);
  assert.match(source, /state\.specialties\.map\(specialty/);
  assert.match(source, /groups\.push\(\{[\s\S]*id: "unclassified"[\s\S]*name: "Sem especialidade classificada"/);
  assert.match(source, /groups\.map\(renderDirectoryGroup\)/);
  assert.match(styles, /supplier-specialty-group/);
});

test("cada grupo ordena avaliados por média e não avaliados alfabeticamente", () => {
  assert.match(source, /function compareDirectoryRows\(left, right\)/);
  assert.match(source, /leftEvaluated !== rightEvaluated/);
  assert.match(source, /right\.metrics\.rating - left\.metrics\.rating/);
  assert.match(source, /localeCompare\([\s\S]*"pt-PT"/);
});

test("o cartão prioriza especialidade, nome e estrelas e omite adjudicado histórico", () => {
  const visibleName = card.indexOf('row.supplier.nome || "Fornecedor sem nome"');
  assert.ok(card.indexOf("supplier-primary-specialty") < visibleName);
  assert.ok(visibleName < card.indexOf("renderRating"));
  assert.doesNotMatch(card, /ADJUDICADO HISTÓRICO|metrics\.total/);
  assert.match(source, /supplier-rating-stars/);
  assert.match(styles, /supplier-rating-stars::before/);
});

test("o seletor de especialidade salta para o grupo sem filtrar a lista", () => {
  const rows = source.slice(source.indexOf("function directoryRows"), source.indexOf("function trustBadge"));
  assert.doesNotMatch(rows, /matchesSpecialty/);
  assert.match(source, /data-specialty-group/);
  assert.match(source, /scrollIntoView\(\{ behavior: "smooth", block: "start" \}\)/);
  assert.doesNotMatch(source, /data-supplier-sort/);
});
