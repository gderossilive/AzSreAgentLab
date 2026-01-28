using Microsoft.EntityFrameworkCore;
using Octopets.Backend.Data;
using Octopets.Backend.Models;
using Octopets.Backend.Repositories.Interfaces;

namespace Octopets.Backend.Repositories;

public class ReviewRepository : IReviewRepository
{
    private readonly AppDbContext _context;

    public ReviewRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<IEnumerable<Review>> GetAllAsync()
    {
        return await _context.Reviews.ToListAsync();
    }

    public async Task<IEnumerable<Review>> GetByListingIdAsync(int listingId)
    {
        return await _context.Reviews
            .Where(r => r.ListingId == listingId)
            .ToListAsync();
    }

    public async Task<Review?> GetByIdAsync(int id)
    {
        return await _context.Reviews.FindAsync(id);
    }

    public async Task<Review> CreateAsync(Review review)
    {
        review.CreatedAt = DateTime.UtcNow;
        _context.Reviews.Add(review);
        await _context.SaveChangesAsync();
        return review;
    }

    public async Task<Review?> UpdateAsync(int id, Review review)
    {
        var existingReview = await _context.Reviews.FindAsync(id);
        if (existingReview == null)
            return null;

        existingReview.Reviewer = review.Reviewer;
        existingReview.Rating = review.Rating;
        existingReview.Comment = review.Comment;

        await _context.SaveChangesAsync();
        return existingReview;
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var review = await _context.Reviews.FindAsync(id);
        if (review == null)
            return false;

        _context.Reviews.Remove(review);
        await _context.SaveChangesAsync();
        return true;
    }
}
