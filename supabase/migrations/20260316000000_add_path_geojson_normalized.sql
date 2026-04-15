-- Add normalized (Pro GPS) path for display; raw path remains in path_geojson for audit.
ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS path_geojson_normalized TEXT;

COMMENT ON COLUMN public.sessions.path_geojson_normalized IS 'Optional GeoJSON LineString of normalized breadcrumb trail (Pro GPS Normalization). When set, used for summary/share display; path_geojson remains raw.';
