import React, { useState, useEffect } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { ROUTES, LISTING_TYPES } from '../data/constants';
import { PET_TYPES } from '../data/constantsJsx';
import { DataService } from '../data/dataService';
import { Listing, PetType, ListingType } from '../types/types';
import ListingCard from '../components/ListingCard';
import '../styles/Listings.css';

const Listings: React.FC = () => {
  const [searchParams, setSearchParams] = useSearchParams();
  const [listings, setListings] = useState<Listing[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedPetType, setSelectedPetType] = useState<string>(searchParams.get('petType') || '');
  const [selectedListingType, setSelectedListingType] = useState<string>(searchParams.get('listingType') || '');  const [searchTerm, setSearchTerm] = useState(searchParams.get('search') || '');

  // Function to update search parameters in the URL
  const updateSearchParams = (key: string, value: string) => {
    const newSearchParams = new URLSearchParams(searchParams);
    if (value) {
      newSearchParams.set(key, value);
    } else {
      newSearchParams.delete(key);
    }
    setSearchParams(newSearchParams);
  };

  useEffect(() => {
    const fetchListings = async () => {
      try {
        const fetchedListings = await DataService.getListings();
        console.log('Fetched listings:', fetchedListings); // Debug log
        setListings(fetchedListings);
      } catch (error) {
        console.error('Failed to fetch listings:', error);
      } finally {
        setLoading(false);
      }    };

    fetchListings();
  }, [searchParams]);

  const filteredListings = listings.filter(listing => {
    const matchesPetType = !selectedPetType || listing.allowedPets.includes(selectedPetType);
    const matchesListingType = !selectedListingType || listing.type === selectedListingType;
    const matchesSearch = !searchTerm ||
      listing.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      listing.description.toLowerCase().includes(searchTerm.toLowerCase()) ||
      listing.location.toLowerCase().includes(searchTerm.toLowerCase());

    return matchesPetType && matchesListingType && matchesSearch;
  });

  if (loading) {
    return <div className="loading">Loading listings...</div>;
  }

  return (
    <div className="listings-page">
      <div className="hero-section">
        <h1>Find pet-friendly venues</h1>
        <div className="search-container">          <input
            type="text"
            placeholder="Search by name, description, or location..."
            value={searchTerm}
            onChange={(e) => {
              const value = e.target.value;
              setSearchTerm(value);
              updateSearchParams('search', value);
            }}
            className="hero-search-input"
          />
          <button 
            className="search-button"
            onClick={() => console.log('Search triggered')}
          >
            Search
          </button>
        </div>
      </div>

      <div className="filter-section">
        <div className="filter-controls">          <div className="filter-group">
            <label htmlFor="pet-type">Pet Type</label>
            <select
              id="pet-type"
              value={selectedPetType}
              onChange={(e) => {
                const value = e.target.value;
                setSelectedPetType(value);
                updateSearchParams('petType', value);
              }}
            >
              <option value="">All Pets</option>
              {PET_TYPES.map((pet: PetType) => (
                <option key={pet.id} value={pet.id}>
                  {pet.name}
                </option>
              ))}
            </select>
          </div>

          <div className="filter-group">
            <label htmlFor="listing-type">Venue Type</label>
            <select
              id="listing-type"
              value={selectedListingType}
              onChange={(e) => {
                const value = e.target.value;
                setSelectedListingType(value);
                updateSearchParams('listingType', value);
              }}
            >              <option value="">All Types</option>
              {LISTING_TYPES.map((type: ListingType) => (
                <option key={type.id} value={type.id}>
                  {type.name}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      <div className="listings-container">
        {filteredListings.length === 0 ? (
          <div className="no-results">
            <p>No listings found matching your criteria.</p>
            <button
              className="btn btn-secondary"              onClick={() => {
                setSelectedPetType('');
                setSelectedListingType('');
                setSearchTerm('');
                setSearchParams(new URLSearchParams());
              }}
            >
              Clear Filters
            </button>
          </div>
        ) : (
          <div className="listings-grid">
            {filteredListings.map(listing => (
              <ListingCard key={listing.id} listing={listing} />
            ))}          </div>
        )}
      </div>
      
      <section className="cta-section-container">
        <section className="cta-section">
          <div className="cta-image">
            <img src={`${process.env.PUBLIC_URL}/images/generic/doggo.jpg`} alt="Dog enjoying a pet-friendly place" />
          </div>
          <div className="cta-content">
            <div className="cta-text">
              <h2>Have a pet-friendly place to share?</h2>
              <p>Help other pet owners discover great places for their furry, feathery, or scaly friends.</p>
            </div>
            <div className="hero-buttons">
              <Link to={ROUTES.ADD_LISTING} className="btn btn-black">Add a listing</Link>
            </div>
          </div>
        </section>
      </section>
    </div>
  );
};

export default Listings;
