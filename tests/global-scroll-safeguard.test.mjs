import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const styles = await readFile(new URL("../src/workforce-calendar.css", import.meta.url), "utf8");
const html = await readFile(new URL("../index.html", import.meta.url), "utf8");

test("o documento conserva a rolagem vertical global", () => {
  assert.match(styles, /html\s*\{[\s\S]*?overflow-y:\s*scroll/);
  assert.match(styles, /body\s*\{[\s\S]*?overflow:\s*visible/);
  assert.match(styles, /scrollbar-gutter:\s*stable/);
});

test("as grelhas mantêm barras de rolagem visíveis", () => {
  assert.match(styles, /\.vacation-map-scroll::\-webkit-scrollbar[\s\S]*?height:\s*12px/);
  assert.match(styles, /\.management-map-scroll/);
  assert.match(styles, /\.financial-map-scroll/);
  assert.match(html, /workforce-calendar\.css\?v=4/);
});

test("a área central tem rolagem própria sem deslocar a barra lateral", () => {
  assert.match(styles, /\.app-shell\s*\{[\s\S]*?height:\s*100vh[\s\S]*?overflow:\s*hidden/);
  assert.match(styles, /main\s*\{[\s\S]*?height:\s*100vh[\s\S]*?overflow-y:\s*scroll/);
  assert.match(styles, /main::\-webkit-scrollbar\s*\{[\s\S]*?width:\s*12px/);
});
