'use client';

import { useEffect } from 'react';

export function WolfSocialPWARegister() {
  useEffect(() => {
    if (!('serviceWorker' in navigator) || !window.location.hostname.startsWith('social.')) return;
    void navigator.serviceWorker.register('/wolfsocial-sw.js');
  }, []);
  return null;
}
