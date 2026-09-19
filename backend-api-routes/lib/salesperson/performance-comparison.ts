export type PerformancePeriod = 'daily' | 'weekly' | 'monthly' | 'yearly';

export type ComparisonRange = {
  start: Date;
  end: Date;
};

export type PerformanceRanges = {
  timezone: string;
  current: ComparisonRange;
  previous: ComparisonRange;
};

export type MetricComparison = {
  previousValue: number | null;
  percentageChange: number | null;
};

type ZonedParts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

const formatterCache = new Map<string, Intl.DateTimeFormat>();

function formatter(timezone: string): Intl.DateTimeFormat {
  const cached = formatterCache.get(timezone);
  if (cached) return cached;
  const value = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  });
  formatterCache.set(timezone, value);
  return value;
}

export function normalizeTimezone(value: string | null | undefined): string {
  const candidate = value?.trim() || 'UTC';
  try {
    formatter(candidate).format(new Date());
    return candidate;
  } catch {
    return 'UTC';
  }
}

function zonedParts(date: Date, timezone: string): ZonedParts {
  const parts = formatter(timezone).formatToParts(date);
  const value = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((part) => part.type === type)?.value ?? 0);
  return {
    year: value('year'),
    month: value('month'),
    day: value('day'),
    hour: value('hour'),
    minute: value('minute'),
    second: value('second'),
  };
}

function partsAsUtc(parts: ZonedParts): number {
  return Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second
  );
}

function zonedDate(parts: ZonedParts, timezone: string): Date {
  let timestamp = partsAsUtc(parts);
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const actual = zonedParts(new Date(timestamp), timezone);
    const correction = partsAsUtc(parts) - partsAsUtc(actual);
    if (correction === 0) break;
    timestamp += correction;
  }
  return new Date(timestamp);
}

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function shiftCalendarDays(parts: ZonedParts, amount: number): ZonedParts {
  const value = new Date(partsAsUtc(parts));
  value.setUTCDate(value.getUTCDate() + amount);
  return {
    year: value.getUTCFullYear(),
    month: value.getUTCMonth() + 1,
    day: value.getUTCDate(),
    hour: parts.hour,
    minute: parts.minute,
    second: parts.second,
  };
}

function shiftCalendarMonths(parts: ZonedParts, amount: number): ZonedParts {
  const monthIndex = parts.year * 12 + (parts.month - 1) + amount;
  const year = Math.floor(monthIndex / 12);
  const month = ((monthIndex % 12) + 12) % 12 + 1;
  return {
    ...parts,
    year,
    month,
    day: Math.min(parts.day, daysInMonth(year, month)),
  };
}

function shiftCalendarYears(parts: ZonedParts, amount: number): ZonedParts {
  const year = parts.year + amount;
  return {
    ...parts,
    year,
    day: Math.min(parts.day, daysInMonth(year, parts.month)),
  };
}

function startParts(period: PerformancePeriod, end: ZonedParts): ZonedParts {
  const midnight = { ...end, hour: 0, minute: 0, second: 0 };
  switch (period) {
    case 'weekly': {
      const weekday = new Date(Date.UTC(end.year, end.month - 1, end.day)).getUTCDay();
      return shiftCalendarDays(midnight, -((weekday + 6) % 7));
    }
    case 'monthly':
      return { ...midnight, day: 1 };
    case 'yearly':
      return { ...midnight, month: 1, day: 1 };
    case 'daily':
    default:
      return midnight;
  }
}

function previousParts(period: PerformancePeriod, parts: ZonedParts): ZonedParts {
  switch (period) {
    case 'weekly':
      return shiftCalendarDays(parts, -7);
    case 'monthly':
      return shiftCalendarMonths(parts, -1);
    case 'yearly':
      return shiftCalendarYears(parts, -1);
    case 'daily':
    default:
      return shiftCalendarDays(parts, -1);
  }
}

export function rangesForPeriod(
  period: PerformancePeriod,
  timezoneInput: string | null | undefined,
  now = new Date()
): PerformanceRanges {
  const timezone = normalizeTimezone(timezoneInput);
  const currentEndParts = zonedParts(now, timezone);
  const currentStartParts = startParts(period, currentEndParts);
  return {
    timezone,
    current: {
      start: zonedDate(currentStartParts, timezone),
      end: now,
    },
    previous: {
      start: zonedDate(previousParts(period, currentStartParts), timezone),
      end: zonedDate(previousParts(period, currentEndParts), timezone),
    },
  };
}

export function percentageChange(
  currentValue: number,
  previousValue: number | null
): number | null {
  if (previousValue === null || !Number.isFinite(previousValue)) return null;
  if (previousValue === 0) return currentValue === 0 ? 0 : null;
  return ((currentValue - previousValue) / previousValue) * 100;
}

export function metricComparison(
  currentValue: number,
  previousValue: number | null
): MetricComparison {
  return {
    previousValue,
    percentageChange: percentageChange(currentValue, previousValue),
  };
}
