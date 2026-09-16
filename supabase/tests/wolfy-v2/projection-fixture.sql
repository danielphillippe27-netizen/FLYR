ALTER TABLE sessions ADD COLUMN start_time timestamptz DEFAULT now(), ADD COLUMN active_seconds integer DEFAULT 0;
CREATE TABLE profiles(id uuid PRIMARY KEY,first_name text,full_name text);
INSERT INTO profiles VALUES('00000000-0000-0000-0000-000000000001','Daniel','Daniel Private'),('00000000-0000-0000-0000-000000000002','Gabe','Gabe Private');
