-- Migration: Update farms table for Farm Workflow system
-- Created: 2025-01-26
-- Purpose: Add polygon, start_date, end_date, and frequency (touches per month) to farms table

-- Enable PostGIS extension if not already enabled
CREATE EXTENSION IF NOT EXISTS postgis;

-- Add new columns to farms table
ALTER TABLE public.farms
    ADD COLUMN IF NOT EXISTS polygon GEOMETRY(Polygon, 4326),
    ADD COLUMN IF NOT EXISTS start_date DATE,
    ADD COLUMN IF NOT EXISTS end_date DATE,
    ADD COLUMN IF NOT EXISTS frequency INTEGER DEFAULT 2; -- touches per month

-- Create spatial index on polygon column
CREATE INDEX IF NOT EXISTS idx_farms_polygon 
    ON public.farms USING GIST(polygon);

-- Create indexes for date queries
CREATE INDEX IF NOT EXISTS idx_farms_start_date 
    ON public.farms(start_date);

CREATE INDEX IF NOT EXISTS idx_farms_end_date 
    ON public.farms(end_date);

-- Add check constraint for date validity
ALTER TABLE public.farms
    ADD CONSTRAINT chk_farms_date_range 
    CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date);

-- Add check constraint for frequency
ALTER TABLE public.farms
    ADD CONSTRAINT chk_farms_frequency 
    CHECK (frequency IS NULL OR (frequency >= 1 AND frequency <= 4));

-- Update comment
COMMENT ON COLUMN public.farms.polygon IS 'PostGIS Polygon geometry (SRID 4326) defining the farm boundary';
COMMENT ON COLUMN public.farms.start_date IS 'Farm start date';
COMMENT ON COLUMN public.farms.end_date IS 'Farm end date';
COMMENT ON COLUMN public.farms.frequency IS 'Number of touches per month (1-4)';



