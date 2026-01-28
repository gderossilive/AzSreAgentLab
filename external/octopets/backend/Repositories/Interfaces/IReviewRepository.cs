using Octopets.Backend.Models;

namespace Octopets.Backend.Repositories.Interfaces;

public interface IReviewRepository
{
    Task<IEnumerable<Review>> GetAllAsync();
    Task<IEnumerable<Review>> GetByListingIdAsync(int listingId);
    Task<Review?> GetByIdAsync(int id);
    Task<Review> CreateAsync(Review review);
    Task<Review?> UpdateAsync(int id, Review review);
    Task<bool> DeleteAsync(int id);
}
