// Synthetic review artifact only; never reads an account or connects to a service.
import {writeFileSync} from 'node:fs';
import {analyze,KPI} from '../intelligence';
import {fixture,rep,campaign} from './field-fixture';
const c=fixture();c.scope='team';c.people.push({id:rep,name:'Jake'});c.rows.push({rep,campaign,day:c.local_day,values:{doors:'16',conversations:'8',leads:'0'}});
const report=analyze(c);
writeFileSync('../WolfGrid/Resources/Wolfy/wolfy_kpi_fixture.json',JSON.stringify(report));
writeFileSync('../docs/WOLFY_KPI_CATALOG.md','# Wolfy field KPI catalog\n\nBase KPIs; derived rates, historical changes, custom stages, goals, rep rankings and lifetime stats are also included.\n\n| KPI | Source | Unit | Period |\n|---|---|---|---|\n'+Object.entries(KPI).map(([id,k])=>`| ${k.label} (${id}) | ${k.source} | ${k.unit} | ${k.current?'Current snapshot':'Reporting period'} |`).join('\n')+'\n');
console.log(`${Object.keys(KPI).length} base KPI definitions; ${report.facts.length} synthetic report facts.`);
