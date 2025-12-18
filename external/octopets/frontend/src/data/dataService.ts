import { appConfig } from '../config/appConfig';
import { Listing, Review } from '../types/types';
import listingsData from './listingsData';

// Debug environment setup
console.log('Environment Setup:', {
    REACT_APP_USE_MOCK_DATA: process.env.REACT_APP_USE_MOCK_DATA,
    REACT_APP_USE_MOCK_DATA_PARSED: process.env.REACT_APP_USE_MOCK_DATA?.toLowerCase() === 'true',
    appConfigMockData: appConfig.useMockData,
    apiUrl: appConfig.apiUrl
});

// Mock data
const mockListings: Listing[] = listingsData;

// API service
export class DataService {
    static async getListings(): Promise<Listing[]> {
        console.log('DataService: Fetching listings, using mock data:', appConfig.useMockData);
        
        if (appConfig.useMockData) {
            console.log('DataService: Returning mock listings:', mockListings.length, 'items');
            return mockListings;
        }
        
        try {
            const response = await fetch(`${appConfig.apiUrl}/listings`);
            if (!response.ok) {
                console.error('DataService: Failed to fetch listings, status:', response.status);
                throw new Error('Failed to fetch listings');
            }
            const data = await response.json();
            console.log('DataService: Fetched listings from API:', data.length, 'items');
            return data;
        } catch (error) {
            console.error('DataService: Error fetching listings:', error);
            throw error;
        }
    }

    static async getListing(id: string): Promise<Listing> {
        console.log('DataService: Fetching listing', id, 'using mock data:', appConfig.useMockData);
        
        if (appConfig.useMockData) {
            const listing = mockListings.find(l => l.id === id);
            if (!listing) {
                console.error('DataService: Mock listing not found:', id);
                throw new Error('Listing not found');
            }
            console.log('DataService: Returning mock listing:', listing.name);
            return listing;
        }

        try {
            const response = await fetch(`${appConfig.apiUrl}/listings/${id}`);
            if (!response.ok) {
                console.error('DataService: Failed to fetch listing, status:', response.status);
                throw new Error('Failed to fetch listing');
            }
            const data = await response.json();
            console.log('DataService: Fetched listing from API:', data.name);
            return data;
        } catch (error) {
            console.error('DataService: Error fetching listing:', error);
            throw error;
        }
    }

    static async getReviews(listingId: string): Promise<Review[]> {
        console.log('DataService: Fetching reviews for listing', listingId, 'using mock data:', appConfig.useMockData);
        
        if (appConfig.useMockData) {
            const listing = mockListings.find(l => l.id === listingId);
            const reviews = listing?.reviews || [];
            console.log('DataService: Returning mock reviews:', reviews.length, 'items');
            return reviews;
        }

        try {
            const response = await fetch(`${appConfig.apiUrl}/listings/${listingId}/reviews`);
            if (!response.ok) {
                console.error('DataService: Failed to fetch reviews, status:', response.status);
                throw new Error('Failed to fetch reviews');
            }
            const data = await response.json();
            console.log('DataService: Fetched reviews from API:', data.length, 'items');
            return data;
        } catch (error) {
            console.error('DataService: Error fetching reviews:', error);
            throw error;
        }
    }

    static async createListing(listing: Omit<Listing, 'id' | 'reviews' | 'rating'>): Promise<Listing> {
        console.log('DataService: Creating listing using mock data:', appConfig.useMockData);
        
        if (appConfig.useMockData) {
            const newListing: Listing = {
                ...listing,
                id: Math.random().toString(36).substr(2, 9),
                reviews: [],
                rating: 0
            };
            mockListings.push(newListing);
            console.log('DataService: Created mock listing:', newListing.name);
            return newListing;
        }

        try {
            const response = await fetch(`${appConfig.apiUrl}/listings`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(listing)
            });

            if (!response.ok) {
                console.error('DataService: Failed to create listing, status:', response.status);
                throw new Error('Failed to create listing');
            }
            const data = await response.json();
            console.log('DataService: Created listing via API:', data.name);
            return data;
        } catch (error) {
            console.error('DataService: Error creating listing:', error);
            throw error;
        }
    }

    static async createReview(listingId: string, review: Omit<Review, 'id' | 'date'>): Promise<Review> {
        console.log('DataService: Creating review for listing', listingId, 'using mock data:', appConfig.useMockData);
        
        if (appConfig.useMockData) {
            const listing = mockListings.find(l => l.id === listingId);
            if (!listing) {
                console.error('DataService: Mock listing not found for review:', listingId);
                throw new Error('Listing not found');
            }

            const newReview: Review = {
                ...review,
                id: Math.random().toString(36).substr(2, 9),
                date: new Date().toISOString().split('T')[0]
            };
            
            listing.reviews.push(newReview);
            
            // Update listing rating
            listing.rating = listing.reviews.reduce((sum: number, r: Review) => sum + r.rating, 0) / listing.reviews.length;
            
            console.log('DataService: Created mock review for listing:', listing.name);
            return newReview;
        }

        try {
            const response = await fetch(`${appConfig.apiUrl}/reviews/by-listing/${listingId}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(review)
            });

            if (!response.ok) {
                console.error('DataService: Failed to create review, status:', response.status);
                throw new Error('Failed to create review');
            }
            const data = await response.json();
            console.log('DataService: Created review via API');
            return data;
        } catch (error) {
            console.error('DataService: Error fetching reviews:', error);
            throw error;
        }
    }
}
