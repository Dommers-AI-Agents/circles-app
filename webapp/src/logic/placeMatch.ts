// What counts as a match when I search my own saved places. Done here, in the
// browser, over the list the server already sent (GET /places/my-places).
//
// The rule: every word I typed must start a word somewhere in the place's
// name, address, kind of place, circle name, tags or my own notes. Case and
// accents don't matter ("cafe" finds "Café"), and neither do apostrophes
// ("sals" finds "Sal's"). Places whose NAME matches come first, in the order
// the server sent them; nothing is ever re-sorted alphabetically.
import { categoryOf } from './labels';

export interface SearchablePlace {
  name: string;
  address?: string | null;
  category?: string;
  circleName?: string;
  tags?: string[];
  privateNotes?: string | null;
  publicNotes?: string | null;
  notes?: string | null;
}

/** Lower-case, accents and apostrophes dropped, everything else that isn't a letter or digit becomes a space. */
export const fold = (text: string | null | undefined): string =>
  String(text || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/['’`]/g, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();

export const wordsOf = (text: string | null | undefined): string[] => {
  const folded = fold(text);
  return folded ? folded.split(' ') : [];
};

const startsAWord = (words: string[], term: string) => words.some((word) => word.startsWith(term));

/** Shortest search worth running: one letter matches nearly everything. */
export const MIN_QUERY = 2;

export const isSearchable = (query: string): boolean => fold(query).replace(/ /g, '').length >= MIN_QUERY;

/** 0 = no match, 2 = every word is in the name, 1 = matched with help from the other fields. */
export function matchRank(place: SearchablePlace, query: string): 0 | 1 | 2 {
  const terms = wordsOf(query);
  if (terms.length === 0) return 0;
  const nameWords = wordsOf(place.name);
  if (terms.every((term) => startsAWord(nameWords, term))) return 2;
  const allWords = [
    ...nameWords,
    ...wordsOf(place.address),
    ...wordsOf(place.category),
    ...wordsOf(place.category ? categoryOf(place.category).name : ''),
    ...wordsOf(place.circleName),
    ...(place.tags || []).flatMap((tag) => wordsOf(tag)),
    ...wordsOf(place.privateNotes),
    ...wordsOf(place.publicNotes),
    ...wordsOf(place.notes)
  ];
  return terms.every((term) => startsAWord(allWords, term)) ? 1 : 0;
}

/** My places that match, name matches first, each group in the order given. */
export function filterMyPlaces<P extends SearchablePlace>(places: P[], query: string, limit = 30): P[] {
  if (!isSearchable(query)) return [];
  const byName: P[] = [];
  const byRest: P[] = [];
  places.forEach((place) => {
    const rank = matchRank(place, query);
    if (rank === 2) byName.push(place);
    else if (rank === 1) byRest.push(place);
  });
  return [...byName, ...byRest].slice(0, limit);
}
