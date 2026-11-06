const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function warrantyContextRows(records,works,workId,date,timeline=[]) {
 const seen=new Set();return records.map(r=>{
 if(!r.id||seen.has(r.id)||!['garantia','outra'].includes(r.tipo)||r.data!==date||(workId&&r.origem_obra_id!==workId&&r.associada_obra_id!==workId)||!Number.isInteger(r.revision)||r.revision<1)throw Error('Referência operacional inconsistente');seen.add(r.id);
 const target=works.find(w=>w.id===r.associada_obra_id),original=works.find(w=>w.id===r.obra_original_id);
 return {id:r.id,revision:r.revision,date:r.data,kind:r.tipo,original_reference:r.referencia_original,origin_work:r.obra_original_id||null,associated_work:r.associada_obra_id||null,original_work_name:original?.name||r.obra_original_id||'Não identificada',associated_work_name:target?.name||r.associada_obra_id||'Por associar',context:target?.status==='fechada'?'REFERÊNCIA ASSOCIADA A OBRA ENCERRADA':target?'REFERÊNCIA ASSOCIADA A OBRA':'REFERÊNCIA POR ASSOCIAR',chronology:referenceChronology(r,timeline).label,chronology_code:referenceChronology(r,timeline).code,minutes:r.minutes,intervals:r.intervals,financial_effect:false};
 });
}
export function warrantyContextHtml(records,works,workId,date,timeline=[]){const rows=warrantyContextRows(records,works,workId,date,timeline);return `<details class="warranty-context"><summary>CONTEXTO DAS REFERÊNCIAS · ${rows.length}</summary><p>Garantia e Outra são destinos operacionais distintos dos pontos normais da obra. A associação não reabre a obra, não duplica os horários e não reconhece custos.</p>${rows.map(r=>`<article><h4>${r.kind==='garantia'?'GARANTIA':'OUTRA'} · ${esc(r.context)}</h4><p style="white-space:pre-wrap">${esc(r.original_reference)}</p><p>Origem ${esc(r.original_work_name)} · Associação ${esc(r.associated_work_name)} · ${esc(r.date)} · revisão ${r.revision}</p><small>${esc(r.chronology)}</small></article>`).join('')||'<p>Sem referências no contexto consultado.</p>'}${timeline.map(w=>`<details><summary>TRANSIÇÕES REGISTADAS · OBRA ${esc(w.work_id)}</summary><p>Estado atual: ${esc(w.status)}. O timestamp é da transição registada.</p>${(w.events||[]).map(e=>`<p>${esc(e.at)} · ${esc(e.before)} → ${esc(e.after)} · ${esc(e.source)} · ${esc(e.id)}</p>`).join('')||'<p>Sem transição factual registada. Não se atribui data retroativa.</p>'}</details>`).join('')}</details>`;}

export function referenceChronology(record,timeline){
 const result=(code,label)=>({code,label});
 if(record.tipo==='outra')return result('outra','REFERÊNCIA OUTRA · preserva o contrato próprio');
 if(!record.associada_obra_id)return result('garantia_por_associar','GARANTIA POR ASSOCIAR');
 const work=timeline.find(w=>w.work_id===record.associada_obra_id);
 if(!work)return result('desconhecida','CRONOLOGIA DESCONHECIDA · sem fonte de encerramento');
 const closed=s=>['fechada','concluida','concluido','concluído'].includes(s),events=[...(work.events||[])].filter(e=>e.date&&e.at&&e.before!==e.after).sort((a,b)=>a.at.localeCompare(b.at));
 if(events.some(e=>e.date===record.data))return result('mesmo_dia','CRONOLOGIA DESCONHECIDA · ponto diário e transição no mesmo dia');
 const past=events.filter(e=>e.date<record.data),latest=past.at(-1);
 if(latest){const simultaneous=past.filter(e=>e.at===latest.at);if(new Set(simultaneous.map(e=>e.after)).size>1)return result('desconhecida','CRONOLOGIA DESCONHECIDA · transições contraditórias');
 if(closed(latest.after))return result('posterior_encerramento','INTERVENÇÃO POSTERIOR AO ENCERRAMENTO REGISTADO · '+latest.date+' · '+latest.source);
 if(['em_curso','preparacao'].includes(latest.after))return result('obra_ativa','TRABALHO EM OBRA ATIVA · transição registada '+latest.date);
 }
 const futureClose=events.find(e=>e.date>record.data&&closed(e.after)&&!closed(e.before));
 if(futureClose)return result('anterior_encerramento','REFERÊNCIA ANTERIOR AO ENCERRAMENTO REGISTADO · '+futureClose.date+' · '+futureClose.source);
 return result('desconhecida','CRONOLOGIA DESCONHECIDA · estado atual não prova data histórica de encerramento');
}
