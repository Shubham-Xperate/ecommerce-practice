namespace ECommerce.Api.DTOs;

public record OrderItemDto(
    int ProductId,
    string ProductName,
    int Quantity,
    decimal UnitPrice,
    decimal LineTotal);
