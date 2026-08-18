import { describe, expect, it } from 'vitest';
import { assertStagingUrl, budapestDatePlusDays, EXPECTED_STAGING_URL } from './staging-uat-bootstrap.mjs';

describe('staging UAT bootstrap safety helpers', () => {
  it('accepts only the exact staging Supabase project URL', () => {
    expect(assertStagingUrl(EXPECTED_STAGING_URL)).toBe(EXPECTED_STAGING_URL);
    expect(assertStagingUrl(`${EXPECTED_STAGING_URL}/`)).toBe(EXPECTED_STAGING_URL);
  });

  it('fails closed for any other Supabase project URL', () => {
    expect(() => assertStagingUrl('https://production-example.supabase.co')).toThrow(/kizárólag a staging projekt/);
    expect(() => assertStagingUrl('https://fvwapntzhavhgazeflri.supabase.co.evil.example')).toThrow(/kizárólag a staging projekt/);
  });

  it('calculates relative dates from the Budapest calendar day', () => {
    const now = new Date('2026-03-28T23:30:00Z');
    expect(budapestDatePlusDays(0, now)).toBe('2026-03-29');
    expect(budapestDatePlusDays(20, now)).toBe('2026-04-18');
  });
});
