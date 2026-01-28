// Mock data for pet-friendly listings
import { Listing } from '../types/types';

const listingsData: Listing[] = [
  {
    id: "1",
    name: "Pawsome Park",
    type: "park",
    location: "123 Park Avenue, New York, NY",
    description: "A spacious park with dedicated areas for dogs to run off-leash. Beautiful walking paths and rest areas for owners.",
    allowedPets: ["dogs", "cats"],
    amenities: ["Water fountains", "Waste stations", "Benches", "Shade areas"],
    photos: ["park1.jpg", "park2.jpg"],
    rating: 4.7,
    reviews: [
      {
        id: "101",
        userId: "user1",
        userName: "Alex Johnson",
        rating: 5,
        comment: "My golden retriever loves this park! Plenty of space to run around.",
        date: "2025-04-15"
      },
      {
        id: "102",
        userId: "user2",
        userName: "Taylor Smith",
        rating: 4,
        comment: "Clean and well-maintained. Would be perfect with more shade in summer.",
        date: "2025-04-10"
      }
    ],
    contactInfo: {
      phone: "555-123-4567",
      email: "info@pawsomepark.com",
      website: "https://pawsomepark.com"
    }
  },
  {
    id: "2",
    name: "Whiskers Cafe",
    type: "cafe",
    location: "456 Main Street, Seattle, WA",
    description: "A cozy cafe with a special menu for pets. Indoor and outdoor seating available with pet-friendly accommodations.",
    allowedPets: ["dogs", "cats", "small_mammals"],
    amenities: ["Pet menu", "Water bowls", "Pet beds", "Outdoor patio"],
    photos: ["cafe1.jpg", "cafe2.jpg"],
    rating: 4.5,
    reviews: [
      {
        id: "201",
        userId: "user3",
        userName: "Jamie Lee",
        rating: 5,
        comment: "They have treats for my dog and great coffee for me!",
        date: "2025-04-18"
      },
      {
        id: "202",
        userId: "user4",
        userName: "Casey Morgan",
        rating: 4,
        comment: "My cat enjoyed lounging on their special pet beds. Very accommodating staff.",
        date: "2025-04-05"
      }
    ],
    contactInfo: {
      phone: "555-987-6543",
      email: "hello@whiskerscafe.com",
      website: "https://whiskerscafe.com"
    }
  },
  {
    id: "3",
    name: "Pet Haven Home",
    type: "home",
    location: "789 Oak Road, San Francisco, CA",
    description: "A beautiful vacation home with a fenced yard, pet doors, and all necessities for your furry friends.",
    allowedPets: ["dogs", "cats", "birds", "small_mammals"],
    amenities: ["Fenced yard", "Pet doors", "Pet beds", "Feeding stations", "Pet toys"],
    photos: ["home1.jpg", "home2.jpg"],
    rating: 4.9,
    reviews: [
      {
        id: "301",
        userId: "user5",
        userName: "Jordan Riley",
        rating: 5,
        comment: "Best pet-friendly accommodation we've found! Our dogs loved the yard.",
        date: "2025-03-28"
      },
      {
        id: "302",
        userId: "user6",
        userName: "Riley Chen",
        rating: 5,
        comment: "Even our parakeet was comfortable here. Thoughtful touches for all types of pets.",
        date: "2025-03-15"
      }
    ],
    contactInfo: {
      phone: "555-234-5678",
      email: "stay@pethavenhome.com",
      website: "https://pethavenhome.com"
    }
  },
  {
    id: "4",
    name: "Pets & Pillows Hotel",
    type: "hotel",
    location: "101 Sunset Blvd, Los Angeles, CA",
    description: "Luxury hotel that welcomes pets of all sizes. Special pet services available including walking and grooming.",
    allowedPets: ["dogs", "cats", "birds"],
    amenities: ["Pet spa", "Walking service", "Pet menu", "Pet sitting", "Pet beds"],
    photos: ["hotel1.jpg", "hotel2.jpg"],
    rating: 4.8,
    reviews: [
      {
        id: "401",
        userId: "user7",
        userName: "Sam Wilson",
        rating: 5,
        comment: "They treated my dog like royalty! Room service even for pets.",
        date: "2025-04-02"
      },
      {
        id: "402",
        userId: "user8",
        userName: "Jesse Taylor",
        rating: 4.5,
        comment: "Great amenities for pets, though a bit pricey.",
        date: "2025-03-20"
      }
    ],
    contactInfo: {
      phone: "555-876-5432",
      email: "reservations@petsandpillows.com",
      website: "https://petsandpillows.com"
    }
  },
  {
    id: "5",
    name: "Furry Friends Store",
    type: "custom",
    location: "246 Cherry Lane, Chicago, IL",
    description: "A pet store with a play area where pets are welcome to try toys and meet other animals.",
    allowedPets: ["dogs", "cats", "small_mammals", "birds", "other"],
    amenities: ["Play area", "Treats bar", "Water stations", "Pet events"],
    photos: ["store1.jpg", "store2.jpg"],
    rating: 4.6,
    reviews: [
      {
        id: "501",
        userId: "user9",
        userName: "Taylor Kim",
        rating: 5,
        comment: "My ferret loved the play area! Staff was very knowledgeable about exotic pets.",
        date: "2025-04-12"
      },
      {
        id: "502",
        userId: "user10",
        userName: "Alex Rivera",
        rating: 4,
        comment: "Great selection of products for all types of pets.",
        date: "2025-04-08"
      }
    ],    contactInfo: {
      phone: "555-345-6789",
      email: "shop@furryfriendsstore.com",
      website: "https://furryfriendsstore.com"
    }
  },
  {
    id: "6",
    name: "Mooch's Meow",
    type: "cafe",
    location: "789 Banana Street, Miami, FL",
    description: "A unique monkey-themed cafe where you can enjoy your coffee surrounded by banana decor and monkey-themed treats. Perfect for primate enthusiasts and their pets!",
    allowedPets: ["dogs", "cats", "small_mammals", "other"],
    amenities: ["Banana treats", "Monkey-themed play area", "Climbing structures", "Tropical atmosphere", "Pet-friendly seating"],
    photos: ["moochs1.jpg", "moochs2.jpg"],
    rating: 5.0,
    reviews: [
      {
        id: "601",
        userId: "user11",
        userName: "Charlie Simmons",
        rating: 5,
        comment: "Such a fun atmosphere! My dog loved the banana-shaped treats and the staff was amazing.",
        date: "2025-04-28"
      },
      {
        id: "602",
        userId: "user12",
        userName: "Morgan Patel",
        rating: 5,
        comment: "The monkey theme is adorable! Great place to bring your pets, they have special accommodations for all types of animals.",
        date: "2025-04-22"
      },
      {
        id: "603",
        userId: "user13",
        userName: "Sam Washington",
        rating: 5,
        comment: "Best cafe experience ever! My cat actually enjoyed the climbing structures, and I loved the monkey-themed lattes!",
        date: "2025-05-01"
      }
    ],
    contactInfo: {
      phone: "555-111-2222",
      email: "hello@moochsmeow.com",
      website: "https://moochsmeow.com"
    }
  }
];

export default listingsData;
