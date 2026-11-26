// Sign in with an emailed 6-digit code (also how a new account is made), or
// with a password for accounts that have one. No passkeys or Google here
// yet: the server only accepts those from favcircles.com and the iOS app.
import { useState, type FormEvent } from 'react';
import { ApiError, messageOf } from '../api/client';
import { forgotPassword, passwordLogin, startEmailCode, verifyEmailCode } from '../api/auth';
import { useAuth } from '../auth/AuthContext';
import './login.css';

type Step = 'email' | 'code' | 'password';

export function LoginPage() {
  const { signIn } = useAuth();
  const [step, setStep] = useState<Step>('email');
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [name, setName] = useState('');
  const [password, setPassword] = useState('');
  const [isNew, setIsNew] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');

  const cleanEmail = email.replace(/\s+/g, '').toLowerCase();
  const run = async (work: () => Promise<void>) => {
    setError('');
    setNote('');
    setBusy(true);
    try { await work(); } catch (e) { setError(messageOf(e)); } finally { setBusy(false); }
  };

  const sendCode = (event: FormEvent) => {
    event.preventDefault();
    if (!/^[^@]+@[^@]+\.[^@]+$/.test(cleanEmail)) { setError('Enter your email address.'); return; }
    run(async () => {
      const { newAccount } = await startEmailCode(cleanEmail);
      setIsNew(newAccount === true);
      setCode('');
      setStep('code');
    });
  };

  const checkCode = (event: FormEvent) => {
    event.preventDefault();
    const digits = code.replace(/\D/g, '');
    const cleanName = name.replace(/\s+/g, ' ').trim();
    if (digits.length !== 6) { setError('Enter the 6 digits from the email.'); return; }
    if (isNew && cleanName.length < 2) { setError('Add your name to finish.'); return; }
    run(async () => {
      try {
        signIn(await verifyEmailCode(cleanEmail, digits, isNew ? cleanName : undefined));
      } catch (e) {
        if (e instanceof ApiError && e.code === 'NAME_REQUIRED') { setIsNew(true); setError('Add your name to finish.'); return; }
        throw e;
      }
    });
  };

  const usePassword = (event: FormEvent) => {
    event.preventDefault();
    if (!password) { setError('Enter your password.'); return; }
    run(async () => { signIn(await passwordLogin(cleanEmail, password)); });
  };

  const resetPassword = () => run(async () => {
    if (!/^[^@]+@[^@]+\.[^@]+$/.test(cleanEmail)) { setError('Enter your email address first.'); return; }
    await forgotPassword(cleanEmail);
    setNote('If that email has an account, a reset link is on its way.');
  });

  return (
    <main className="login">
      <div className="login-art" aria-hidden="true">
        <span className="pin p1">📍</span><span className="pin p2">☕</span><span className="pin p3">🍽️</span><span className="pin p4">🌲</span>
      </div>
      <section className="login-panel card">
        <p className="login-brand">FavCircles</p>
        <h1>Your own map of the places you love.</h1>
        <p className="muted login-sub">Save places into circles, share them with friends, and see theirs.</p>

        {step === 'email' ? (
          <form onSubmit={sendCode} noValidate>
            <label className="field"><span>Your email</span>
              <input type="email" autoComplete="email" inputMode="email" placeholder="you@example.com" value={email} onChange={(e) => setEmail(e.target.value)} autoFocus />
            </label>
            <button className="btn block" type="submit" disabled={busy}>{busy ? 'Sending your code…' : 'Email me a sign-in code'}</button>
            <button className="btn block plain" type="button" onClick={() => { setError(''); setStep('password'); }}>Use a password instead</button>
            <p className="small muted login-fine">New here? The same code creates your account. By continuing you agree to the <a href="https://favcircles.com/terms.html">terms</a> and <a href="https://favcircles.com/privacy.html">privacy policy</a>.</p>
          </form>
        ) : null}

        {step === 'code' ? (
          <form onSubmit={checkCode} noValidate>
            <label className="field"><span>The 6-digit code we emailed to {cleanEmail}</span>
              <input className="login-code" type="text" inputMode="numeric" autoComplete="one-time-code" maxLength={6} placeholder="000000" value={code} onChange={(e) => setCode(e.target.value)} autoFocus />
            </label>
            {isNew ? (
              <label className="field"><span>Your name</span>
                <input type="text" autoComplete="name" maxLength={50} placeholder="First and last name" value={name} onChange={(e) => setName(e.target.value)} />
              </label>
            ) : null}
            <button className="btn block" type="submit" disabled={busy}>{busy ? 'Signing you in…' : isNew ? 'Create my account' : 'Sign in'}</button>
            <button className="btn block plain" type="button" onClick={() => { setError(''); setStep('email'); }}>Use a different email</button>
          </form>
        ) : null}

        {step === 'password' ? (
          <form onSubmit={usePassword} noValidate>
            <label className="field"><span>Your email</span>
              <input type="email" autoComplete="email" inputMode="email" value={email} onChange={(e) => setEmail(e.target.value)} autoFocus />
            </label>
            <label className="field"><span>Password</span>
              <input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} />
            </label>
            <button className="btn block" type="submit" disabled={busy}>{busy ? 'Signing you in…' : 'Sign in'}</button>
            <button className="btn block plain" type="button" onClick={() => { setError(''); setStep('email'); }}>Email me a code instead</button>
            <button className="btn block plain" type="button" onClick={resetPassword} disabled={busy}>Forgot your password?</button>
          </form>
        ) : null}

        <p className="err" role="alert">{error}</p>
        {note ? <p className="small muted" role="status">{note}</p> : null}
      </section>
      <p className="small login-foot">Have an iPhone? <a href="https://apps.apple.com/us/app/favcircles/id6746807095">Get the app</a></p>
    </main>
  );
}
