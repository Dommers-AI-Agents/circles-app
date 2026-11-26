// Share a link: the phone's own share sheet where there is one, else copy it.
import { toast } from './kit';

export const SHARE_BASE = 'https://api.favcircles.com';

export async function shareLink(title: string, url: string): Promise<void> {
  try {
    if (navigator.share) { await navigator.share({ title, url }); return; }
    await navigator.clipboard.writeText(url);
    toast('Link copied');
  } catch (error) {
    if ((error as Error).name !== 'AbortError') toast("Couldn't share that. Try again.");
  }
}
