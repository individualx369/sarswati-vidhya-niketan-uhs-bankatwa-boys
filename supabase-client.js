// Browser-side Supabase client for the school portal.
// Loaded as an ES module from the official Supabase CDN.
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const config = window.SUPABASE_CONFIG;

if (!config?.url || !config?.publishableKey) {
  console.warn('Supabase configuration is missing.');
} else {
  window.supabaseClient = createClient(config.url, config.publishableKey);
  window.dispatchEvent(new CustomEvent('supabase:ready'));
}
