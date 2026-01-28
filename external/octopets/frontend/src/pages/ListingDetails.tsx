import React, { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import { LISTING_TYPES, ROUTES } from '../data/constants';
import { PET_TYPES } from '../data/constantsJsx';
import { DataService } from '../data/dataService';
import { Listing, ListingType } from '../types/types';
import '../styles/ListingDetails.css';

const ListingDetails: React.FC = () => {
  const { id } = useParams();
  const [listing, setListing] = useState<Listing | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [currentPhotoIndex, setCurrentPhotoIndex] = useState(0);

  useEffect(() => {
    const fetchListing = async () => {
      try {
        const foundListing = await DataService.getListing(id || '');
        setListing(foundListing);
      } catch (error) {
        console.error('Failed to fetch listing:', error);
      } finally {
        setLoading(false);
      }
    };
    
    if (id) {
      fetchListing();
    }
  }, [id]);

  if (loading) {
    return <div className="loading">Loading listing details...</div>;
  }

  if (!listing) {
    return (
      <div className="not-found">
        <h2>Listing Not Found</h2>
        <p>Sorry, we couldn't find a listing with that ID.</p>
        <Link to={ROUTES.LISTINGS} className="btn">Back to Listings</Link>
      </div>
    );
  }

  return (
    <div className="listing-details">
      <div className="listing-header">
        <img 
          src={`${process.env.PUBLIC_URL}/images/generic/cat.jpg`} 
          alt="Cat in a pet-friendly place" 
          className="listing-header-background"
        />        
        <div className="listing-header-overlay"></div>
        <div className="venue-type-tag">
          <div className="venue-type-pill">
            <span>{LISTING_TYPES.find((t: ListingType) => t.id === listing.type)?.icon}</span>
            <span>{LISTING_TYPES.find((t: ListingType) => t.id === listing.type)?.name}</span>
          </div>
        </div>
        <div className="listing-title">
          <h1>{listing.name}</h1>          
          <div className="listing-location">
            <span>📍</span> {listing.location}
          </div>
          <div className="rating-container">
            <span>★ {listing.rating.toFixed(1)} <span className="reviews-gray">({listing.reviews.length} reviews)</span></span>
          </div>
          
          <div className="hero-contact-info">
            {listing.contactInfo?.phone && (
              <div className="hero-contact-item">
                <span className="contact-icon">📞</span>
                <span>{listing.contactInfo.phone}</span>
              </div>
            )}
            {listing.contactInfo?.email && (
              <div className="hero-contact-item">
                <span className="contact-icon">📧</span>
                <span>{listing.contactInfo.email}</span>
              </div>
            )}
            {listing.contactInfo?.website && (
              <div className="hero-contact-item">
                <span className="contact-icon">🌐</span>
                <a href={listing.contactInfo.website} target="_blank" rel="noopener noreferrer">
                  Visit Website
                </a>
              </div>
            )}
          </div>
        </div>
        <div className="listing-actions">
          <Link to={ROUTES.LISTINGS} className="btn btn-outline">Back to Listings</Link>
        </div>
      </div>

      <div className="listing-content">
        <div className="listing-main">
          <div className="listing-main-content-row">
            <div className="listing-images-container">
              {listing.photos && listing.photos.length > 0 ? (
                <div className="listing-images">
                  <div className="images-carousel">
                    {listing.photos.map((photo, idx) => (
                      <div 
                        key={idx} 
                        className={`carousel-item ${idx === currentPhotoIndex ? 'active' : ''}`}
                      >
                        <img 
                          src={`/images/venues/${photo}`} 
                          alt={`${listing.name} ${idx + 1}`} 
                        />
                      </div>
                    ))}
                  </div>
                  {listing.photos.length > 1 && (
                    <div className="carousel-controls">
                      <button 
                        className="carousel-control prev" 
                        onClick={() => setCurrentPhotoIndex((currentPhotoIndex - 1 + listing.photos.length) % listing.photos.length)}
                        aria-label="Previous photo"
                      >
                        &#8592;
                      </button>
                      <div className="carousel-dots">
                        {listing.photos.map((_, idx) => (
                          <span 
                            key={idx} 
                            className={`carousel-dot ${idx === currentPhotoIndex ? 'active' : ''}`}
                            onClick={() => setCurrentPhotoIndex(idx)}
                            role="button"
                            aria-label={`Go to photo ${idx + 1}`}
                          />
                        ))}
                      </div>
                      <button 
                        className="carousel-control next" 
                        onClick={() => setCurrentPhotoIndex((currentPhotoIndex + 1) % listing.photos.length)}
                        aria-label="Next photo"
                      >
                        &#8594;
                      </button>
                    </div>
                  )}
                </div>
              ) : (
                <div className="image-placeholder">
                  <div className="placeholder-icon">
                    {LISTING_TYPES.find((t: ListingType) => t.id === listing.type)?.icon || '🏠'}
                  </div>
                  <p>Photo gallery would appear here</p>
                </div>
              )}
            </div>
            
            <div className="listing-description">
              <h2>About This Place</h2>
              <p>{listing.description}</p>
            </div>
          </div>
        </div>

        <div className="listing-sidebar">          <div className="allowed-pets-section">
            <h3>Allowed Pets</h3>
            <div className="allowed-pets-pills">                {listing.allowedPets.map((petId, index) => {
                const pet = PET_TYPES.find(p => p.id === petId);
                return pet ? (                  <div 
                    key={petId} 
                    className="pet-pill"
                  >
                    <span className="pet-icon">{pet.icon}</span>
                    <span className="pet-name">{pet.name}</span>
                  </div>
                ) : null;
              })}
            </div>
          </div><div className="amenities-sidebar-section">
            <h3>Amenities</h3>
            <div className="amenities-pills">              {listing.amenities.map((amenity, index) => (                <div 
                  key={amenity} 
                  className="amenity-pill"
                >
                  {amenity}
                </div>
              ))}
            </div>
          </div>

          <div className="review-summary-section">
            <h3>Reviews</h3>
            <div className="rating-summary">
              <div className="rating-stars">★ {listing.rating.toFixed(1)}</div>
              <div className="review-count">({listing.reviews.length} reviews)</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ListingDetails;
