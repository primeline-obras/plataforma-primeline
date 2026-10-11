import test from 'node:test';
import assert from 'node:assert/strict';
import {expenseAmount,parseExpenseGrid} from '../src/financial-expenses-import.js';
const header=['Obra','JAN','FEV','MAR','ABR','MAI','JUN','JUL','AGO','SET','OUT','NOV','DEZ'];
test('valores financeiros estritos: zero, decimal português e inglês',()=>{for(const [v,n] of [[0,0],['0',0],['1.234,50',1234.5],['12.50',12.5],['-10,00',-10],['',null]])assert.equal(expenseAmount(v),n);for(const v of ['12 euros','=12*2','NaN','1,2,3','1e3','12abc',Infinity])assert.throws(()=>expenseAmount(v));});
test('grelha mantém todas as linhas; inválidas impedem confirmação',()=>{const p=parseExpenseGrid([header,['Despesas Sede',0],['120',25],['999',12],['Despesas Armazém','12 euros']],[{id:'work',numero:120}]);assert.equal(p.rows.length,2);assert.equal(p.errors.length,2);assert.equal(p.rows[0].meses[0],0);assert.equal(p.rows[1].obra_id,'work');assert.equal(p.rows[0].linha,2);});
test('estrutura e obra ambígua recusadas, sem inferência',()=>{assert.throws(()=>parseExpenseGrid([['Obra','FEV','JAN']]));assert.throws(()=>parseExpenseGrid([header]));const p=parseExpenseGrid([header,['120',1]],[{id:'a',numero:120},{id:'b',numero:120}]);assert.equal(p.errors.length,1);assert.equal(p.rows.length,0);});
