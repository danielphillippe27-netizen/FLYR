"""Run against an EMPTY disposable PostgreSQL database using CALL_GUARD_TEST_DSN.
Exercises the actual migration, including overlapping transactions. No production DSN.
"""
import os
from pathlib import Path
import subprocess
from concurrent.futures import ThreadPoolExecutor
import time

DSN = os.environ['CALL_GUARD_TEST_DSN']
def sql(query, ok=True):
    result = subprocess.run(['psql', DSN, '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-c', query], capture_output=True, text=True)
    if ok:
        assert result.returncode == 0, result.stderr
    else:
        assert result.returncode != 0 and 'recently called' in result.stderr, result.stderr
    return result.stdout.strip()

assert sql('SELECT current_database()').startswith('wolfgrid_call_guard_test'), 'Use a disposable test database'
assert sql("SELECT to_regclass('public.dialer_calls') IS NULL") == 't', 'Database must be empty'
sql("""
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY, raw_user_meta_data jsonb);
CREATE TABLE public.dialer_calls (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), workspace_id uuid NOT NULL,
 user_id uuid, to_number_e164 text, direction text, status text,
 call_request_id uuid, status_payload jsonb, created_at timestamptz DEFAULT now()
);
INSERT INTO auth.users VALUES
 ('00000000-0000-0000-0000-000000000001', '{"full_name":"Jamie"}'),
 ('00000000-0000-0000-0000-000000000002', '{"full_name":"Alex"}');
""")
sql((Path(__file__).parents[1] / 'migrations/20260909220000_shared_lead_call_guard.sql').read_text())

def insert(phone='+14165550123', user=1, workspace=1, status='pending', double=False, age='0 hours', direction='outbound'):
    return f"""INSERT INTO public.dialer_calls(workspace_id,user_id,to_number_e164,direction,status,call_request_id,status_payload,created_at)
    VALUES ('10000000-0000-0000-0000-{workspace:012}', '00000000-0000-0000-0000-{user:012}',
    '{phone}', '{direction}', '{status}', gen_random_uuid(), '{{"doubleDial":{str(double).lower()}}}', now()-interval '{age}');"""

sql(insert())
sql(insert(user=2), ok=False)
sql(insert(), ok=False)
sql(insert(user=2, double=True), ok=False)
sql(insert(double=True), ok=False)  # Cannot retry an active call.
sql("UPDATE dialer_calls SET status='no-answer'")
sql(insert(double=True))
sql("UPDATE dialer_calls SET status='no-answer'")
sql(insert(double=True), ok=False)  # Only one deliberate immediate retry.
sql(insert(workspace=2))  # Independent workspace.
sql(insert(phone='+14165550124'))  # Independent phone.
sql(insert(status='completed', direction='inbound'))  # Webhook history is not blocked.
sql(insert(phone='+14165550125', status='completed', age='25 hours'))
sql(insert(phone='+14165550125', user=2))
sql(insert(phone='+14165550126', status='completed', age='2 hours'))
sql(insert(phone='+14165550126', user=2), ok=False)  # Pre-migration history counts too.
assert sql("SELECT last_called_by FROM shared_lead_call_history('10000000-0000-0000-0000-000000000001', ARRAY['+14165550123'])") == 'Jamie'
assert sql("SELECT count(*) FROM shared_lead_call_history('90000000-0000-0000-0000-000000000001', ARRAY['+14165550123'])") == '0'
assert sql("SELECT has_function_privilege('authenticated', 'shared_lead_call_history(uuid,text[])','EXECUTE')") == 'f'
assert sql("SELECT has_function_privilege('service_role', 'shared_lead_call_history(uuid,text[])','EXECUTE')") == 't'
# A failed enclosing transaction must not leave behind a reservation.
sql('BEGIN; ' + insert(phone='+14165550127') + ' ROLLBACK;')
sql(insert(phone='+14165550127', user=2))
# Hold the phone lock in one transaction while a second rep tries to dial.
with ThreadPoolExecutor() as pool:
    first = pool.submit(sql, 'BEGIN; ' + insert(phone='+14165550128') + ' SELECT pg_sleep(1); COMMIT;')
    time.sleep(0.2)
    second = pool.submit(sql, insert(phone='+14165550128', user=2), False)
    first.result()
    second.result()
assert sql("SELECT count(*) FROM dialer_calls WHERE to_number_e164='+14165550128'") == '1'
print('PASS: duplicate attempts, active calls, deliberate retry limit, workspace/phone isolation, historical calls, permissions, rollback and concurrent callers')
