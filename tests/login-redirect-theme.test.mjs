import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");

test("o ecrã de login usa sempre o tema claro sem apagar a preferência", () => {
  assert.match(app, /applySavedThemeInitially\s*=\s*Boolean\(initialSession\s*\|\|\s*!isSupabaseConfigured\)/);
  assert.match(app, /applySavedThemeInitially\s*&&\s*savedTheme\s*===\s*"dark"\s*\?\s*"dark"\s*:\s*"light"/);
  assert.match(app, /function applyLoginTheme\(\)[\s\S]*dataset\.theme\s*=\s*"light"/);
  assert.doesNotMatch(
    app.match(/function applyLoginTheme\(\)[\s\S]*?\n}/)?.[0] || "",
    /localStorage\.setItem\(UI_THEME_KEY/,
  );
  assert.match(app, /primeline:session-expired[\s\S]*applyLoginTheme\(\)/);
  assert.match(app, /#logout[\s\S]*applyLoginTheme\(\)/);
});

test("cada login concluído redireciona para o ecrã inicial do papel", () => {
  assert.match(app, /function redirectToRoleHome\(\)[\s\S]*history\.replaceState[\s\S]*switchView\(defaultViewForCurrentUser\(\)\)/);
  assert.match(app, /session\s*=\s*await signIn[\s\S]*await loadData\(\);\s*redirectToRoleHome\(\)/);
  assert.match(app, /defaultViewForCurrentUser[\s\S]*includes\("action-plan"\)[\s\S]*includes\("overview"\)/);
});
