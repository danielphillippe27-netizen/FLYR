-- Add appointments column to user_stats for Stats screen (Conversations → Appointments % and Appointments row).
-- Populated later from CRM/contacts; default 0 until then.

ALTER TABLE public.user_stats
ADD COLUMN IF NOT EXISTS appointments INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.user_stats.appointments IS 'Number of appointments set (e.g. from leads/CRM); used for Stats screen C→A %';
