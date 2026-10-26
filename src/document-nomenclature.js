// The workbook is authoritative. IDs identify its rows, never inferred acronyms.
export const CATALOG_VERSION = '20261019';
export const CATALOG_SHA256 = '259adb516f6371f36db6119d394eb46482b93fceb9a04b823cd822964abb60e9';
export const tokens = item => [...new Set([...item.padrao_nome.matchAll(/\[([^\]]+)\]/g)].map(m => m[1]))];
export const hasSequence = item => tokens(item).includes('Nº');
export const hasRevision = item => tokens(item).includes('XX');
export function sequenceWidth(item) {
  if (/3 dígitos/u.test(item.observacoes || '')) return 3;
  const order=[];
  const pattern=item.padrao_nome.split(/(\[[^\]]+\])/g).map(p=>{
    if(p.startsWith('[')){order.push(p.slice(1,-1));return '(.+?)';}
    return p.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  }).join('');
  const m=new RegExp('^'+pattern+'$').exec(item.exemplo || ''), n=m?.[order.indexOf('Nº')+1];
  return n && /^\d+$/.test(n) ? n.length : 1;
}
export function filenamePart(value, label = 'Campo') {
  const text = String(value ?? '').normalize('NFC').trim();
  if (!text || text.length > 120 || /[<>:"/\\|?*\[\]\u0000-\u001f\u007f]/u.test(text) || /[. ]$/.test(text) || text === '.' || text === '..') {
    throw Error(`${label}: indique um valor válido, sem caracteres de caminho.`);
  }
  return text.replace(/\s+/gu, '_');
}
export function buildDocumentName(item, fields, { sequence, revision = 0, originalName, external = false, extension = '' } = {}) {
  if (external || item.padrao_nome === 'Manter nomenclatura original') {
    if (!originalName || /[\\/\u0000]/u.test(originalName)) throw Error('Indique o nome original do ficheiro.');
    return originalName; // No normalization of an external issuer's identity.
  }
  const values = { ...fields };
  if (item.linha_excel===49 && /\b(?:\d{4}[-_]\d{2}[-_]\d{2}|\d{2}[-_]\d{2}[-_]\d{4}|(?:19|20)\d{6})\b/.test(String(values.PERIODO || ''))) throw Error('Identifique o período por semana ou quinzena, sem data no nome.');
  if (item.linha_excel===35 && values.FASE) {
    item={...item,padrao_nome:item.padrao_nome.replace('_REV[XX]','_[FASE]_REV[XX]')};
  }
  if (hasRevision(item)) {
    if (!Number.isSafeInteger(revision) || revision < 0 || revision > 2147483647) throw Error('Revisão inválida.');
    values.XX = String(revision).padStart(2, '0');
  }
  if (hasSequence(item)) {
    if (!Number.isSafeInteger(sequence) || sequence < 1 || sequence > 999999999) throw Error('A sequência deve ser confirmada pelo servidor.');
    values['Nº'] = String(sequence).padStart(sequenceWidth(item), '0');
  }
  let name = item.padrao_nome.replace(/\[([^\]]+)\]/g, (_, token) => filenamePart(values[token], token));
  if (extension && !/^\.[a-zA-Z0-9]{1,10}$/.test(extension)) throw Error('Extensão inválida.');
  name += extension;
  if (name.length > 240) throw Error('O nome excede 240 caracteres. Reduza os campos descritivos.');
  return name;
}
export async function loadDocumentCatalog() {
  const r = await fetch(new URL('./document-nomenclature-catalog.json?v=20261020', import.meta.url));
  if (!r.ok) throw Error('Catálogo documental indisponível.');
  const c = await r.json();
  if (c.sha256_fonte !== CATALOG_SHA256 || c.itens?.length !== 66 || new Set(c.itens.map(i => i.linha_excel)).size !== 66) throw Error('Catálogo documental divergente.');
  return c;
}
