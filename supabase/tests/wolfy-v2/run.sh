#!/bin/bash
set -euo pipefail
# Creates a disposable local DB; does not read project secrets or contact hosted Supabase.
root="$(cd "$(dirname "$0")/../../.." && pwd)"
container="wolfy-v2-test-$RANDOM-$$"
cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker run --name "$container" -e POSTGRES_PASSWORD=local-wolfy-test -d postgres:17-alpine >/dev/null
for attempt in {1..30}; do
 if docker exec "$container" pg_isready -U postgres >/dev/null 2>&1; then break; fi
 sleep 1
done
for file in \
 "$root/supabase/tests/wolfy-v2/fixture.sql" \
 "$root/supabase/pending/wolfy-v2/20260915210000_wolfy_pack_v2_foundation.sql" \
 "$root/supabase/tests/wolfy-v2/projection-fixture.sql" \
 "$root/supabase/pending/wolfy-v2/20260915211000_wolfy_pack_v2_projection.sql" \
 "$root/supabase/tests/wolfy-v2/policies.sql" \
 "$root/supabase/tests/wolfy-v2/projection-policies.sql" \
 "$root/supabase/tests/wolfy-v2/rollout-policies.sql" \
 "$root/supabase/tests/wolfy-v2/activity-fixture.sql" \
 "$root/supabase/pending/wolfy-v2/20260915212000_wolfy_v2_activity.sql" \
 "$root/supabase/pending/wolfy-v2/20260915213000_wolfy_v2_followups.sql" \
 "$root/supabase/pending/wolfy-v2/20260915214000_wolfy_pack_lifecycle.sql" \
 "$root/supabase/tests/wolfy-v2/activity-policies.sql" \
 "$root/supabase/tests/wolfy-v2/lifecycle-policies.sql" \
 "$root/supabase/tests/wolfy-v2/stats-fixture.sql" \
 "$root/supabase/pending/wolfy-v2/20260915215000_wolfy_pack_stats.sql" \
 "$root/supabase/tests/wolfy-v2/stats-policies.sql" \
 "$root/supabase/pending/wolfy-v2/20260915220000_wolfy_pack_achievements.sql" \
 "$root/supabase/pending/wolfy-v2/20260915221000_wolfy_pack_event_projection.sql" \
 "$root/supabase/tests/wolfy-v2/achievement-policies.sql" \
 "$root/supabase/pending/wolfy-v2/20260915222000_wolfy_pack_participants.sql" \
 "$root/supabase/tests/wolfy-v2/participant-policies.sql" \
 "$root/supabase/pending/wolfy-v2/20260915223000_wolfy_v2_participant_activity.sql" \
 "$root/supabase/tests/wolfy-v2/participant-activity.sql" \
 "$root/supabase/pending/wolfy-v2/20260915224000_wolfy_participant_intervals.sql" \
 "$root/supabase/tests/wolfy-v2/participant-activity.sql" \
 "$root/supabase/tests/wolfy-v2/participant-intervals.sql"; do
 docker exec -i "$container" psql -U postgres -v ON_ERROR_STOP=1 -q < "$file"
done
# Two independent connections cross the same campaign milestone concurrently.
docker exec -i "$container" psql -U postgres -v ON_ERROR_STOP=1 -q < "$root/supabase/tests/wolfy-v2/concurrent-setup.sql"
for door in 99 100; do
 docker exec "$container" psql -U postgres -v ON_ERROR_STOP=1 -q -c "INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES('30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','concurrent-$door','completed_manual')" &
 if [ "$door" = 99 ]; then first_job=$!; else second_job=$!; fi
done
wait "$first_job"
wait "$second_job"
docker exec -i "$container" psql -U postgres -v ON_ERROR_STOP=1 -q <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM wolfy_pack_events WHERE kind IN ('pack_goal','pack_milestone'))<>2 THEN
  RAISE EXCEPTION 'Concurrent writes did not yield exactly one goal and one milestone'; END IF;
 RAISE NOTICE 'Two simultaneous database connections: exactly one goal and one milestone passed';
END $$;
SQL
