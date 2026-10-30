export type DtmfCall = {
  dtmf?: (digit: string) => void;
  sendDigits?: (digit: string) => void;
};

export function sendCallDigit(provider: 'telnyx' | 'twilio', call: DtmfCall | null, digit: string): void {
  if (!/^[0-9*#]$/.test(digit)) throw new Error('Choose a keypad digit.');
  if (!call) throw new Error('Connect a call before using the keypad.');
  if (provider === 'telnyx' && call.dtmf) {
    call.dtmf(digit);
  } else if (provider === 'twilio' && call.sendDigits) {
    call.sendDigits(digit);
  } else {
    throw new Error('The keypad is unavailable for this call.');
  }
}
