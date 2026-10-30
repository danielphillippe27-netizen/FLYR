'use client';

import { useEffect, useState } from 'react';
import { Grid3X3 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';

const keys = [
  ['1', ''], ['2', 'ABC'], ['3', 'DEF'],
  ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'],
  ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'],
  ['*', ''], ['0', '+'], ['#', ''],
];

export function CallKeypad({ connected, callKey, onDigit, className }: {
  connected: boolean;
  callKey: string | null;
  onDigit: (digit: string) => boolean;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const [digits, setDigits] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    setOpen(false);
    setDigits('');
    setError('');
  }, [connected, callKey]);

  const pressDigit = (digit: string) => {
    if (!connected) return;
    if (onDigit(digit)) {
      setDigits((value) => (value + digit).slice(-24));
      setError('');
    } else {
      setError('Could not send the tone. Check that your call is connected.');
    }
  };

  return <>
    <Button type="button" variant="outline" disabled={!connected} onClick={() => setOpen(true)}
      aria-haspopup="dialog" aria-expanded={open && connected} className={className}>
      <Grid3X3 className="h-4 w-4" /> Keypad
    </Button>
    <Dialog open={open && connected} onOpenChange={setOpen}>
      <DialogContent className="max-w-xs" onKeyDown={(event) => {
        if (!event.ctrlKey && !event.metaKey && !event.altKey && /^[0-9*#]$/.test(event.key)) {
          event.preventDefault();
          event.stopPropagation();
          if (!event.repeat) pressDigit(event.key);
        }
      }}>
        <DialogHeader>
          <DialogTitle>Keypad</DialogTitle>
          <DialogDescription>Press a number for extensions or phone menus. You can also use your keyboard.</DialogDescription>
        </DialogHeader>
        <output aria-label="Digits sent" className="min-h-10 overflow-hidden text-center text-2xl font-medium tabular-nums">{digits || '\u00a0'}</output>
        <div className="grid grid-cols-3 gap-2">
          {keys.map(([digit, letters]) => <Button key={digit} type="button" variant="outline"
            aria-label={digit === '*' ? 'Star' : digit === '#' ? 'Pound' : digit}
            className="h-16 flex-col gap-0 text-2xl tabular-nums" onClick={() => pressDigit(digit)}>
            {digit}<span aria-hidden="true" className="h-4 text-[10px] tracking-widest text-muted-foreground">{letters}</span>
          </Button>)}
        </div>
        {error && <p role="alert" className="text-sm text-red-600">{error}</p>}
      </DialogContent>
    </Dialog>
  </>;
}
