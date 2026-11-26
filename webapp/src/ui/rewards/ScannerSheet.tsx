// "Scan a store code": the camera where the browser can read QR codes
// (BarcodeDetector + getUserMedia), and always a field for the 6 characters
// printed under the code. A window code saves the store (and pays its save
// bonus where rewards are live); a register code pays the visit's points.
import { useCallback, useEffect, useRef, useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { codeName, scan, type ScanInput, type ScanResult, type Voucher } from '../../api/rewards';
import { ApiError, messageOf } from '../../api/client';
import { parseScanInput, scanCouponLine, scanOutcome } from '../../logic/rewards';
import { Sheet, Spinner } from '../kit';
import { RewardBar } from './RewardBar';
import { askWhere } from './where';
import { rememberVenuePlace, storeRewardsPath } from './venuePlaces';
import './rewards.css';

interface Detector { detect(source: HTMLVideoElement): Promise<{ rawValue: string }[]> }
type DetectorClass = new (options?: { formats?: string[] }) => Detector;

const detectorClass = (): DetectorClass | null => {
  const found = (window as unknown as { BarcodeDetector?: DetectorClass }).BarcodeDetector;
  return typeof found === 'function' ? found : null;
};
/** Only where the browser can both open the camera and read a QR code. */
export const canScanWithCamera = (): boolean =>
  !!detectorClass() && !!(navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function');

const NOT_OURS = "That's not a FavCircles store code. Look for the FavCircles QR in the window or at the register.";
const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

type Step =
  | { name: 'enter' }
  | { name: 'working'; line: string }
  | { name: 'result'; data: ScanResult; storeName: string };

export function ScannerSheet({ onClose, onTicket }: { onClose: () => void; onTicket: (voucher: Voucher, storeName: string) => void }) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [step, setStep] = useState<Step>({ name: 'enter' });
  const [typed, setTyped] = useState('');
  const [error, setError] = useState('');
  const [camera, setCamera] = useState<'off' | 'starting' | 'on'>('off');
  const [cameraNote, setCameraNote] = useState('');
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const running = useRef(false);
  const cameraWorks = canScanWithCamera();

  const stopCamera = useCallback(() => {
    if (streamRef.current) streamRef.current.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    setCamera('off');
  }, []);
  useEffect(() => stopCamera, [stopCamera]);

  const run = useCallback(async (input: ScanInput) => {
    if (running.current) return;
    running.current = true;
    stopCamera();
    setError('');
    setStep({ name: 'working', line: 'Checking the code…' });
    try {
      // Which store, and which of its two codes: only the register one asks where the phone is
      const named = await codeName(input);
      const storeName = named.venueName || '';
      if (named.kind === 'generic') {
        setStep({ name: 'enter' });
        setError("That's the code for joining FavCircles, and you're already in. Enter the code from a store's window or register.");
        return;
      }
      setStep({
        name: 'working',
        line: named.kind === 'register'
          ? `Checking rewards at ${storeName || 'the store'}…`
          : `Saving ${storeName || 'the store'}…`
      });
      const where = named.kind === 'register' ? await askWhere() : {};
      let data = await scan(input, where);
      // The first circle of a brand-new account can take a moment: once more
      if (data.savePending) {
        await wait(2500);
        data = await scan(input, where);
      }
      if (data.venue) rememberVenuePlace(data.venue.venueId, data.venue.globalPlaceId);
      queryClient.invalidateQueries({ queryKey: ['rewards'] });
      if (data.saved) queryClient.invalidateQueries({ queryKey: ['circles'] });
      setStep({ name: 'result', data, storeName: (data.venue && data.venue.venueName) || storeName });
    } catch (e) {
      setStep({ name: 'enter' });
      setError(e instanceof ApiError && e.status === 404
        ? "We don't know that code. Check the 6 characters under the QR and try again."
        : messageOf(e));
    } finally {
      running.current = false;
    }
  }, [queryClient, stopCamera]);

  // ---- the camera
  const startCamera = async () => {
    const Detector = detectorClass();
    if (!Detector) return;
    setCameraNote('');
    setCamera('starting');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false });
      streamRef.current = stream;
      setCamera('on');
    } catch (e) {
      setCamera('off');
      const name = (e as Error).name;
      setCameraNote(name === 'NotAllowedError' || name === 'SecurityError'
        ? "FavCircles needs the camera to scan the store's QR code. Allow it in your browser's settings, or type the code instead."
        : "The camera couldn't start. Type the code instead.");
    }
  };
  useEffect(() => {
    const video = videoRef.current;
    const Detector = detectorClass();
    if (camera !== 'on' || !video || !streamRef.current || !Detector) return undefined;
    video.srcObject = streamRef.current;
    video.play().catch(() => undefined);
    let detector: Detector;
    try {
      detector = new Detector({ formats: ['qr_code'] });
    } catch {
      stopCamera();
      setCameraNote("This browser can't read QR codes. Type the code instead.");
      return undefined;
    }
    let looking = false;
    const timer = setInterval(async () => {
      if (looking || video.readyState < 2) return;
      looking = true;
      try {
        const found = await detector.detect(video);
        if (found.length > 0) {
          const input = parseScanInput(found[0].rawValue);
          if (input) run(input);
          else setCameraNote(NOT_OURS);
        }
      } catch {
        // A frame that couldn't be read: the next one will be
      } finally {
        looking = false;
      }
    }, 350);
    return () => clearInterval(timer);
  }, [camera, run, stopCamera]);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const input = parseScanInput(typed);
    if (!input) {
      setError(typed.trim().length === 0 ? 'Enter the 6 characters printed under the QR code.' : NOT_OURS);
      return;
    }
    run(input);
  };

  const again = () => { setTyped(''); setError(''); setCameraNote(''); setStep({ name: 'enter' }); };

  if (step.name === 'working') {
    return (
      <Sheet title="Scan a store code" onClose={onClose}>
        <Spinner />
        <p className="muted" style={{ textAlign: 'center', marginBottom: 30 }} role="status">{step.line}</p>
      </Sheet>
    );
  }

  if (step.name === 'result') {
    const { data, storeName } = step;
    const outcome = scanOutcome(data, storeName);
    const couponLine = scanCouponLine(data, storeName);
    const ticket = data.coupon && data.coupon.status === 'ticket' ? data.coupon.voucher : null;
    const live = data.loyaltyLive === true && !!data.venue;
    const points = data.venueBalance || 0;
    return (
      <Sheet title="Scan a store code" onClose={onClose}>
        <div className="scan-result">
          {storeName ? <p className="store">{storeName}</p> : null}
          <h3>{outcome.title}{outcome.gain ? <> <span className="rw-gain">{outcome.gain}</span></> : null}</h3>
          {outcome.detail ? <p className="detail">{outcome.detail}</p> : null}
          {couponLine ? <p className="card coupon">🎟️ {couponLine}</p> : null}
          {live ? (
            <div className="card scan-balance">
              <div className="row">
                <span className="grow">Your points at {storeName || 'this store'}</span>
                <strong style={{ fontSize: 20 }}>{points}</strong>
              </div>
              <RewardBar reward={data.nextReward} points={points} />
            </div>
          ) : null}
        </div>
        <div style={{ marginTop: 16 }}>
          {ticket ? (
            <button className="btn block" style={{ marginBottom: 8 }} onClick={() => onTicket(ticket, storeName)}>Show my coupon</button>
          ) : null}
          {data.venue && data.kind !== 'generic' ? (
            <button className={`btn block ${ticket ? 'soft' : ''}`}
              onClick={() => { onClose(); navigate(storeRewardsPath(data.venue!.venueId, data.venue!.globalPlaceId)); }}>
              {live ? `See rewards at ${storeName || 'the store'}` : `See ${storeName || 'the store'}`}
            </button>
          ) : null}
          <button className="btn block plain" onClick={again}>Scan another code</button>
          <button className="btn block plain" onClick={onClose}>Done</button>
        </div>
      </Sheet>
    );
  }

  return (
    <Sheet title="Scan a store code" onClose={onClose}>
      <p className="muted" style={{ marginBottom: 14 }}>
        Stores on FavCircles have a QR code in the window and one at the register. The window code saves the store; the register code is for when you buy something.
      </p>
      {cameraWorks && camera === 'on' ? (
        <div className="scan-view"><video ref={videoRef} muted playsInline aria-label="Camera: point it at the store's QR code" /></div>
      ) : null}
      {cameraWorks && camera !== 'on' ? (
        <button className="btn block soft" style={{ marginBottom: 14 }} onClick={startCamera} disabled={camera === 'starting'}>
          {camera === 'starting' ? 'Opening the camera…' : '📷 Scan with the camera'}
        </button>
      ) : null}
      {cameraNote ? <p className="small muted" style={{ margin: '-4px 2px 14px' }} role="status">{cameraNote}</p> : null}
      <form onSubmit={submit} noValidate>
        <label className="field"><span>{cameraWorks ? 'Or type the code under the QR' : 'Type the code printed under the QR'}</span>
          <input className="scan-code" type="text" inputMode="text" autoCapitalize="characters" autoCorrect="off" autoComplete="off" spellCheck={false}
            maxLength={80} placeholder="ABC123" value={typed} onChange={(e) => { setTyped(e.target.value); setError(''); }} />
        </label>
        {!cameraWorks ? (
          <p className="small muted" style={{ margin: '-6px 2px 12px' }}>
            This browser can’t read QR codes here. Your phone’s camera app can: point it at the code and it opens the store’s page.
          </p>
        ) : null}
        <p className="err" role="alert">{error}</p>
        <button className="btn block" type="submit" style={{ marginTop: 12 }}>Continue</button>
        <button className="btn block plain" type="button" onClick={onClose}>Cancel</button>
      </form>
    </Sheet>
  );
}
