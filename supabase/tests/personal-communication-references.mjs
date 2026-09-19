const { PGlite } = await import(process.env.PGLITE_MODULE_PATH || '@electric-sql/pglite');
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
const a='00000000-0000-0000-0000-000000000001',b='00000000-0000-0000-0000-000000000002',w='00000000-0000-0000-0000-000000000003';
await db.exec(`CREATE TABLE sales_contacts(id uuid,workspace_id uuid,owner_user_id uuid);
CREATE TABLE sales_leads(id uuid,workspace_id uuid,assigned_user_id uuid);
INSERT INTO sales_contacts VALUES ('${a}','${w}','${a}'),('${b}','${w}','${b}');
INSERT INTO sales_leads SELECT * FROM sales_contacts;
CREATE TABLE communication_events(id uuid,workspace_id uuid,actor_user_id uuid,sales_contact_id uuid,sales_lead_id uuid,body text);
CREATE TABLE communication_threads(id uuid,workspace_id uuid,assigned_user_id uuid,sales_contact_id uuid,sales_lead_id uuid);
INSERT INTO communication_events VALUES ('${a}','${w}','${a}','${b}','${b}','Preserve my message');
INSERT INTO communication_threads VALUES ('${a}','${w}','${a}','${b}','${b}');`);
await db.exec(readFileSync(new URL('../migrations/20260909070000_personal_communication_references.sql',import.meta.url),'utf8'));
assert.equal((await db.query('SELECT body FROM communication_events')).rows[0].body,'Preserve my message');
for(const table of ['communication_events','communication_threads']) {
 const row=(await db.query(`SELECT * FROM ${table}`)).rows[0];
 assert.equal(row.sales_contact_id,null);assert.equal(row.sales_lead_id,null);
 await db.exec(`UPDATE ${table} SET sales_contact_id='${a}',sales_lead_id='${a}' WHERE id='${a}'`);
 await assert.rejects(db.exec(`UPDATE ${table} SET sales_contact_id='${b}' WHERE id='${a}'`),/contact owner/);
 await assert.rejects(db.exec(`UPDATE ${table} SET sales_lead_id='${b}' WHERE id='${a}'`),/lead owner/);
}
console.log('PASS: historical foreign links detached with messages preserved; even privileged writes cannot attach foreign contacts/leads.');
await db.close();
