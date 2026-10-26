'use client';

import { useEffect, useState } from 'react';
import { Input } from '@/components/ui/input';
import { MapboxAutocompleteService, type AddressSuggestion } from '@/lib/services/MapboxAutocompleteService';

export default function BusinessLocationInput({ id, value, onChange, disabled, includePlaces = false, required = false }: {
  id: string; value: string; onChange: (value: string) => void; disabled?: boolean; includePlaces?: boolean; required?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [suggestions, setSuggestions] = useState<AddressSuggestion[]>([]);
  const [active, setActive] = useState(-1);
  const [error, setError] = useState('');
  useEffect(() => {
    setSuggestions([]); setActive(-1); setError('');
    if (!open || disabled || value.trim().length < 3) return;
    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      MapboxAutocompleteService.searchAddresses(value.trim(), undefined, controller.signal, includePlaces)
        .then(results => { if (!controller.signal.aborted) setSuggestions(results); })
        .catch(() => { if (!controller.signal.aborted) setError('Address suggestions are unavailable. You can enter the address manually.'); });
    }, 300);
    return () => { window.clearTimeout(timer); controller.abort(); };
  }, [value, open, disabled, includePlaces]);
  function choose(suggestion: AddressSuggestion) {
    onChange(suggestion.fullAddress.slice(0, includePlaces ? 100 : 500));
    setOpen(false); setSuggestions([]); setActive(-1);
  }
  const expanded = open && suggestions.length > 0 && !disabled;
  return <div className="relative">
    <Input id={id} role="combobox" aria-autocomplete="list" aria-expanded={expanded} aria-controls={`${id}-suggestions`} aria-activedescendant={expanded && active >= 0 ? `${id}-suggestion-${active}` : undefined}
      autoComplete="off" value={value} required={required} minLength={required ? 2 : undefined} maxLength={includePlaces ? 100 : 500} disabled={disabled}
      placeholder={includePlaces ? 'Enter an address or city' : 'Enter a business address'}
      onChange={event => { onChange(event.target.value); setOpen(true); }} onFocus={() => setOpen(true)} onBlur={() => setOpen(false)}
      onKeyDown={event => {
        if (event.key === 'Escape') { setOpen(false); return; }
        if (!expanded) return;
        if (event.key === 'ArrowDown') { event.preventDefault(); setActive(index => (index + 1) % suggestions.length); }
        else if (event.key === 'ArrowUp') { event.preventDefault(); setActive(index => index <= 0 ? suggestions.length - 1 : index - 1); }
        else if (event.key === 'Enter' && active >= 0) { event.preventDefault(); choose(suggestions[active]); }
      }} />
    {expanded && <ul id={`${id}-suggestions`} role="listbox" aria-label="Mapbox address suggestions" className="absolute z-50 mt-1 max-h-64 w-full overflow-auto rounded-md border bg-popover shadow-md">
      {suggestions.map((suggestion, index) => <li key={suggestion.id} id={`${id}-suggestion-${index}`} role="option" aria-selected={active === index}
        className={`cursor-pointer px-3 py-2 text-sm hover:bg-accent ${active === index ? 'bg-accent' : ''}`}
        onMouseDown={event => event.preventDefault()} onClick={() => choose(suggestion)}>
        <div>{suggestion.title}</div><div className="text-xs text-muted-foreground">{suggestion.subtitle}</div>
      </li>)}
      <li role="presentation" className="px-3 py-1 text-xs text-muted-foreground">Powered by Mapbox</li>
    </ul>}
    {open && error && <p role="status" className="mt-1 text-xs text-muted-foreground">{error}</p>}
  </div>;
}
