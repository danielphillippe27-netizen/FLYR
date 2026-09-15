import { hiringSourceConfigured } from './postings';
import { theirStackConfigured } from './theirstack';

export function hiringSource() {
  if (theirStackConfigured() || !hiringSourceConfigured()) {
    return {
      name: 'TheirStack', configured: theirStackConfigured(), mode: 'webhook',
      attributionURL: 'https://theirstack.com',
      coverage: 'TheirStack aggregates job boards and company career sites. Coverage and hiring-contact availability vary; this is not every posting on every site.',
      collectionDescription: 'Door-to-door, canvassing, field sales and outside sales in Canada and the USA. New postings arrive automatically from the connected search.',
    };
  }
  return {
    name: 'Adzuna', configured: true, mode: 'daily', attributionURL: 'https://www.adzuna.com',
    coverage: 'Adzuna results only. Direct connections to Indeed, Glassdoor, LinkedIn and ZipRecruiter are not enabled.',
    collectionDescription: 'The latest three days, up to 500 postings per country daily. All job types and industries.',
  };
}
