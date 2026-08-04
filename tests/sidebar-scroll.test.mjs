import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const styles = await readFile(new URL("../src/styles.css", import.meta.url), "utf8");

test("a navegação lateral rola sem empurrar o utilizador e o logout", () => {
  const nav = styles.match(/\.sidebar nav\s*\{([\s\S]*?)\}/)?.[1] || "";
  const user = styles.match(/\.sidebar-user\s*\{([\s\S]*?)\}/)?.[1] || "";

  assert.match(nav, /flex:\s*1\s+1\s+auto/);
  assert.match(nav, /min-height:\s*0/);
  assert.match(nav, /overflow-y:\s*auto/);
  assert.match(nav, /scrollbar-gutter:\s*stable/);
  assert.match(user, /flex:\s*0\s+0\s+auto/);
});
