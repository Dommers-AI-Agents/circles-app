// Category mapping for imported places (Mapstr, Google Takeout, Swarm/Foursquare)
// Maps external platform categories/tags onto the app's place category enum
// (see validatePlace in models/FirestoreModels.js for the canonical list).

// Extended Google Places types map. Deliberately separate from
// placeDiscoveryService's CATEGORY_BY_GOOGLE_TYPE: onboarding defaults to
// 'restaurant', imports must default to 'other'.
const GOOGLE_TYPE_TO_CATEGORY = {
  restaurant: 'restaurant',
  meal_takeaway: 'restaurant',
  meal_delivery: 'restaurant',
  food: 'restaurant',
  cafe: 'cafe',
  bakery: 'cafe',
  bar: 'bar',
  night_club: 'bar',
  lodging: 'hotel',
  campground: 'hotel',
  rv_park: 'hotel',
  store: 'retail',
  clothing_store: 'retail',
  shopping_mall: 'retail',
  supermarket: 'retail',
  grocery_or_supermarket: 'retail',
  department_store: 'retail',
  convenience_store: 'retail',
  book_store: 'retail',
  jewelry_store: 'retail',
  shoe_store: 'retail',
  furniture_store: 'retail',
  electronics_store: 'retail',
  florist: 'retail',
  liquor_store: 'retail',
  pet_store: 'retail',
  hair_care: 'service',
  beauty_salon: 'service',
  spa: 'service',
  laundry: 'service',
  car_repair: 'service',
  car_wash: 'service',
  plumber: 'service',
  electrician: 'service',
  locksmith: 'service',
  real_estate_agency: 'service',
  travel_agency: 'service',
  tourist_attraction: 'attraction',
  museum: 'attraction',
  art_gallery: 'attraction',
  church: 'attraction',
  hindu_temple: 'attraction',
  mosque: 'attraction',
  synagogue: 'attraction',
  city_hall: 'attraction',
  landmark: 'attraction',
  movie_theater: 'entertainment',
  amusement_park: 'entertainment',
  bowling_alley: 'entertainment',
  casino: 'entertainment',
  stadium: 'entertainment',
  aquarium: 'entertainment',
  zoo: 'entertainment',
  hospital: 'healthcare',
  doctor: 'healthcare',
  dentist: 'healthcare',
  pharmacy: 'healthcare',
  physiotherapist: 'healthcare',
  veterinary_care: 'healthcare',
  gym: 'fitness',
  school: 'education',
  university: 'education',
  primary_school: 'education',
  secondary_school: 'education',
  library: 'education',
  park: 'outdoor',
  natural_feature: 'outdoor',
  hiking_area: 'outdoor',
  beach: 'outdoor',
  train_station: 'transport',
  subway_station: 'transport',
  bus_station: 'transport',
  transit_station: 'transport',
  airport: 'transport',
  parking: 'transport',
  gas_station: 'transport',
  bank: 'finance',
  atm: 'finance',
  accounting: 'finance',
  insurance_agency: 'finance'
};

function categoryFromGoogleTypes(types = []) {
  for (const type of types) {
    if (GOOGLE_TYPE_TO_CATEGORY[type]) return GOOGLE_TYPE_TO_CATEGORY[type];
  }
  return 'other';
}

// Foursquare venue categories form a deep hierarchy; matching on category-name
// substrings (venue.categories[].name) is robust across levels.
// Order matters: first match wins, more specific entries first.
const FOURSQUARE_NAME_RULES = [
  { pattern: /coffee|café|cafe|tea room|bubble tea|bakery|breakfast|brunch|donut|dessert|ice cream|juice/i, category: 'cafe' },
  { pattern: /bar|pub|brewery|nightclub|night club|lounge|speakeasy|wine|cocktail|beer garden|distillery/i, category: 'bar' },
  { pattern: /hotel|hostel|motel|bed & breakfast|resort|lodging|vacation rental/i, category: 'hotel' },
  { pattern: /restaurant|pizza|burger|sushi|taco|bbq|steakhouse|diner|food truck|noodle|ramen|deli|sandwich/i, category: 'restaurant' },
  { pattern: /gym|fitness|yoga|climbing|martial arts|pilates|crossfit/i, category: 'fitness' },
  { pattern: /hospital|doctor|dentist|pharmacy|medical|clinic|urgent care|veterinarian/i, category: 'healthcare' },
  { pattern: /school|university|college|library|student/i, category: 'education' },
  { pattern: /park|trail|beach|mountain|lake|river|campground|garden|outdoor|scenic|ski/i, category: 'outdoor' },
  { pattern: /airport|train|metro|subway|bus station|ferry|transport|gas station|parking/i, category: 'transport' },
  { pattern: /bank|atm|credit union|financial/i, category: 'finance' },
  { pattern: /museum|gallery|monument|landmark|historic|temple|church|mosque|synagogue|attraction|plaza|castle/i, category: 'attraction' },
  { pattern: /theater|theatre|cinema|movie|music venue|concert|comedy|arcade|bowling|casino|stadium|arena|zoo|aquarium|amusement/i, category: 'entertainment' },
  { pattern: /salon|spa|barber|laundry|dry clean|repair|tailor|photographer/i, category: 'service' },
  { pattern: /shop|store|market|boutique|mall|bookstore|record/i, category: 'retail' },
  { pattern: /food|eatery|bistro|gastropub|trattoria|taverna/i, category: 'restaurant' }
];

function categoryFromFoursquareNames(categoryNames = []) {
  for (const name of categoryNames) {
    if (!name) continue;
    for (const rule of FOURSQUARE_NAME_RULES) {
      if (rule.pattern.test(name)) return rule.category;
    }
  }
  return 'other';
}

// Infer a category from free text (a place name, description, and/or address).
// Reuses the Foursquare name rules — they're broad English keyword patterns
// that work well on venue names ("Cafe Monte", "Que Onda Tacos", "Gold's Gym").
// Returns 'other' when nothing matches. First (most specific) rule wins.
function categoryFromText(...parts) {
  const text = parts.filter(Boolean).join(' ');
  if (!text.trim()) return 'other';
  for (const rule of FOURSQUARE_NAME_RULES) {
    if (rule.pattern.test(text)) return rule.category;
  }
  return 'other';
}

// Mapstr tags are free-form user text, often French or English.
const MAPSTR_TAG_RULES = [
  { pattern: /resto|restaurant|food|pizza|sushi|burger|dîner|diner|manger|brunch/i, category: 'restaurant' },
  { pattern: /café|cafe|coffee|thé|tea|boulangerie|pâtisserie|patisserie|goûter|dessert|glace/i, category: 'cafe' },
  { pattern: /bar|pub|cocktail|bière|biere|beer|vin|wine|club|soir/i, category: 'bar' },
  { pattern: /hôtel|hotel|auberge|logement|airbnb|dormir/i, category: 'hotel' },
  { pattern: /shop|boutique|magasin|store|market|marché|marche|vintage|fripe/i, category: 'retail' },
  { pattern: /musée|musee|museum|monument|galerie|gallery|culture|visite|église|eglise|château|chateau/i, category: 'attraction' },
  { pattern: /ciné|cine|cinema|théâtre|theatre|concert|spectacle|fun/i, category: 'entertainment' },
  { pattern: /sport|gym|fitness|yoga|piscine|escalade/i, category: 'fitness' },
  { pattern: /parc|park|plage|beach|rando|hike|nature|jardin|balade/i, category: 'outdoor' },
  { pattern: /santé|sante|médecin|medecin|pharmacie|docteur|health/i, category: 'healthcare' },
  { pattern: /coiffeur|salon|spa|beauté|beaute|massage|service/i, category: 'service' }
];

function categoryFromMapstrTags(tags = []) {
  for (const tag of tags) {
    if (!tag) continue;
    for (const rule of MAPSTR_TAG_RULES) {
      if (rule.pattern.test(tag)) return rule.category;
    }
  }
  return 'other';
}

module.exports = {
  categoryFromGoogleTypes,
  categoryFromFoursquareNames,
  categoryFromMapstrTags,
  categoryFromText
};
