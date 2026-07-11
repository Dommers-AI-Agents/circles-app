// backend/data/popularPlaces.js
// Curated list of popular places for user onboarding

const POPULAR_PLACES = {
  // Major US Cities
  'new york': [
    {
      name: "Joe's Pizza",
      category: "restaurant",
      description: "Classic NYC pizza joint",
      address: "Multiple locations in New York, NY",
      coordinates: [-73.9857, 40.7484], // Times Square area
      website: "https://joespizzanyc.com"
    },
    {
      name: "Katz's Delicatessen", 
      category: "restaurant",
      description: "Iconic NYC deli famous for pastrami",
      address: "205 E Houston St, New York, NY 10002",
      coordinates: [-73.9872, 40.7224],
      website: "https://katzsdelicatessen.com"
    },
    {
      name: "The High Line",
      category: "attraction",
      description: "Elevated park on former railway",
      address: "New York, NY",
      coordinates: [-74.0048, 40.7480]
    }
  ],
  
  'los angeles': [
    {
      name: "In-N-Out Burger",
      category: "restaurant", 
      description: "California's beloved burger chain",
      address: "Multiple locations in Los Angeles, CA",
      coordinates: [-118.2437, 34.0522],
      website: "https://in-n-out.com"
    },
    {
      name: "Griffith Observatory",
      category: "attraction",
      description: "Iconic observatory with city views",
      address: "2800 E Observatory Rd, Los Angeles, CA 90027",
      coordinates: [-118.3004, 34.1184],
      website: "https://griffithobservatory.org"
    },
    {
      name: "Grand Central Market",
      category: "restaurant",
      description: "Historic food hall downtown",
      address: "317 S Broadway, Los Angeles, CA 90013", 
      coordinates: [-118.2512, 34.0507],
      website: "https://grandcentralmarket.com"
    }
  ],

  'chicago': [
    {
      name: "Lou Malnati's Pizzeria",
      category: "restaurant",
      description: "Famous Chicago deep dish pizza",
      address: "Multiple locations in Chicago, IL",
      coordinates: [-87.6298, 41.8781],
      website: "https://loumalnatis.com"
    },
    {
      name: "The Bean (Cloud Gate)",
      category: "attraction", 
      description: "Iconic reflective sculpture",
      address: "201 E Randolph St, Chicago, IL 60602",
      coordinates: [-87.6233, 41.8827]
    },
    {
      name: "Portillo's",
      category: "restaurant",
      description: "Chicago-style hot dogs and Italian beef",
      address: "Multiple locations in Chicago, IL",
      coordinates: [-87.6298, 41.8781],
      website: "https://portillos.com"
    }
  ],

  'san francisco': [
    {
      name: "Tartine Bakery",
      category: "cafe",
      description: "Artisanal bakery and cafe",
      address: "600 Guerrero St, San Francisco, CA 94110",
      coordinates: [-122.4241, 37.7606],
      website: "https://tartinebakery.com"
    },
    {
      name: "Golden Gate Bridge",
      category: "attraction",
      description: "Iconic suspension bridge",
      address: "Golden Gate Bridge, San Francisco, CA",
      coordinates: [-122.4783, 37.8199]
    },
    {
      name: "Swan Oyster Depot",
      category: "restaurant",
      description: "Historic seafood counter",
      address: "1517 Polk St, San Francisco, CA 94109",
      coordinates: [-122.4194, 37.7926]
    }
  ],

  // Belmar, NJ defaults used when we don't have city-specific places
  'belmar': [
    {
      name: "Starbucks",
      category: "cafe",
      description: "Popular coffee chain",
      address: "1799 River Rd, Belmar, NJ 07719",
      coordinates: [-74.0407, 40.1771],
      website: "https://starbucks.com"
    },
    {
      name: "Playa Bowls",
      category: "cafe",
      description: "Acai bowls and smoothies - the original location",
      address: "806 Main St, Belmar, NJ 07719",
      coordinates: [-74.0256, 40.1802],
      website: "https://playabowls.com"
    },
    {
      name: "Federico's Pizza & Restaurant",
      category: "restaurant",
      description: "Family-owned Jersey Shore pizza spot",
      address: "700 Main St, Belmar, NJ 07719",
      coordinates: [-74.0254, 40.1817],
      website: "https://federicospizza.com"
    },
    {
      name: "D'Jais Oceanview Bar & Cafe",
      category: "restaurant",
      description: "Iconic Belmar beach bar and restaurant",
      address: "1801 Ocean Ave, Belmar, NJ 07719",
      coordinates: [-74.0165, 40.1703],
      website: "https://djais.com"
    },
    {
      name: "Belmar Boardwalk",
      category: "attraction",
      description: "Classic Jersey Shore boardwalk and beach",
      address: "Ocean Ave, Belmar, NJ 07719",
      coordinates: [-74.0137, 40.1765]
    }
  ]
};

// Default circles to create for new users
const DEFAULT_CIRCLES = [
  {
    name: "Want to Try",
    description: "Places you're excited to visit soon",
    privacy: "private",
    category: "other"
  },
  {
    name: "Favorite Local Spots", 
    description: "Your go-to places in your area",
    privacy: "myNetwork",
    category: "food"
  },
  {
    name: "Vacation",
    description: "Amazing places from your travels",
    privacy: "public",
    category: "travel"
  }
];

// Function to get places for a specific city/region
const getPlacesForCity = (cityName) => {
  const normalizedCity = cityName.toLowerCase();
  return POPULAR_PLACES[normalizedCity] || [];
};

// Function to get Belmar, NJ default places as fallback
const getNationalChains = () => {
  return POPULAR_PLACES.belmar;
};

// Function to get a random local place for onboarding
const getRandomLocalPlace = (userLocation = null) => {
  let places = [];
  
  // If user has location, try to find city-specific places
  if (userLocation && userLocation.city) {
    places = getPlacesForCity(userLocation.city);
  }
  
  // Fallback to national chains if no local places found
  if (places.length === 0) {
    places = getNationalChains();
  }
  
  // Return random place or fallback
  if (places.length > 0) {
    const randomIndex = Math.floor(Math.random() * places.length);
    return places[randomIndex];
  }
  
  // Ultimate fallback - Starbucks in Belmar, NJ
  return {
    name: "Starbucks",
    category: "cafe",
    description: "Popular coffee chain",
    address: "1799 River Rd, Belmar, NJ 07719",
    coordinates: [-74.0407, 40.1771],
    website: "https://starbucks.com"
  };
};

module.exports = {
  POPULAR_PLACES,
  DEFAULT_CIRCLES,
  getPlacesForCity,
  getNationalChains,
  getRandomLocalPlace
};