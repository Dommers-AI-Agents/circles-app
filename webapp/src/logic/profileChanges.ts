// Editing my profile sends only what I changed (PUT /users/me writes every
// field it is given), and says what is wrong before the server has to.

export interface ProfileForm {
  displayName: string;
  bio: string;
  zipcode: string;
  /** A newly uploaded picture's URL; empty = keep the one I have */
  profilePicture?: string;
}

export interface ProfileBefore {
  displayName?: string | null;
  bio?: string | null;
  zipcode?: string | null;
  profilePicture?: string | null;
}

const tidy = (text: string | null | undefined) => String(text || '').replace(/\s+/g, ' ').trim();
const tidyLines = (text: string | null | undefined) => String(text || '').trim();

export const BIO_MAX = 300;

/** What to tell the person, or '' when the form can be saved. */
export function profileProblem(form: ProfileForm): string {
  const name = tidy(form.displayName);
  if (name.length < 2) return 'Your name needs at least 2 letters.';
  if (name.length > 50) return 'Your name can be up to 50 letters.';
  const zip = form.zipcode.trim();
  if (zip && !/^\d{5}$/.test(zip)) return 'A zip code is 5 digits, like 28203.';
  if (tidyLines(form.bio).length > BIO_MAX) return `Your bio can be up to ${BIO_MAX} letters.`;
  return '';
}

/** Only the fields that differ from what is saved. Empty = nothing to save. */
export function profileChanges(before: ProfileBefore, form: ProfileForm): Partial<ProfileForm> {
  const changes: Partial<ProfileForm> = {};
  const name = tidy(form.displayName);
  if (name !== tidy(before.displayName)) changes.displayName = name;
  const bio = tidyLines(form.bio);
  if (bio !== tidyLines(before.bio)) changes.bio = bio;
  const zip = form.zipcode.trim();
  if (zip !== String(before.zipcode || '').trim()) changes.zipcode = zip;
  if (form.profilePicture && form.profilePicture !== (before.profilePicture || '')) changes.profilePicture = form.profilePicture;
  return changes;
}
