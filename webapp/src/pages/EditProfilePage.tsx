// Edit my profile: name, bio, zip code and photo. Only what I changed is sent.
import { useEffect, useRef, useState, type ChangeEvent, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { messageOf } from '../api/client';
import { uploadImage } from '../api/upload';
import { me, updateMe } from '../api/users';
import { useAuth } from '../auth/AuthContext';
import { BIO_MAX, profileChanges, profileProblem } from '../logic/profileChanges';
import { Avatar, Head, LoadError, Spinner, toast } from '../ui/kit';
import './edit-profile.css';

export function EditProfilePage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { userId } = useAuth();
  const profile = useQuery({ queryKey: ['me'], queryFn: me });
  const saved = profile.data;

  const [displayName, setDisplayName] = useState('');
  const [bio, setBio] = useState('');
  const [zipcode, setZipcode] = useState('');
  const [picture, setPicture] = useState('');
  const [uploading, setUploading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const filled = useRef(false);
  const picker = useRef<HTMLInputElement>(null);

  // Fill the form once, from the first load: a background refresh must not
  // wipe what is being typed
  useEffect(() => {
    if (!saved || filled.current) return;
    filled.current = true;
    setDisplayName(saved.displayName || '');
    setBio(saved.bio || '');
    setZipcode(saved.zipcode || '');
  }, [saved]);

  const form = { displayName, bio, zipcode, profilePicture: picture };
  const changes = saved ? profileChanges(saved, form) : {};
  const dirty = Object.keys(changes).length > 0;

  const pick = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files && event.target.files[0];
    event.target.value = '';
    if (!file) return;
    setUploading(true);
    setError('');
    try {
      setPicture(await uploadImage(file, 800));
    } catch (e) {
      setError(messageOf(e));
    } finally {
      setUploading(false);
    }
  };

  const save = async (event: FormEvent) => {
    event.preventDefault();
    if (!saved) return;
    const problem = profileProblem(form);
    if (problem) { setError(problem); return; }
    if (!dirty) { navigate('/me'); return; }
    setBusy(true);
    setError('');
    try {
      await updateMe(changes);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['me'] }),
        userId ? queryClient.invalidateQueries({ queryKey: ['user', userId] }) : Promise.resolve()
      ]);
      toast('Profile saved');
      navigate('/me');
    } catch (e) {
      setError(messageOf(e));
      setBusy(false);
    }
  };

  const shownName = displayName.trim() || saved?.displayName || 'You';
  const zipChanged = !!saved && zipcode.trim() !== (saved.zipcode || '');

  return (
    <>
      <Head title="Edit profile" back />
      <main className="page">
        {profile.isPending ? <Spinner /> : null}
        {profile.isError && !saved ? <LoadError message={messageOf(profile.error)} retry={() => profile.refetch()} /> : null}
        {saved ? (
          <form onSubmit={save} noValidate className="edit-profile">
            <div className="edit-photo">
              <Avatar name={shownName} src={picture || saved.profilePicture} size={96} seed={saved._id} />
              <div>
                <button type="button" className="btn small soft" disabled={uploading || busy} onClick={() => picker.current?.click()}>
                  {uploading ? 'Uploading…' : (picture || saved.profilePicture) ? 'Change photo' : 'Add a photo'}
                </button>
                {picture ? <p className="small muted">New photo ready. Save to keep it.</p> : null}
              </div>
              <input ref={picker} type="file" accept="image/*" hidden onChange={pick} aria-label="Choose a profile photo" />
            </div>

            <label className="field"><span>Name</span>
              <input type="text" name="displayName" maxLength={50} autoComplete="name" value={displayName}
                onChange={(e) => setDisplayName(e.target.value)} />
            </label>
            <label className="field"><span>Bio</span>
              <textarea name="bio" maxLength={BIO_MAX} value={bio} onChange={(e) => setBio(e.target.value)}
                placeholder="What you love: tacos, trails, a city you know well…" />
            </label>
            <label className="field"><span>Zip code</span>
              <input type="text" name="zipcode" inputMode="numeric" pattern="[0-9]*" maxLength={5} autoComplete="postal-code"
                value={zipcode} onChange={(e) => setZipcode(e.target.value.replace(/\D/g, ''))} placeholder="28203" />
            </label>
            <p className="small muted edit-hint">
              {zipChanged && /^\d{5}$/.test(zipcode)
                ? 'Your profile will show the city and state for this zip code, never the zip code itself.'
                : saved.location
                  ? `Your profile shows “${saved.location}”. We work the city out from your zip code and never show the zip code itself.`
                  : 'We turn your zip code into a city and state for your profile, like “Charlotte, NC”. The zip code itself is never shown.'}
            </p>

            <p className="err" role="alert">{error}</p>
            <button className="btn block" type="submit" disabled={busy || uploading}>{busy ? 'Saving…' : 'Save'}</button>
            <button className="btn block plain" type="button" onClick={() => navigate(-1)}>Cancel</button>
          </form>
        ) : null}
      </main>
    </>
  );
}
