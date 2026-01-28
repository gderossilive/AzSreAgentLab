namespace Octopets.Backend.Models;

public class Listing
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public string? Address { get; set; }
    public string Location { get; set; } = string.Empty;
    public string? Type { get; set; }
    public List<string> AllowedPets { get; set; } = new();
    public List<string> Amenities { get; set; } = new();
    public double Rating { get; set; } = 0.0;
    public List<string> Photos { get; set; } = new();
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }
    
    // Navigation properties
    public ICollection<Review> Reviews { get; set; } = new List<Review>();
}
