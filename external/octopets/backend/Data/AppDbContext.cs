using Microsoft.EntityFrameworkCore;
using Octopets.Backend.Models;
using System.Text.Json;

namespace Octopets.Backend.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<Listing> Listings => Set<Listing>();
    public DbSet<Review> Reviews => Set<Review>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Configure relationships
        modelBuilder.Entity<Review>()
            .HasOne(r => r.Listing)
            .WithMany(l => l.Reviews)
            .HasForeignKey(r => r.ListingId);

        // Configure JSON serialization for List properties
        modelBuilder.Entity<Listing>()
            .Property(l => l.AllowedPets)
            .HasConversion(
                v => JsonSerializer.Serialize(v, (JsonSerializerOptions)null!),
                v => JsonSerializer.Deserialize<List<string>>(v, (JsonSerializerOptions)null!)!);

        modelBuilder.Entity<Listing>()
            .Property(l => l.Amenities)
            .HasConversion(
                v => JsonSerializer.Serialize(v, (JsonSerializerOptions)null!),
                v => JsonSerializer.Deserialize<List<string>>(v, (JsonSerializerOptions)null!)!);

        // Seed data
        SeedData(modelBuilder);
    }

    private void SeedData(ModelBuilder modelBuilder)
    {
        // Seed reviews
        modelBuilder.Entity<Review>().HasData(
            // Pawsome Park reviews
            new Review
            {
                Id = 101,
                ListingId = 1,
                Reviewer = "Alex Johnson",
                Rating = 5,
                Comment = "My golden retriever loves this park! Plenty of space to run around.",
                CreatedAt = new DateTime(2025, 4, 15)
            },
            new Review
            {
                Id = 102,
                ListingId = 1,
                Reviewer = "Taylor Smith",
                Rating = 4,
                Comment = "Clean and well-maintained. Would be perfect with more shade in summer.",
                CreatedAt = new DateTime(2025, 4, 10)
            },
            // Whiskers Cafe reviews
            new Review
            {
                Id = 201,
                ListingId = 2,
                Reviewer = "Jamie Lee",
                Rating = 5,
                Comment = "They have treats for my dog and great coffee for me!",
                CreatedAt = new DateTime(2025, 4, 18)
            },
            new Review
            {
                Id = 202,
                ListingId = 2,
                Reviewer = "Casey Morgan",
                Rating = 4,
                Comment = "My cat enjoyed lounging on their special pet beds. Very accommodating staff.",
                CreatedAt = new DateTime(2025, 4, 5)
            },
            // Pet Haven Home reviews
            new Review
            {
                Id = 301,
                ListingId = 3,
                Reviewer = "Jordan Riley",
                Rating = 5,
                Comment = "Best pet-friendly accommodation we've found! Our dogs loved the yard.",
                CreatedAt = new DateTime(2025, 3, 28)
            },
            new Review
            {
                Id = 302,
                ListingId = 3,
                Reviewer = "Riley Chen",
                Rating = 5,
                Comment = "Even our parakeet was comfortable here. Thoughtful touches for all types of pets.",
                CreatedAt = new DateTime(2025, 3, 15)
            },
            // Pets & Pillows Hotel reviews
            new Review
            {
                Id = 401,
                ListingId = 4,
                Reviewer = "Sam Wilson",
                Rating = 5,
                Comment = "They treated my dog like royalty! Room service even for pets.",
                CreatedAt = new DateTime(2025, 4, 2)
            },
            new Review
            {
                Id = 402,
                ListingId = 4,
                Reviewer = "Jesse Taylor",
                Rating = 4,
                Comment = "Great amenities for pets, though a bit pricey.",
                CreatedAt = new DateTime(2025, 3, 20)
            },
            // Furry Friends Store reviews
            new Review
            {
                Id = 501,
                ListingId = 5,
                Reviewer = "Taylor Kim",
                Rating = 5,
                Comment = "My ferret loved the play area! Staff was very knowledgeable about exotic pets.",
                CreatedAt = new DateTime(2025, 4, 12)
            },
            new Review
            {
                Id = 502,
                ListingId = 5,
                Reviewer = "Alex Rivera",
                Rating = 4,
                Comment = "Great selection of products for all types of pets.",
                CreatedAt = new DateTime(2025, 4, 8)
            },
            // Mooch's Meow reviews
            new Review
            {
                Id = 601,
                ListingId = 6,
                Reviewer = "Charlie Simmons",
                Rating = 5,
                Comment = "Such a fun atmosphere! My dog loved the banana-shaped treats and the staff was amazing.",
                CreatedAt = new DateTime(2025, 4, 28)
            },
            new Review
            {
                Id = 602,
                ListingId = 6,
                Reviewer = "Morgan Patel",
                Rating = 5,
                Comment = "The monkey theme is adorable! Great place to bring your pets, they have special accommodations for all types of animals.",
                CreatedAt = new DateTime(2025, 4, 22)
            },
            new Review
            {
                Id = 603,
                ListingId = 6,
                Reviewer = "Sam Washington",
                Rating = 5,
                Comment = "Best cafe experience ever! My cat actually enjoyed the climbing structures, and I loved the monkey-themed lattes!",
                CreatedAt = new DateTime(2025, 5, 1)
            }
        );
        // Seed listings
        modelBuilder.Entity<Listing>().HasData(
            new Listing
            {
                Id = 1,
                Name = "Pawsome Park",
                Location = "123 Park Avenue, New York, NY",
                Address = "123 Park Avenue, New York, NY",
                Description = "A spacious park with dedicated areas for dogs to run off-leash. Beautiful walking paths and rest areas for owners.",
                Price = 0m,
                Type = "park",
                AllowedPets = new List<string> { "dogs", "cats" },
                Amenities = new List<string> { "Water fountains", "Waste stations", "Benches", "Shade areas" },
                Photos = new List<string> { "park1.jpg", "park2.jpg" },
                Rating = 4.7,
                CreatedAt = new DateTime(2025, 4, 15)
            },
            new Listing
            {
                Id = 2,
                Name = "Whiskers Cafe",
                Location = "456 Main Street, Seattle, WA",
                Address = "456 Main Street, Seattle, WA",
                Description = "A cozy cafe with a special menu for pets. Indoor and outdoor seating available with pet-friendly accommodations.",
                Price = 0m,
                Type = "cafe",
                AllowedPets = new List<string> { "dogs", "cats", "small_mammals" },
                Amenities = new List<string> { "Pet menu", "Water bowls", "Pet beds", "Outdoor patio" },
                Photos = new List<string> { "cafe1.jpg", "cafe2.jpg" },
                Rating = 4.5,
                CreatedAt = new DateTime(2025, 4, 18)
            },
            new Listing
            {
                Id = 3,
                Name = "Pet Haven Home",
                Location = "789 Oak Road, San Francisco, CA",
                Address = "789 Oak Road, San Francisco, CA",
                Description = "A beautiful vacation home with a fenced yard, pet doors, and all necessities for your furry friends.",
                Price = 0m,
                Type = "home",
                AllowedPets = new List<string> { "dogs", "cats", "birds", "small_mammals" },
                Amenities = new List<string> { "Fenced yard", "Pet doors", "Pet beds", "Feeding stations", "Pet toys" },
                Photos = new List<string> { "home1.jpg", "home2.jpg" },
                Rating = 4.9,
                CreatedAt = new DateTime(2025, 3, 28)
            },
            new Listing
            {
                Id = 4,
                Name = "Pets & Pillows Hotel",
                Location = "101 Sunset Blvd, Los Angeles, CA",
                Address = "101 Sunset Blvd, Los Angeles, CA",
                Description = "Luxury hotel that welcomes pets of all sizes. Special pet services available including walking and grooming.",
                Price = 0m,
                Type = "hotel",
                AllowedPets = new List<string> { "dogs", "cats", "birds" },
                Amenities = new List<string> { "Pet spa", "Walking service", "Pet menu", "Pet sitting", "Pet beds" },
                Photos = new List<string> { "hotel1.jpg", "hotel2.jpg" },
                Rating = 4.8,
                CreatedAt = new DateTime(2025, 4, 2)
            },
            new Listing
            {
                Id = 5,
                Name = "Furry Friends Store",
                Location = "246 Cherry Lane, Chicago, IL",
                Address = "246 Cherry Lane, Chicago, IL",
                Description = "A pet store with a play area where pets are welcome to try toys and meet other animals.",
                Price = 0m,
                Type = "custom",
                AllowedPets = new List<string> { "dogs", "cats", "small_mammals", "birds", "other" },
                Amenities = new List<string> { "Play area", "Treats bar", "Water stations", "Pet events" },
                Photos = new List<string> { "store1.jpg", "store2.jpg" },
                Rating = 4.6,
                CreatedAt = new DateTime(2025, 4, 12)
            },
            new Listing
            {
                Id = 6,
                Name = "Mooch's Meow",
                Location = "789 Banana Street, Miami, FL",
                Address = "789 Banana Street, Miami, FL",
                Description = "A unique monkey-themed cafe where you can enjoy your coffee surrounded by banana decor and monkey-themed treats. Perfect for primate enthusiasts and their pets!",
                Price = 0m,
                Type = "cafe",
                AllowedPets = new List<string> { "dogs", "cats", "small_mammals", "other" },
                Amenities = new List<string> { "Banana treats", "Monkey-themed play area", "Climbing structures", "Tropical atmosphere", "Pet-friendly seating" },
                Photos = new List<string> { "moochs1.jpg", "moochs2.jpg" },
                Rating = 5.0,
                CreatedAt = new DateTime(2025, 4, 28)
            },
            new Listing
            {
                Id = 7,
                Name = "Maui Paws",
                Location = "123 Hibiscus Street, Lahaina, HI",
                Address = "123 Hibiscus Street, Lahaina, HI",
                Description = "A local venue for local pet owners",
                Price = 0m,
                Type = "cafe",
                AllowedPets = new List<string> { "dogs", "cats", "small_mammals", "other" },
                Amenities = new List<string> { "Hawaiian treats", "Outdoors", "Climbing structures", "Tropical atmosphere", "Pet-friendly seating" },
                Photos = new List<string> { "moochs1.jpg", "moochs2.jpg" },
                Rating = 5.0,
                CreatedAt = new DateTime(2025, 5, 2)
            }
        );
    }
}
