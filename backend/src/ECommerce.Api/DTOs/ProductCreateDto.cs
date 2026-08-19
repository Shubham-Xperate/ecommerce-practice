namespace ECommerce.Api.DTOs;

public record ProductCreateDto(
    string Name,
    string Description,
    decimal Price,
    int Stock,
    int CategoryId);
