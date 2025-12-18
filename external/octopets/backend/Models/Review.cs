namespace Octopets.Backend.Models;

public class Review
{
    public int Id { get; set; }
    public int ListingId { get; set; }
    public string Reviewer { get; set; } = string.Empty;
    public int Rating { get; set; }
    public string Comment { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    // Navigation property
    public Listing? Listing { get; set; }
}
