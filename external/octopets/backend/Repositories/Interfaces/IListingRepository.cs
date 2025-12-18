using Octopets.Backend.Models;

namespace Octopets.Backend.Repositories.Interfaces;

public interface IListingRepository
{
    Task<IEnumerable<Listing>> GetAllAsync();
    Task<Listing?> GetByIdAsync(int id);
    Task<Listing> CreateAsync(Listing listing);
    Task<Listing?> UpdateAsync(int id, Listing listing);
    Task<bool> DeleteAsync(int id);
}
