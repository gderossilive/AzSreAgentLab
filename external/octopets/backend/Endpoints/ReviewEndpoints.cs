using Octopets.Backend.Models;
using Octopets.Backend.Repositories.Interfaces;
using Microsoft.Extensions.Configuration;

namespace Octopets.Backend.Endpoints;

public static class ReviewEndpoints
{
    public static void MapReviewEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/reviews")
                       .WithTags("Reviews");

        // GET all reviews
        group.MapGet("/", async (IReviewRepository repository) =>
        {
            var reviews = await repository.GetAllAsync();
            return Results.Ok(reviews);
        })
        .WithName("GetAllReviews")
        .WithDescription("Gets all reviews")
        .WithOpenApi();

        // GET reviews by listing id
        group.MapGet("/by-listing/{listingId:int}", async (int listingId, IReviewRepository repository) =>
        {
            var reviews = await repository.GetByListingIdAsync(listingId);
            return Results.Ok(reviews);
        })
        .WithName("GetReviewsByListingId")
        .WithDescription("Gets all reviews for a specific listing")
        .WithOpenApi(operation => {
            operation.Parameters[0].Description = "The ID of the listing to get reviews for";
            return operation;
        });

        // GET review by id
        group.MapGet("/{id:int}", async (int id, IReviewRepository repository) =>
        {
            var review = await repository.GetByIdAsync(id);
            return review is null ? Results.NotFound() : Results.Ok(review);
        })
        .WithName("GetReviewById")
        .WithDescription("Gets a review by its ID")
        .WithOpenApi();        // POST new review
        group.MapPost("/", async (Review review, IReviewRepository repository, IConfiguration config) =>
        {
            if (!config.GetValue<bool>("ENABLE_CRUD", true))
            {
                throw new InvalidOperationException("CRUD operations are currently disabled");
            }
            var newReview = await repository.CreateAsync(review);
            return Results.Created($"/api/reviews/{newReview.Id}", newReview);
        })
        .WithName("CreateReview")
        .WithDescription("Creates a new review")
        .WithOpenApi();

        // PUT update review
        group.MapPut("/{id:int}", async (int id, Review review, IReviewRepository repository, IConfiguration config) =>
        {
            if (!config.GetValue<bool>("ENABLE_CRUD", true))
            {
                throw new InvalidOperationException("CRUD operations are currently disabled");
            }
            var updatedReview = await repository.UpdateAsync(id, review);
            return updatedReview is null ? Results.NotFound() : Results.Ok(updatedReview);
        })
        .WithName("UpdateReview")
        .WithDescription("Updates an existing review")
        .WithOpenApi();

        // DELETE review
        group.MapDelete("/{id:int}", async (int id, IReviewRepository repository, IConfiguration config) =>
        {
            if (!config.GetValue<bool>("ENABLE_CRUD", true))
            {
                throw new InvalidOperationException("CRUD operations are currently disabled");
            }
            var result = await repository.DeleteAsync(id);
            return result ? Results.NoContent() : Results.NotFound();
        })
        .WithName("DeleteReview")
        .WithDescription("Deletes a review")
        .WithOpenApi();
    }
}
